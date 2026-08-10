import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:adhan/adhan.dart' as adhan;
import '../prayer/city.dart';

/// Виджет Киблы: Режим 1 (Живой Компас с градуированной вибрацией) и Режим 2 (Интерактивная Карта).
class QiblaView extends StatefulWidget {
  final City? selectedCity;
  final bool showAppBar;
  final VoidCallback? onClose;

  const QiblaView({
    super.key,
    this.selectedCity,
    this.showAppBar = true,
    this.onClose,
  });

  @override
  State<QiblaView> createState() => _QiblaViewState();
}

class _QiblaViewState extends State<QiblaView> with SingleTickerProviderStateMixin {
  int _selectedTab = 0; // 0: Компас, 1: Карта
  Position? _currentPosition;
  bool _loadingLocation = true;
  double? _qiblaBearing;
  double _distanceToKaabaKm = 0.0;

  // Состояние вибрации (0: далеко, 1: близко (light), 2: точно (medium))
  int _hapticStage = 0;

  // Координаты Каабы в Мекке
  static const double _kaabaLat = 21.422487;
  static const double _kaabaLng = 39.826206;
  static final LatLng _kaabaPoint = const LatLng(_kaabaLat, _kaabaLng);

  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _determineLocation();
  }

  Future<void> _determineLocation() async {
    setState(() => _loadingLocation = true);
    try {
      Position? pos;
      if (await Geolocator.isLocationServiceEnabled()) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
          );
        }
      }

      final lat = pos?.latitude ?? widget.selectedCity?.lat ?? 43.238949;
      final lng = pos?.longitude ?? widget.selectedCity?.lng ?? 76.889709;

      final coords = adhan.Coordinates(lat, lng);
      final qibla = adhan.Qibla(coords).direction;
      final distanceMeters = Geolocator.distanceBetween(lat, lng, _kaabaLat, _kaabaLng);

      if (mounted) {
        setState(() {
          _currentPosition = pos ?? Position(
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
          _qiblaBearing = qibla;
          _distanceToKaabaKm = distanceMeters / 1000;
          _loadingLocation = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingLocation = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userLatLng = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(43.238949, 76.889709);

    final content = Column(
      children: [
        if (widget.showAppBar) ...[
          AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28),
              onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
            ),
            centerTitle: true,
            title: const Text(
              'Направление Киблы',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Manrope',
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ] else const SizedBox(height: 12),
        // Вкладки переключения: Локатор | Карта
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedTab = 0);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: _selectedTab == 0 ? const Color(0xFFC88D51) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.explore,
                            size: 18,
                            color: _selectedTab == 0 ? Colors.white : Colors.white60,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Локатор',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _selectedTab == 0 ? Colors.white : Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedTab = 1);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: _selectedTab == 1 ? const Color(0xFFC88D51) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.map,
                            size: 18,
                            color: _selectedTab == 1 ? Colors.white : Colors.white60,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Карта',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _selectedTab == 1 ? Colors.white : Colors.white60,
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
        const SizedBox(height: 12),
        Expanded(
          child: _loadingLocation
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFC88D51)),
                )
              : IndexedStack(
                  index: _selectedTab,
                  children: [
                    _buildCompassView(),
                    _buildMapView(userLatLng),
                  ],
                ),
        ),
      ],
    );

    if (widget.showAppBar) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F141C),
        body: SafeArea(child: content),
      );
    }
    return content;
  }

  Widget _buildCompassFallback() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.compass_calibration, size: 48, color: Color(0xFFC88D51)),
          SizedBox(height: 12),
          Text(
            'Датчик компаса недоступен\nили требует калибровки',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontFamily: 'Manrope'),
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

        final heading = snapshot.data?.heading;

        if (heading == null) {
          return _buildCompassFallback();
        }

        final qiblaAngle = _qiblaBearing ?? 244.0;
        final diff = (qiblaAngle - heading + 360) % 360;
        final absDiff = diff > 180 ? 360 - diff : diff;

        // Двухступенчатая градация вибрации:
        // Ступень 2: Точно (absDiff < 4°) -> mediumImpact
        // Ступень 1: Близко (4° <= absDiff <= 12°) -> lightImpact
        // Ступень 0: Далеко (absDiff > 12°) -> нет вибрации
        if (absDiff < 4.0) {
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

        final isExact = absDiff < 4.0;
        final isNear = absDiff <= 12.0 && !isExact;

        final statusColor = isExact
            ? const Color(0xFF4CAF50)
            : (isNear ? const Color(0xFFE5A96A) : Colors.white24);

        final statusText = isExact
            ? 'Вы смотрите точно на Киблу'
            : (isNear
                ? 'Приближаетесь к Кибле (${qiblaAngle.toStringAsFixed(0)}°)'
                : 'Поверните устройство (${qiblaAngle.toStringAsFixed(0)}°)');

        return Column(
          children: [
            const SizedBox(height: 12),
            // Индикатор статуса ориентации
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isExact
                    ? const Color(0xFF2E7D32).withValues(alpha: 0.3)
                    : (isNear ? const Color(0xFFC88D51).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.06)),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isExact ? Icons.check_circle : (isNear ? Icons.near_me : Icons.navigation),
                    color: isExact ? const Color(0xFF81C784) : const Color(0xFFC88D51),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: isExact ? const Color(0xFF81C784) : Colors.white,
                      fontFamily: 'Manrope',
                      fontSize: 14,
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
                    width: 270,
                    height: 270,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: isExact
                              ? const Color(0xFF4CAF50).withValues(alpha: 0.4)
                              : (isNear ? const Color(0xFFC88D51).withValues(alpha: 0.3) : Colors.black45),
                          blurRadius: isExact ? 30 : (isNear ? 20 : 12),
                          spreadRadius: isExact ? 4 : 0,
                        ),
                      ],
                      gradient: const RadialGradient(
                        colors: [
                          Color(0xFF1E2634),
                          Color(0xFF131A24),
                        ],
                      ),
                      border: Border.all(
                        color: isExact
                            ? const Color(0xFF81C784)
                            : (isNear ? const Color(0xFFE5A96A) : const Color(0xFF323F52)),
                        width: isExact ? 3 : 2,
                      ),
                    ),
                  ),
                  // Шкала компаса
                  Transform.rotate(
                    angle: -heading * (math.pi / 180),
                    child: SizedBox(
                      width: 250,
                      height: 250,
                      child: CustomPaint(
                        painter: _CompassDialPainter(qiblaBearing: qiblaAngle),
                      ),
                    ),
                  ),
                  // Золотая стрелка Киблы
                  Transform.rotate(
                    angle: (qiblaAngle - heading) * (math.pi / 180),
                    child: SizedBox(
                      width: 240,
                      height: 240,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isExact ? const Color(0xFF4CAF50) : const Color(0xFFC88D51),
                              boxShadow: [
                                BoxShadow(
                                  color: isExact ? const Color(0xFF4CAF50) : const Color(0xFFC88D51),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.mosque,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down,
                            size: 26,
                            color: isExact ? const Color(0xFF4CAF50) : const Color(0xFFC88D51),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Центральная тумба
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isExact ? const Color(0xFF4CAF50) : const Color(0xFFC88D51),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Плашка метаданных
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text(
                          'Азимут Киблы',
                          style: TextStyle(
                            color: Colors.white54,
                            fontFamily: 'Manrope',
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${qiblaAngle.toStringAsFixed(1)}°',
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Manrope',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Container(width: 1, height: 28, color: Colors.white12),
                    Column(
                      children: [
                        const Text(
                          'До Мекки',
                          style: TextStyle(
                            color: Colors.white54,
                            fontFamily: 'Manrope',
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_distanceToKaabaKm.toStringAsFixed(0)} км',
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Manrope',
                            fontSize: 17,
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

  /// Режим 2: Интерактивная Карта
  Widget _buildMapView(LatLng userLatLng) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: userLatLng,
            initialZoom: 5.5,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'kz.dauam.jadwal',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: [userLatLng, _kaabaPoint],
                  strokeWidth: 4.0,
                  color: const Color(0xFFC88D51),
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: userLatLng,
                  width: 44,
                  height: 44,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2E7D32),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 8),
                      ],
                    ),
                    child: const Icon(
                      Icons.my_location,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                Marker(
                  point: _kaabaPoint,
                  width: 50,
                  height: 50,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFC88D51),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 10),
                      ],
                    ),
                    child: const Icon(
                      Icons.mosque,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 20,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'center_user',
                backgroundColor: const Color(0xFF1E2634),
                child: const Icon(Icons.my_location, color: Colors.white),
                onPressed: () {
                  _mapController.move(userLatLng, 12.0);
                },
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'center_kaaba',
                backgroundColor: const Color(0xFFC88D51),
                child: const Icon(Icons.mosque, color: Colors.white),
                onPressed: () {
                  _mapController.move(_kaabaPoint, 12.0);
                },
              ),
            ],
          ),
        ),
      ],
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

    const textStyleN = TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold);
    const textStyleOther = TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold);

    _drawText(canvas, center, radius - 24, 0, 'N', textStyleN);
    _drawText(canvas, center, radius - 24, 90, 'E', textStyleOther);
    _drawText(canvas, center, radius - 24, 180, 'S', textStyleOther);
    _drawText(canvas, center, radius - 24, 270, 'W', textStyleOther);
  }

  void _drawText(Canvas canvas, Offset center, double distance, double angleDeg, String text, TextStyle style) {
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
    painter.paint(canvas, Offset(pos.dx - painter.width / 2, pos.dy - painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
