import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:adhan/adhan.dart' as adhan;
import '../prayer/city.dart';
import '../theme/tokens.dart';
import '../theme/adaptive_layout.dart';
import '../data/app_state.dart';
import '../i18n/strings.dart';
import '../services/compass_capability_service.dart';
import 'swipe_hint.dart';

enum _CompassAvailability { checking, available, unavailable, noData, unknown }

/// Виджет Киблы: Режим 1 (Живой Компас с градуированной вибрацией) и Режим 2 (Интерактивная Карта).
class QiblaView extends StatefulWidget {
  final City? selectedCity;
  final bool showAppBar;
  final bool embedded;
  final bool hapticsEnabled;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureDragCancelCallback? onVerticalDragCancel;
  final Future<bool?> Function()? compassAvailabilityProbe;

  const QiblaView({
    super.key,
    this.selectedCity,
    this.showAppBar = true,
    this.embedded = false,
    this.hapticsEnabled = true,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onVerticalDragCancel,
    this.compassAvailabilityProbe,
  });

  @override
  State<QiblaView> createState() => _QiblaViewState();
}

class _QiblaViewState extends State<QiblaView>
    with SingleTickerProviderStateMixin {
  int _selectedTab = 0; // 0: Компас, 1: Карта
  Position? _currentPosition;
  double? _qiblaBearing;
  double _distanceToKaabaKm = 0.0;
  double? _filteredHeading;
  int _mapReloadGeneration = 0;
  _CompassAvailability _compassAvailability = _CompassAvailability.checking;
  Timer? _compassDataTimer;
  bool _receivedCompassSample = false;

  // Состояние вибрации (0: далеко, 1: близко (light), 2: точно (medium))
  int _hapticStage = 0;

  // Координаты Каабы в Мекке
  static const double _kaabaLat = 21.422487;
  static const double _kaabaLng = 39.826206;
  final MapController _mapController = MapController();

  int get selectedTab => _selectedTab;

  @override
  void didUpdateWidget(covariant QiblaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hapticsEnabled && !widget.hapticsEnabled) {
      _hapticStage = 0;
    }
  }

  @override
  void initState() {
    super.initState();
    // Сразу показываем рабочий локатор по координатам выбранного города, а
    // более точная GPS-позиция бесшовно подменит их после ответа системы.
    // Так карта не ждёт долгий bestForNavigation-запрос пустым экраном.
    _applyPosition(null, notify: false);
    _determineLocation();
    _checkCompassCapability();
  }

  @override
  void dispose() {
    _compassDataTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkCompassCapability() async {
    bool? available;
    try {
      available =
          await (widget.compassAvailabilityProbe ??
              CompassCapabilityService.isAvailable)();
    } catch (_) {
      available = null;
    }
    if (!mounted) return;

    if (available == false) {
      _compassDataTimer?.cancel();
      _hapticStage = 0;
      setState(() {
        _compassAvailability = _CompassAvailability.unavailable;
        _selectedTab = 1;
      });
      return;
    }

    setState(() {
      _compassAvailability = available == true
          ? _CompassAvailability.available
          : _CompassAvailability.unknown;
    });
    if (available == true) _armCompassDataWatchdog();
  }

  void _armCompassDataWatchdog() {
    _compassDataTimer?.cancel();
    if (_compassAvailability != _CompassAvailability.available ||
        _selectedTab != 0) {
      return;
    }
    _receivedCompassSample = false;
    _compassDataTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted ||
          _receivedCompassSample ||
          _compassAvailability != _CompassAvailability.available ||
          _selectedTab != 0) {
        return;
      }
      _hapticStage = 0;
      setState(() {
        _compassAvailability = _CompassAvailability.noData;
        _selectedTab = 1;
      });
    });
  }

  void _markCompassSampleReceived() {
    _receivedCompassSample = true;
    _compassDataTimer?.cancel();
  }

  void _selectLocator() {
    if (_compassAvailability == _CompassAvailability.unavailable) {
      _showCompassUnavailableMessage();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _selectedTab = 0;
      if (_compassAvailability == _CompassAvailability.noData) {
        _compassAvailability = _CompassAvailability.available;
      }
    });
    _armCompassDataWatchdog();
  }

  void _selectMap() {
    HapticFeedback.selectionClick();
    _compassDataTimer?.cancel();
    _hapticStage = 0;
    setState(() => _selectedTab = 1);
  }

  void _showCompassUnavailableMessage() {
    final kz = AppScope.of(context).lang == 'kz';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          kz
              ? 'Бұл құрылғыда компас датчигі жоқ. Құбыла бағытын картадан қараңыз.'
              : 'На этом устройстве нет датчика компаса. Используйте карту.',
        ),
      ),
    );
  }

  Future<void> _determineLocation() async {
    try {
      Position? pos;
      if (await Geolocator.isLocationServiceEnabled()) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.whileInUse ||
            perm == LocationPermission.always) {
          try {
            pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 12),
              ),
            );
          } catch (_) {
            // Keep the Qibla screen responsive when a fresh GPS fix is slow
            // (common indoors and on entry-level Android devices).
            pos = await Geolocator.getLastKnownPosition();
          }
        }
      }
      if (pos != null && mounted && _isUsablePosition(pos)) {
        _applyPosition(pos);
      }
    } catch (_) {
      // The selected city remains a safe fallback for the Qibla direction.
    }
  }

  bool _isUsablePosition(Position position) {
    return position.latitude.isFinite &&
        position.longitude.isFinite &&
        position.latitude.abs() <= 90 &&
        position.longitude.abs() <= 180 &&
        position.accuracy.isFinite &&
        position.accuracy >= 0 &&
        position.accuracy <= 5000;
  }

  void _applyPosition(Position? position, {bool notify = true}) {
    final lat = position?.latitude ?? widget.selectedCity?.lat ?? 43.238949;
    final lng = position?.longitude ?? widget.selectedCity?.lng ?? 76.889709;
    final resolved =
        position ??
        Position(
          latitude: lat,
          longitude: lng,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
    final qibla = adhan.Qibla(adhan.Coordinates(lat, lng)).direction;
    final distanceKm =
        Geolocator.distanceBetween(lat, lng, _kaabaLat, _kaabaLng) / 1000;

    void apply() {
      _currentPosition = resolved;
      _qiblaBearing = qibla;
      _distanceToKaabaKm = distanceKm;
    }

    if (notify) {
      setState(apply);
      if (_selectedTab == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            _mapController.move(LatLng(lat, lng), 16.2);
          } catch (_) {}
        });
      }
    } else {
      apply();
    }
  }

  bool _minimal(BuildContext context) =>
      widget.embedded && AppScope.of(context).dayLayout == 'pages';

  @override
  Widget build(BuildContext context) {
    final expanded = isExpandedLayout(context);
    final userLatLng = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(43.238949, 76.889709);

    // Минималистичная Кибла для прототипа «Страницы»: одна подпись вместо
    // заголовка и крупного переключателя, карта — круглой кнопкой.
    final minimal = _minimal(context);
    final kz = AppScope.of(context).lang == 'kz';

    final content = AdaptiveContentPane(
      expandedMaxWidth: 980,
      child: Column(
        children: [
          if (minimal)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      kz ? 'ҚҰБЫЛА' : 'КИБЛА',
                      style: JType.caption(const Color(0xFFE5B872), size: 12),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: _selectedTab == 0
                        ? (kz ? 'Картаны ашу' : 'Открыть карту')
                        : (kz ? 'Локаторға оралу' : 'Вернуться к локатору'),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _selectedTab == 0 ? _selectMap() : _selectLocator();
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Icon(
                          _selectedTab == 0
                              ? Icons.map_outlined
                              : Icons.explore,
                          size: 19,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (widget.showAppBar) ...[
            AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              centerTitle: true,
              title: Text(
                'Направление Киблы',
                style: JType.ui(
                  expanded ? 23 : 18,
                  color: Colors.white,
                  w: FontWeight.w700,
                ),
              ),
            ),
          ] else
            const SizedBox(height: 12),
          // Вкладки переключения: Локатор | Карта
          if (!minimal)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: expanded ? 56 : 44,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.13),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _selectLocator,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: _selectedTab == 0
                                ? const Color(
                                    0xFFC88D51,
                                  ).withValues(alpha: 0.90)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.explore,
                                size: expanded ? 22 : 18,
                                color:
                                    _compassAvailability ==
                                        _CompassAvailability.unavailable
                                    ? Colors.white30
                                    : (_selectedTab == 0
                                          ? Colors.white
                                          : Colors.white60),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Локатор',
                                style: JType.ui(
                                  expanded ? 17 : 14,
                                  w: FontWeight.w600,
                                  color:
                                      _compassAvailability ==
                                          _CompassAvailability.unavailable
                                      ? Colors.white30
                                      : (_selectedTab == 0
                                            ? Colors.white
                                            : Colors.white60),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _selectMap,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: _selectedTab == 1
                                ? const Color(
                                    0xFFC88D51,
                                  ).withValues(alpha: 0.90)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.map,
                                size: expanded ? 22 : 18,
                                color: _selectedTab == 1
                                    ? Colors.white
                                    : Colors.white60,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Карта',
                                style: JType.ui(
                                  expanded ? 17 : 14,
                                  w: FontWeight.w600,
                                  color: _selectedTab == 1
                                      ? Colors.white
                                      : Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_compassAvailability == _CompassAvailability.unavailable ||
              _compassAvailability == _CompassAvailability.noData)
            _buildCompassNotice(),
          const SizedBox(height: 12),
          Expanded(
            child: _selectedTab == 0
                ? _buildReturnSwipeRegion(
                    key: const ValueKey('qibla-locator-return-zone'),
                    child: _buildCompassView(),
                  )
                // Карта создаётся уже в видимом размере. Скрытая инициализация
                // внутри IndexedStack могла оставить загруженным один тайл.
                : _buildMapView(userLatLng),
          ),
          if (widget.embedded &&
              _selectedTab == 0 &&
              widget.onVerticalDragStart != null)
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: SwipeHint(
                  key: const ValueKey('qibla-return-swipe-hint'),
                  label: S.of(AppScope.of(context).lang).swipeBack,
                  direction: SwipeHintDirection.down,
                  color: Colors.white.withValues(alpha: 0.88),
                  shadows: const [
                    Shadow(
                      color: Colors.black54,
                      offset: Offset(0, 1),
                      blurRadius: 2.5,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.embedded) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(child: content),
      );
    }
    if (widget.showAppBar) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F141C),
        body: SafeArea(child: content),
      );
    }
    return content;
  }

  Widget _buildReturnSwipeRegion({Key? key, required Widget child}) {
    if (widget.onVerticalDragStart == null) return child;
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: widget.onVerticalDragStart,
      onVerticalDragUpdate: widget.onVerticalDragUpdate,
      onVerticalDragEnd: widget.onVerticalDragEnd,
      onVerticalDragCancel: widget.onVerticalDragCancel,
      child: child,
    );
  }

  Widget _buildCompassNotice() {
    final kz = AppScope.of(context).lang == 'kz';
    final noSensor = _compassAvailability == _CompassAvailability.unavailable;
    final message = noSensor
        ? (kz
              ? 'Бұл құрылғыда компас датчигі жоқ. Құбыла бағыты картада көрсетілді.'
              : 'На этом устройстве нет датчика компаса. Направление Киблы показано на карте.')
        : (kz
              ? 'Компас деректері алынбады. Құбыла бағытын картадан қараңыз.'
              : 'Не удалось получить данные компаса. Используйте карту.');

    return Padding(
      key: const ValueKey('qibla-compass-notice'),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFC88D51).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFE5A96A).withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          children: [
            Icon(
              noSensor ? Icons.sensors_off_rounded : Icons.info_outline_rounded,
              color: const Color(0xFFE7B76A),
              size: 21,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: JType.ui(
                  isExpandedLayout(context) ? 15 : 12,
                  color: Colors.white.withValues(alpha: 0.9),
                  w: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompassFallback([String? message]) {
    final kz = AppScope.of(context).lang == 'kz';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.compass_calibration,
            size: 48,
            color: Color(0xFFC88D51),
          ),
          const SizedBox(height: 12),
          Text(
            message ??
                (kz
                    ? 'Компас деректерін алып жатырмыз…'
                    : 'Получаем данные компаса…'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'Manrope',
            ),
          ),
        ],
      ),
    );
  }

  Stream<CompassEvent>? get _safeCompassStream {
    try {
      return FlutterCompass.events;
    } catch (_) {
      return null;
    }
  }

  /// Режим 1: Интерактивный Компас Киблы с 2-ступенчатой градацией вибрации
  Widget _buildCompassView() {
    if (_compassAvailability == _CompassAvailability.checking) {
      return _buildCompassFallback();
    }
    final stream = _safeCompassStream?.handleError((e, s) {});
    if (stream == null) {
      return _buildCompassFallback();
    }
    return StreamBuilder<CompassEvent>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return _buildCompassFallback();
        }

        final rawHeading = snapshot.data?.heading;

        // Core Location uses exactly -1 when true north is temporarily
        // unavailable. It must not be normalized to 359° and shown as a real
        // Qibla direction; the watchdog will move the user to the map instead.
        if (rawHeading == null || !rawHeading.isFinite || rawHeading == -1.0) {
          return _buildCompassFallback();
        }

        _markCompassSampleReceived();
        final heading = _smoothHeading(rawHeading);
        final accuracy = snapshot.data?.accuracy;
        final needsCalibration = accuracy != null && accuracy > 30;
        final qiblaAngle = _qiblaBearing ?? 244.0;
        final diff = (qiblaAngle - heading + 360) % 360;
        final absDiff = diff > 180 ? 360 - diff : diff;

        // Двухступенчатая градация вибрации:
        // Ступень 2: Точно (absDiff < 4°) -> mediumImpact
        // Ступень 1: Близко (4° <= absDiff <= 12°) -> lightImpact
        // Ступень 0: Далеко (absDiff > 12°) -> нет вибрации
        final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
        final canUseHaptics =
            widget.hapticsEnabled &&
            _selectedTab == 0 &&
            routeIsCurrent &&
            TickerMode.valuesOf(context).enabled &&
            !needsCalibration;

        if (!canUseHaptics) {
          _hapticStage = 0;
        } else if (absDiff < 4.0) {
          if (_hapticStage != 2) {
            _hapticStage = 2;
            HapticFeedback.mediumImpact();
          }
        } else if (absDiff <= 12.0) {
          if (_hapticStage != 1) {
            _hapticStage = 1;
            HapticFeedback.lightImpact();
          }
        } else {
          _hapticStage = 0;
        }

        final isExact = absDiff < 4.0 && !needsCalibration;
        final isNear = absDiff <= 12.0 && !isExact && !needsCalibration;

        final statusColor = needsCalibration
            ? const Color(0xFFE5A96A)
            : (isExact
                  ? const Color(0xFF4CAF50)
                  : (isNear ? const Color(0xFFE5A96A) : Colors.white24));

        final kz = AppScope.of(context).lang == 'kz';
        final statusText = needsCalibration
            ? (kz
                  ? 'Компасты калибрлеңіз: телефонды сегіз түрінде қозғаңыз'
                  : 'Откалибруйте компас: двигайте телефон восьмёркой')
            : (isExact
                  ? (kz
                        ? 'Сіз Құбылаға дәл қарап тұрсыз'
                        : 'Вы смотрите точно на Киблу')
                  : (isNear
                        ? (kz
                              ? 'Құбылаға жақындадыңыз (${qiblaAngle.toStringAsFixed(0)}°)'
                              : 'Приближаетесь к Кибле (${qiblaAngle.toStringAsFixed(0)}°)')
                        : (kz
                              ? 'Құрылғыны бұрыңыз (${qiblaAngle.toStringAsFixed(0)}°)'
                              : 'Поверните устройство (${qiblaAngle.toStringAsFixed(0)}°)')));

        final expanded = isExpandedLayout(context);
        final minimal = _minimal(context);
        // В минимальном виде подсказка говорит, куда и на сколько
        // повернуться, а не абсолютный азимут.
        final turn = diff <= 180 ? diff : 360 - diff;
        final turnText = needsCalibration
            ? statusText
            : isExact
            ? (kz ? 'Құбылаға қарап тұрсыз' : 'Вы смотрите на Киблу')
            : diff <= 180
            ? (kz
                  ? 'Оңға ${turn.toStringAsFixed(0)}° бұрылыңыз'
                  : 'Повернитесь вправо на ${turn.toStringAsFixed(0)}°')
            : (kz
                  ? 'Солға ${turn.toStringAsFixed(0)}° бұрылыңыз'
                  : 'Повернитесь влево на ${turn.toStringAsFixed(0)}°');
        final compassSize = expanded ? 340.0 : 270.0;
        final dialSize = expanded ? 316.0 : 250.0;
        final arrowSize = expanded ? 304.0 : 240.0;

        return Column(
          children: [
            const SizedBox(height: 12),
            if (minimal)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: JType.ui(
                    16,
                    w: FontWeight.w600,
                    color: isExact
                        ? const Color(0xFF81C784)
                        : Colors.white.withValues(alpha: 0.92),
                  ),
                  child: Text(turnText, textAlign: TextAlign.center),
                ),
              )
            else
              // Индикатор статуса ориентации
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 26 : 20,
                  vertical: expanded ? 13 : 10,
                ),
                decoration: BoxDecoration(
                  color: needsCalibration
                      ? const Color(0xFFC88D51).withValues(alpha: 0.2)
                      : isExact
                      ? const Color(0xFF2E7D32).withValues(alpha: 0.3)
                      : (isNear
                            ? const Color(0xFFC88D51).withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.06)),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      needsCalibration
                          ? Icons.compass_calibration
                          : isExact
                          ? Icons.check_circle
                          : (isNear ? Icons.near_me : Icons.navigation),
                      color: isExact
                          ? const Color(0xFF81C784)
                          : const Color(0xFFC88D51),
                      size: expanded ? 24 : 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: isExact ? const Color(0xFF81C784) : Colors.white,
                        fontFamily: 'Manrope',
                        fontSize: expanded ? 17 : 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            // Диск компаса
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Внешнее кольцо с динамической подсветкой
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: compassSize,
                    height: compassSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: isExact
                              ? const Color(0xFF4CAF50).withValues(alpha: 0.4)
                              : (isNear
                                    ? const Color(
                                        0xFFC88D51,
                                      ).withValues(alpha: 0.3)
                                    : Colors.black45),
                          blurRadius: isExact ? 30 : (isNear ? 20 : 12),
                          spreadRadius: isExact ? 4 : 0,
                        ),
                      ],
                      gradient: const RadialGradient(
                        colors: [Color(0xD91E2634), Color(0xC7131A24)],
                      ),
                      border: Border.all(
                        color: isExact
                            ? const Color(0xFF81C784)
                            : (isNear
                                  ? const Color(0xFFE5A96A)
                                  : const Color(0xFF323F52)),
                        width: isExact ? 3 : 2,
                      ),
                    ),
                  ),
                  // Шкала компаса
                  Transform.rotate(
                    angle: -heading * (math.pi / 180),
                    child: SizedBox(
                      width: dialSize,
                      height: dialSize,
                      child: CustomPaint(
                        painter: _CompassDialPainter(qiblaBearing: qiblaAngle),
                      ),
                    ),
                  ),
                  // Золотая стрелка Киблы
                  Transform.rotate(
                    angle: (qiblaAngle - heading) * (math.pi / 180),
                    child: SizedBox(
                      width: arrowSize,
                      height: arrowSize,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isExact
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFC88D51),
                              boxShadow: [
                                BoxShadow(
                                  color: isExact
                                      ? const Color(0xFF4CAF50)
                                      : const Color(0xFFC88D51),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.mosque,
                              size: expanded ? 25 : 20,
                              color: Colors.white,
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down,
                            size: expanded ? 32 : 26,
                            color: isExact
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFC88D51),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Центральная тумба
                  Container(
                    width: expanded ? 23 : 18,
                    height: expanded ? 23 : 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isExact
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFC88D51),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (minimal)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  kz
                      ? 'Мекке · ${_distanceToKaabaKm.toStringAsFixed(0)} км'
                      : 'Мекка · ${_distanceToKaabaKm.toStringAsFixed(0)} км',
                  style: JType.ui(
                    13,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              )
            else
              // Плашка метаданных
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.17),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            'Азимут Киблы',
                            style: TextStyle(
                              color: Colors.white54,
                              fontFamily: 'Manrope',
                              fontSize: expanded ? 15 : 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${qiblaAngle.toStringAsFixed(1)}°',
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'Manrope',
                              fontSize: expanded ? 21 : 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Container(width: 1, height: 28, color: Colors.white12),
                      Column(
                        children: [
                          Text(
                            'До Мекки',
                            style: TextStyle(
                              color: Colors.white54,
                              fontFamily: 'Manrope',
                              fontSize: expanded ? 15 : 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_distanceToKaabaKm.toStringAsFixed(0)} км',
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'Manrope',
                              fontSize: expanded ? 21 : 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  double _smoothHeading(double rawHeading) {
    final normalized = (rawHeading % 360 + 360) % 360;
    final previous = _filteredHeading;
    if (previous == null) {
      _filteredHeading = normalized;
      return normalized;
    }

    // Кратчайшая дуга важна около границы 359°→0°: обычное среднее дало бы
    // ложный скачок к югу. Коэффициент оставляет реакцию живой, но гасит
    // одиночные выбросы магнитометра.
    final delta = ((normalized - previous + 540) % 360) - 180;
    final filtered = (previous + delta * 0.24 + 360) % 360;
    _filteredHeading = filtered;
    return filtered;
  }

  /// Режим 2: Интерактивная Карта
  Widget _buildMapView(LatLng userLatLng) {
    final qiblaAngle = _qiblaBearing ?? 244.0;
    final directionPoint = const Distance().offset(userLatLng, 700, qiblaAngle);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF14273A),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Stack(
            children: [
              FlutterMap(
                key: const ValueKey('qibla-map'),
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: userLatLng,
                  initialZoom: 16.2,
                  minZoom: 14,
                  maxZoom: 19,
                  backgroundColor: const Color(0xFF14273A),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                    enableMultiFingerGestureRace: true,
                  ),
                ),
                children: [
                  TileLayer(
                    key: ValueKey('qibla-tiles-$_mapReloadGeneration'),
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'kz.dauam',
                    panBuffer: 0,
                    tileDisplay: const TileDisplay.instantaneous(),
                    evictErrorTileStrategy:
                        EvictErrorTileStrategy.notVisibleRespectMargin,
                    tileBuilder: _buildDauamTile,
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [userLatLng, directionPoint],
                        strokeWidth: 8,
                        color: Colors.black.withValues(alpha: 0.22),
                      ),
                      Polyline(
                        points: [userLatLng, directionPoint],
                        strokeWidth: 3.5,
                        color: const Color(0xFFE7B76A),
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: userLatLng,
                        width: 42,
                        height: 42,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFF8F4EA),
                            border: Border.all(
                              color: const Color(0xFFC88D51),
                              width: 4,
                            ),
                            boxShadow: const [
                              BoxShadow(color: Colors.black38, blurRadius: 12),
                            ],
                          ),
                          child: const Icon(
                            Icons.my_location,
                            color: Color(0xFF203A53),
                            size: 18,
                          ),
                        ),
                      ),
                      Marker(
                        point: directionPoint,
                        width: 52,
                        height: 52,
                        child: Transform.rotate(
                          angle: qiblaAngle * math.pi / 180,
                          child: const Icon(
                            Icons.navigation_rounded,
                            color: Color(0xFFE7B76A),
                            size: 42,
                            shadows: [
                              Shadow(color: Colors.black45, blurRadius: 10),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Positioned(
                left: 12,
                top: 12,
                right: 12,
                child: _MapGlassLabel(
                  icon: Icons.near_me_rounded,
                  text: 'Ваш район · Кибла ${qiblaAngle.round()}°',
                ),
              ),
              Positioned(
                left: 12,
                bottom: 12,
                child: Text(
                  '© OpenStreetMap',
                  style: JType.ui(
                    9,
                    color: Colors.white.withValues(alpha: 0.6),
                    w: FontWeight.w500,
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: IconButton.filled(
                  key: const ValueKey('qibla-map-center-button'),
                  tooltip: 'Вернуться к моему местоположению',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xDD203A53),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _centerMap,
                  icon: const Icon(Icons.my_location, size: 20),
                ),
              ),
              if (widget.onVerticalDragStart != null) ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 24,
                  child: _buildReturnSwipeRegion(
                    key: const ValueKey('qibla-map-left-return-zone'),
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 24,
                  child: _buildReturnSwipeRegion(
                    key: const ValueKey('qibla-map-right-return-zone'),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDauamTile(
    BuildContext context,
    Widget tile,
    TileImage tileImage,
  ) {
    return ColorFiltered(
      // Фирменная сине-серая карта средней яркости. Все исходные цвета OSM
      // сводятся к единой холодной шкале, но тёмные подписи и светлые дороги
      // сохраняют достаточный диапазон контраста.
      colorFilter: const ColorFilter.matrix(<double>[
        0.15,
        0.30,
        0.06,
        0,
        26,
        0.16,
        0.32,
        0.06,
        0,
        38,
        0.17,
        0.34,
        0.07,
        0,
        54,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: tile,
    );
  }

  void _centerMap() {
    final position = _currentPosition;
    if (position == null || !_isUsablePosition(position)) return;
    final target = LatLng(position.latitude, position.longitude);
    var zoom = 16.2;
    try {
      zoom = _mapController.camera.zoom.clamp(14.0, 19.0).toDouble();
    } catch (_) {}

    // Новый ключ заставляет повторно запросить тайлы, если сеть оборвалась и
    // предыдущий неудачный ответ остался в image cache.
    setState(() => _mapReloadGeneration++);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(target, zoom);
      } catch (_) {}
    });
  }
}

class _MapGlassLabel extends StatelessWidget {
  const _MapGlassLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xE6203A53),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: const Color(0xFFE7B76A)),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JType.ui(12, color: Colors.white, w: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QiblaScreen extends StatelessWidget {
  final City? selectedCity;

  const QiblaScreen({super.key, this.selectedCity});

  @override
  Widget build(BuildContext context) {
    return QiblaView(selectedCity: selectedCity, showAppBar: true);
  }
}

class _CompassDialPainter extends CustomPainter {
  final double qiblaBearing;

  _CompassDialPainter({required this.qiblaBearing});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paintTick = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.5;

    final paintMainTick = Paint()
      ..color = Colors.white60
      ..strokeWidth = 2.0;

    for (int i = 0; i < 360; i += 5) {
      final isMain = i % 30 == 0;
      final tickLength = isMain ? 12.0 : 6.0;
      final angle = i * (math.pi / 180);

      final start = Offset(
        center.dx + (radius - tickLength) * math.sin(angle),
        center.dy - (radius - tickLength) * math.cos(angle),
      );
      final end = Offset(
        center.dx + radius * math.sin(angle),
        center.dy - radius * math.cos(angle),
      );

      canvas.drawLine(start, end, isMain ? paintMainTick : paintTick);
    }

    const textStyleN = TextStyle(
      color: Colors.redAccent,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    );
    const textStyleOther = TextStyle(
      color: Colors.white70,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );

    _drawText(canvas, center, radius - 24, 0, 'N', textStyleN);
    _drawText(canvas, center, radius - 24, 90, 'E', textStyleOther);
    _drawText(canvas, center, radius - 24, 180, 'S', textStyleOther);
    _drawText(canvas, center, radius - 24, 270, 'W', textStyleOther);
  }

  void _drawText(
    Canvas canvas,
    Offset center,
    double distance,
    double angleDeg,
    String text,
    TextStyle style,
  ) {
    final angle = angleDeg * (math.pi / 180);
    final pos = Offset(
      center.dx + distance * math.sin(angle),
      center.dy - distance * math.cos(angle),
    );

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(
      canvas,
      Offset(pos.dx - painter.width / 2, pos.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
