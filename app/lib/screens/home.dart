import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hijri/hijri_calendar.dart';
import '../data/app_state.dart';
import '../i18n/strings.dart';
import '../notifications/notifications.dart';
import '../prayer/schedule.dart';
import '../prayer/schedule_service.dart';
import '../prayer/windows.dart';
import '../theme/tokens.dart';
import '../theme/system_bars.dart';
import 'city_picker.dart';
import 'language_picker.dart';
import 'qibla_screen.dart';
import 'reader.dart';
import 'reminders.dart';
import 'scene_background.dart';

import '../services/live_activity_service.dart';
import '../services/location_checker_service.dart';
import '../services/widget_data_service.dart';

/// Экспериментальный современный нижний экран. Классический слой оставлен в
/// этом файле на время проверки владельцем; полный исходник также сохранён в
/// `tmp/lower-screen-rollback-2026-07-22/` для точного отката.
const _modernLowerScreen = true;

/// Главный экран = центральная страница вертикальной ленты из трёх экранов:
/// Кибла сверху, таймер по центру, дела дня снизу. С каждого соседнего экрана
/// встречный свайп возвращает пользователя к центральному таймеру.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  Timer? _ticker;
  String _lastNotifSig = '';
  String _lastLiveActivityMinute = '';
  String _lastWidgetSignature = '';
  bool _widgetSyncInFlight = false;
  bool _hasSwipedHaptic = false;
  double _dragStartProgress = 0.0;
  late final AnimationController _p = AnimationController(
    vsync: this,
    lowerBound: -1.0,
    upperBound: 1.0,
    duration: const Duration(milliseconds: 420),
  );

  double get swipeProgress => _p.value;
  set swipeProgress(double v) {
    _p.value = v;
    _dragStartProgress = v;
  }

  void _onDragStart(DragStartDetails _) {
    _dragStartProgress = _p.value;
    _hasSwipedHaptic = false;
  }

  void _onDragUpdate(DragUpdateDetails d, double h) {
    if (d.primaryDelta == null) return;
    if (_p.value == 0.0 && !_hasSwipedHaptic) {
      HapticFeedback.lightImpact();
      _hasSwipedHaptic = true;
    }
    // На крайних экранах блокируем только движение дальше за границу ленты,
    // но оставляем встречный свайп свободным для возврата к таймеру.
    if (_p.value >= 0.95 && d.primaryDelta! < 0) {
      return;
    }
    if (_p.value <= -0.95 && d.primaryDelta! > 0) {
      return;
    }
    _p.value = (_p.value - d.primaryDelta! / h).clamp(-1.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    _hasSwipedHaptic = false;
    final v = d.primaryVelocity ?? 0;
    final movement = _p.value - _dragStartProgress;
    final startPage = _dragStartProgress.round().clamp(-1, 1);
    final direction = movement.abs() >= 0.10
        ? movement.sign.toInt()
        : v.abs() >= 300
        ? (v < 0 ? 1 : -1)
        : 0;
    final target = (startPage + direction).clamp(-1, 1).toDouble();
    _p.animateTo(target, curve: Curves.easeOutCubic);
  }

  void _onDragCancel() {
    _hasSwipedHaptic = false;
    _p.animateTo(
      _dragStartProgress.round().clamp(-1, 1).toDouble(),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToSiriChannel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Разрешение на уведомления
      await gNotifier?.requestPermission();
      if (!mounted) return;
      syncNotifications(AppScope.of(context), ScheduleScope.of(context));

      // Авто-проверка смены города по GPS
      LocationCheckerService.checkLocationChange(
        context: context,
        currentCity: AppScope.of(context).city,
        onCitySelected: (newCity) {
          if (!mounted) return;
          setState(() {
            AppScope.of(context).setCity(newCity);
          });
          syncNotifications(AppScope.of(context), ScheduleScope.of(context));
        },
      );

      // По тапу на уведомление или по команде Siri — открыть соответствующий сборник.
      final pending = gNotifier?.pendingCollection;
      if (pending != null && pending.isNotEmpty && mounted) {
        gNotifier!.pendingCollection = null;
        _openReader(pending);
      } else {
        _checkSiriTarget();
      }
    });
  }

  void _listenToSiriChannel() {
    const channel = MethodChannel('kz.dauam/widgets');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onSiriTargetReceived') {
        final target = call.arguments as String?;
        if (target != null && target.isNotEmpty && mounted) {
          _openReader(target, autoStartSpeech: true);
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSiriTarget();
    }
  }

  void _checkSiriTarget() async {
    try {
      const channel = MethodChannel('kz.dauam/widgets');
      final siriTarget = await channel.invokeMethod<String>(
        'getPendingIntentTarget',
      );
      if (siriTarget != null && siriTarget.isNotEmpty && mounted) {
        _openReader(siriTarget, autoStartSpeech: true);
      }
    } catch (_) {}
  }

  /// Умное приближение намаза (Сценарий A): Dynamic Island за 15 минут
  /// до одного из пяти намазов. Восход намеренно исключён: это не намаз.
  void _syncPrayerProximity(AppState app, ScheduleService schedule) {
    final now = schedule.now();
    final t = schedule.timesFor(app.city, now);
    if (t == null) {
      LiveActivityService.stopPrayerProximity();
      return;
    }
    final nowMin = now.hour * 60 + now.minute;
    final next = nextNamaz(t, nowMin);
    if (next != null) {
      final targetMin = t.times[next]!;
      final remainingMin = targetMin - nowMin;
      if (remainingMin > 0 && remainingMin <= 15) {
        final s = S.of(app.lang);
        final targetTime = DateTime(
          now.year,
          now.month,
          now.day,
          targetMin ~/ 60,
          targetMin % 60,
        );
        LiveActivityService.startPrayerProximity(
          prayerName: s.prayers[next.index],
          cityName: app.city.name,
          targetTime: targetTime,
        );
        return;
      }
    }
    // Если ближайший намаз ещё далеко или уже наступил, старый автоматический
    // отсчёт не должен оставаться в Dynamic Island с нулём.
    LiveActivityService.stopPrayerProximity();
  }

  void _syncPrayerProximityIfNeeded(AppState app, ScheduleService schedule) {
    final now = schedule.now();
    final key = '${now.year}-${now.month}-${now.day}-${now.hour}-${now.minute}';
    if (key == _lastLiveActivityMinute) return;
    _lastLiveActivityMinute = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPrayerProximity(app, schedule);
    });
  }

  /// Перепланировать уведомления, только когда изменилось что-то значимое
  /// (город / язык / набор выполненного за сегодня).
  void _syncNotificationsIfNeeded(AppState app, ScheduleService schedule) {
    final sig =
        '${app.city.name}|${app.lang}|'
        '${TaskId.values.where((id) => app.isDone(id.name)).join(",")}';
    if (sig == _lastNotifSig) return;
    _lastNotifSig = sig;
    syncNotifications(app, schedule);
  }

  /// WidgetKit получает новый снимок только при изменении значимых данных.
  /// Посекундный countdown внутри виджета рисует сама iOS.
  void _syncWidgetsIfNeeded(
    AppState app,
    ScheduleService schedule,
    S s,
    DayTimes times,
    DateTime now,
  ) {
    final done = app.taskProgressOn(times.date);
    final custom = app.customReminders
        .where((item) => app.reminderOccursOn(item, times.date))
        .map(
          (item) =>
              '${item.id}:${item.title}:${item.enabled}:'
              '${app.isDone('custom:${item.id}')}',
        )
        .join('|');
    final prayerTimes = Prayer.values
        .map((prayer) => times.times[prayer])
        .join(',');
    final signature =
        '${AppState.dayKey(now)}|${app.city.latStr}|${app.city.lngStr}|'
        '${app.lang}|$prayerTimes|${done.$1}/${done.$2}|'
        '${app.isDone('morning')}:${app.isDone('kahf')}:'
        '${app.isDone('evening')}:${app.isDone('dua')}|$custom';
    if (signature == _lastWidgetSignature || _widgetSyncInFlight) return;
    _widgetSyncInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _widgetSyncInFlight = false;
        return;
      }
      final saved = await WidgetDataService.sync(
        app: app,
        schedule: schedule,
        strings: s,
        today: times,
        now: now,
        dateLabel: dateLine(s, now, app.dateGregorian),
      );
      if (mounted && saved) {
        _lastWidgetSignature = signature;
      }
      _widgetSyncInFlight = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _p.dispose();
    super.dispose();
  }

  void _openReader(String collectionId, {bool autoStartSpeech = false}) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ReaderScreen(
            collectionId: collectionId,
            autoStartSpeech: autoStartSpeech,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final schedule = ScheduleScope.of(context);
    final s = S.of(app.lang);
    // Художественный фон ночной → главный/день всегда со светлым текстом,
    // независимо от темы приложения. Сменные фоны придут в настройки позже.
    const c = JColors.dark;
    final now = schedule.now();
    final t = schedule.timesFor(app.city, now);
    final nowSec = now.hour * 3600 + now.minute * 60 + now.second;
    final nowMin = nowSec ~/ 60;
    _syncNotificationsIfNeeded(app, schedule);
    _syncPrayerProximityIfNeeded(app, schedule);
    if (t != null) {
      _syncWidgetsIfNeeded(app, schedule, s, t, now);
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: LayoutBuilder(
        builder: (context, box) {
          final h = box.maxHeight;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: _onDragStart,
            onVerticalDragUpdate: (d) => _onDragUpdate(d, h),
            onVerticalDragEnd: _onDragEnd,
            onVerticalDragCancel: _onDragCancel,
            child: AnimatedBuilder(
              animation: _p,
              builder: (context, _) {
                final p = _p.value;
                final fg = t != null ? skyForeground(t, nowSec) : null;
                final dayPalette = t != null
                    ? daySurfacePalette(t, nowSec)
                    : null;
                // На главном индикаторы следуют за небом, на втором экране —
                // за его собственной дневной/ночной атмосферой.
                final darkStatusIcons = p < 0.45
                    ? fg != null && fg.text.computeLuminance() < 0.5
                    : dayPalette?.isLight ?? false;
                return JSystemBars(
                  darkIcons: darkStatusIcons,
                  child: Stack(
                    children: [
                      if (t != null)
                        SceneBackground(
                          progress: p,
                          screenHeight: h,
                          times: t,
                          nowSec: nowSec,
                          city: app.city,
                        ),
                      if (t != null) ...[
                        Positioned.fill(
                          child: _HomeLayer(
                            p: p,
                            s: s,
                            c: c,
                            fg: fg!,
                            app: app,
                            t: t,
                            nowMin: nowMin,
                            nowSec: nowSec,
                            h: h,
                            schedule: schedule,
                            onCity: () => CityPicker.open(context),
                            onQibla: () =>
                                _p.animateTo(-1, curve: Curves.easeOutCubic),
                            onReader: _openReader,
                            onToggleDate: () =>
                                app.dateGregorian = !app.dateGregorian,
                            onExpand: () =>
                                _p.animateTo(1, curve: Curves.easeOutCubic),
                          ),
                        ),
                        if (p < 0)
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset(0, -h * (1 + p)),
                              child: Opacity(
                                opacity: (-p * 1.4).clamp(0.0, 1.0),
                                child: QiblaView(
                                  selectedCity: app.city,
                                  showAppBar: true,
                                  onClose: () => _p.animateTo(
                                    0,
                                    curve: Curves.easeOutCubic,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned.fill(
                          child: _modernLowerScreen
                              ? _ModernDayLayer(
                                  p: p,
                                  s: s,
                                  palette: dayPalette!,
                                  app: app,
                                  t: t,
                                  nowMin: nowMin,
                                  nowSec: nowSec,
                                  h: h,
                                  schedule: schedule,
                                  onReader: _openReader,
                                  onCollapse: () => _p.animateTo(
                                    0,
                                    curve: Curves.easeOutCubic,
                                  ),
                                  onToggleDate: () =>
                                      app.dateGregorian = !app.dateGregorian,
                                )
                              : _DayLayer(
                                  p: p,
                                  s: s,
                                  c: c,
                                  app: app,
                                  t: t,
                                  nowMin: nowMin,
                                  h: h,
                                  schedule: schedule,
                                  onReader: _openReader,
                                  onCollapse: () => _p.animateTo(
                                    0,
                                    curve: Curves.easeOutCubic,
                                  ),
                                  onToggleDate: () =>
                                      app.dateGregorian = !app.dateGregorian,
                                ),
                        ),
                        // Общий элемент поверх: только таймер (переезжает наверх).
                        // Времена молитв — на экране «дня» (сеткой 3+3), не на главном.
                        _HeroTimer(
                          p: p,
                          s: s,
                          c: c,
                          fg: fg,
                          t: t,
                          nowSec: nowSec,
                          h: h,
                          schedule: schedule,
                          app: app,
                        ),
                      ] else
                        Center(child: CircularProgressIndicator(color: c.gold)),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ── Общий герой: таймер (переезжает из центра главного наверх «дня») ──────────
class _HeroTimer extends StatelessWidget {
  const _HeroTimer({
    required this.p,
    required this.s,
    required this.c,
    required this.fg,
    required this.t,
    required this.nowSec,
    required this.h,
    required this.schedule,
    required this.app,
  });
  final double p, h;
  final S s;
  final JColors c;
  final SkyFg fg;
  final DayTimes t;
  final int nowSec;
  final ScheduleService schedule;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final nowMin = nowSec ~/ 60;
    final (caption, secs, _) = heroTimer(s, t, nowSec, nowMin, schedule, app);
    // Посекундный таймер; часы скрываются, когда их нет: «1:40:15» → «40:15»
    // (решение владельца: без секунд непонятно, часы это или минуты).
    final v = secs < 0 ? 0 : secs;
    final ss = (v % 60).toString().padLeft(2, '0');
    final mm = (v % 3600) ~/ 60;
    final value = v >= 3600
        ? '${v ~/ 3600}:${mm.toString().padLeft(2, '0')}:$ss'
        : '$mm:$ss';
    final fade = (1 - p * 1.6).clamp(0.0, 1.0);
    return Positioned(
      left: 0,
      right: 0,
      top: h * 0.35 - h * p * 0.6,
      child: IgnorePointer(
        child: Opacity(
          opacity: fade,
          child: Column(
            children: [
              Text(
                caption,
                style: JType.caption(
                  fg.accent,
                  size: 15,
                ).copyWith(shadows: fg.shadows),
              ),
              const SizedBox(height: 6),
              _RollingTimerText(
                value: value,
                size: v >= 3600 ? 76 : 84,
                color: fg.text,
                shadows: fg.shadows,
              ),
              _DoneChips(app: app, s: s, fg: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Таймер сохраняет посекундную живость, но меняется не целой строкой:
/// переворачивается только изменившийся разряд. Благодаря фиксированной
/// ширине цифр строка не «дышит» и остаётся главным спокойным акцентом.
class _RollingTimerText extends StatelessWidget {
  const _RollingTimerText({
    required this.value,
    required this.size,
    required this.color,
    required this.shadows,
  });

  final String value;
  final double size;
  final Color color;
  final List<Shadow> shadows;

  @override
  Widget build(BuildContext context) {
    final style = JType.timer(size, color).copyWith(
      letterSpacing: -size * .035,
      shadows: [
        ...shadows,
        Shadow(color: color.withValues(alpha: .12), blurRadius: 18),
      ],
    );

    return Semantics(
      label: value,
      readOnly: true,
      child: ExcludeSemantics(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < value.length; i++)
                SizedBox(
                  width: value[i] == ':' ? size * .25 : size * .53,
                  height: size * 1.12,
                  child: ClipRect(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.center,
                        children: [...previous, ?current],
                      ),
                      transitionBuilder: (child, animation) {
                        final slide = Tween<Offset>(
                          begin: const Offset(0, .36),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(position: slide, child: child),
                        );
                      },
                      child: Center(
                        key: ValueKey('$i:${value[i]}'),
                        child: Text(value[i], style: style),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Заметный статус выполненного (дизайн-отчёт): стеклянные пилюли под
/// таймером — «Вечерние зикры ✓» вместо незаметной строки внизу.
class _DoneChips extends StatelessWidget {
  const _DoneChips({required this.app, required this.s, required this.fg});
  final AppState app;
  final S s;
  final SkyFg fg;

  @override
  Widget build(BuildContext context) {
    final done = <String>[
      if (app.isDone('morning')) s.morningTitle,
      if (app.isDone('kahf')) s.kahfTitle,
      if (app.isDone('evening')) s.eveningTitle,
      if (app.isDone('dua')) s.duaTitle,
    ];
    if (done.isEmpty) return const SizedBox(height: 22);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < done.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check, size: 14, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        done[i],
                        style: JType.ui(
                          13,
                          w: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Единый «геройский» таймер: что показывает большой счётчик сейчас.
/// В открытом окне — до конца окна; иначе — до следующей молитвы.
(String, int, String) heroTimer(
  S s,
  DayTimes t,
  int nowSec,
  int nowMin,
  ScheduleService schedule,
  AppState app,
) {
  final kz = s.step == 'ҚАДАМ';
  final called = justCalledPrayer(t, nowMin, graceMinutes: 10);
  if (called != null) {
    final next = nextPrayer(t, nowMin);
    return (
      kz ? 'АЗАННАН КЕЙІН' : 'ПОСЛЕ АЗАНА',
      nowSec - t.times[called]! * 60,
      next == null
          ? ''
          : s.atTpl
                .replaceFirst('{p}', s.prayers[next.index])
                .replaceFirst('{t}', t.fmt(next)),
    );
  }
  final w = currentWindow(t, nowMin, (id) => app.isDone(id.name));
  if (w != null) {
    final endPrayer = switch (w.id) {
      TaskId.morning => Prayer.sunrise,
      TaskId.kahf => Prayer.dhuhr,
      _ => Prayer.maghrib,
    };
    return (
      s.toPrayerCaps[endPrayer.index],
      t.times[endPrayer]! * 60 - nowSec,
      s.atTpl
          .replaceFirst('{p}', s.prayers[endPrayer.index])
          .replaceFirst('{t}', t.fmt(endPrayer)),
    );
  }
  final next = nextPrayer(t, nowMin);
  if (next != null) {
    return (
      s.toPrayerCaps[next.index],
      t.times[next]! * 60 - nowSec,
      s.atTpl
          .replaceFirst('{p}', s.prayers[next.index])
          .replaceFirst('{t}', t.fmt(next)),
    );
  }
  final tomorrow = schedule.timesFor(
    app.city,
    schedule.now().add(const Duration(days: 1)),
  );
  final fajr = tomorrow?.times[Prayer.fajr] ?? 0;
  return (
    s.toPrayerCaps[Prayer.fajr.index],
    24 * 3600 - nowSec + fajr * 60,
    tomorrow == null
        ? ''
        : s.atTpl
              .replaceFirst('{p}', s.prayers[Prayer.fajr.index])
              .replaceFirst('{t}', tomorrow.fmt(Prayer.fajr)),
  );
}

// ── Слой «главный»: заголовок, карточка окна / бейдж, подсказка. Уезжает вверх ─
class _HomeLayer extends StatelessWidget {
  const _HomeLayer({
    required this.p,
    required this.s,
    required this.c,
    required this.fg,
    required this.app,
    required this.t,
    required this.nowMin,
    required this.nowSec,
    required this.h,
    required this.schedule,
    required this.onCity,
    required this.onQibla,
    required this.onReader,
    required this.onToggleDate,
    required this.onExpand,
  });
  final double p, h;
  final S s;
  final JColors c;
  final SkyFg fg;
  final AppState app;
  final DayTimes t;
  final int nowMin, nowSec;
  final ScheduleService schedule;
  final VoidCallback onCity, onQibla, onToggleDate, onExpand;
  final void Function(String) onReader;

  @override
  Widget build(BuildContext context) {
    final w = currentWindow(t, nowMin, (id) => app.isDone(id.name));
    final fade = (1 - p * 1.4).clamp(0.0, 1.0);

    // Верхний блок окна (над геройским таймером): caption, title, sub.
    Widget topBlock;
    if (w != null) {
      final (title, sub, btn, link, onBtn, onLink) = _windowLabels(
        w,
        s,
        app,
        onReader,
      );
      topBlock = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: JType.ui(
              34,
              w: FontWeight.w800,
              color: fg.text,
              h: 1.1,
            ).copyWith(shadows: fg.shadows),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              sub,
              textAlign: TextAlign.center,
              style: JType.ui(
                14,
                color: fg.faint,
                h: 1.4,
              ).copyWith(shadows: fg.shadows),
            ),
          ),
        ],
      );
      // Кнопка окна — ниже геройского таймера.
      return Transform.translate(
        offset: Offset(0, -h * p),
        child: Opacity(
          opacity: fade,
          child: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                _header(context),
                Positioned(left: 0, right: 0, top: h * 0.16, child: topBlock),
                Positioned(
                  left: 0,
                  right: 0,
                  // На активном окне город поднимается достаточно высоко,
                  // поэтому действия держим в свободной зоне сразу под
                  // таймером, а не поверх башни Абрадж аль-Бейт.
                  top: h * 0.49,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: onBtn,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 44,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: c.btnbg,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            btn,
                            style: JType.ui(
                              16,
                              w: FontWeight.w700,
                              color: c.btnink,
                            ),
                          ),
                        ),
                      ),
                      if (link != null) ...[
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: onLink,
                          child: Text(
                            link,
                            style: JType.ui(14, color: fg.text).copyWith(
                              decoration: TextDecoration.underline,
                              decorationColor: fg.text,
                              shadows: const [
                                Shadow(
                                  color: Colors.black26,
                                  offset: Offset(0, 0.5),
                                  blurRadius: 2.0,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _swipeHint(context),
              ],
            ),
          ),
        ),
      );
    }

    // Нет окна: бейдж «всё выполнено» (если есть) + подпись под таймером.
    return Transform.translate(
      offset: Offset(0, -h * p),
      child: Opacity(
        opacity: fade,
        child: SafeArea(
          bottom: false,
          child: Stack(children: [_header(context), _swipeHint(context)]),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final style = JType.ui(12.5, color: fg.faint).copyWith(shadows: fg.shadows);
    return Positioned(
      left: 28,
      right: 28,
      top: 12,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onCity,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Icon(Icons.place_outlined, size: 14, color: fg.faint),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      app.city.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down, size: 14, color: fg.faint),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: onQibla,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(Icons.navigation_outlined, size: 14, color: fg.faint),
                  const SizedBox(width: 3),
                  Text('Кибла ↑', style: style),
                ],
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onToggleDate,
              behavior: HitTestBehavior.opaque,
              child: Text(
                dateLine(s, schedule.now(), app.dateGregorian),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: style,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _swipeHint(BuildContext context) => Positioned(
    left: 0,
    right: 0,
    bottom: 8,
    child: _BouncingHint(
      s: s,
      // Подсказка лежит поверх архитектуры, поэтому не наследует дневной
      // тёмный foreground неба: её прежний светлый вид читается стабильнее.
      color: const Color(0xFFF2EFE6),
      shadows: const [
        Shadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 2.5),
      ],
      onTap: onExpand,
    ),
  );
}

/// Подсказка свайпа с периодическим подскоком (README: hintbounce) —
/// намекает, что экран можно свайпнуть вверх.
class _BouncingHint extends StatefulWidget {
  const _BouncingHint({
    required this.s,
    required this.color,
    required this.shadows,
    required this.onTap,
  });
  final S s;
  final Color color;
  final List<Shadow> shadows;
  final VoidCallback onTap;

  @override
  State<_BouncingHint> createState() => _BouncingHintState();
}

class _BouncingHintState extends State<_BouncingHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..repeat();
  late final Animation<double> _dy = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0), weight: 72),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: -8.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 6,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: -8.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 6,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: -4.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 6,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: -4.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 6,
    ),
    TweenSequenceItem(tween: ConstantTween(0), weight: 4),
  ]).animate(_ctrl);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _dy,
        builder: (_, child) =>
            Transform.translate(offset: Offset(0, _dy.value), child: child),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.s.swipe,
              style: JType.ui(
                11,
                color: color,
              ).copyWith(shadows: widget.shadows),
            ),
          ],
        ),
      ),
    );
  }
}

(String, String, String, String?, VoidCallback, VoidCallback?) _windowLabels(
  WorshipWindow w,
  S s,
  AppState app,
  void Function(String) onReader,
) {
  switch (w.id) {
    case TaskId.morning:
      return (
        s.morningTitle,
        s.morningSub,
        s.read,
        s.markOnly,
        () => onReader('morning'),
        () => app.markDone('morning'),
      );
    case TaskId.kahf:
      return (
        s.kahfTitle,
        s.kahfSub,
        s.markKahf,
        null,
        () => app.markDone('kahf'),
        null,
      );
    case TaskId.evening:
      return (
        s.eveningTitle,
        s.eveningSub,
        s.read,
        s.markOnly,
        () => onReader('evening'),
        () => app.markDone('evening'),
      );
    case TaskId.dua:
      return (
        s.duaTitle,
        s.duaSub,
        s.markDua,
        null,
        () => app.markDone('dua'),
        null,
      );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding:
                padding ??
                const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1.0,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── Слой «день»: задачи, тетрадь, кнопки. Приезжает снизу ─────────────────────
class _DayLayer extends StatelessWidget {
  const _DayLayer({
    required this.p,
    required this.s,
    required this.c,
    required this.app,
    required this.t,
    required this.nowMin,
    required this.h,
    required this.schedule,
    required this.onReader,
    required this.onCollapse,
    required this.onToggleDate,
  });
  final double p, h;
  final S s;
  final JColors c;
  final AppState app;
  final DayTimes t;
  final int nowMin;
  final ScheduleService schedule;
  final void Function(String) onReader;
  final VoidCallback onCollapse, onToggleDate;

  @override
  Widget build(BuildContext context) {
    final eveningOpen = windowsFor(
      t,
    ).any((w) => w.id == TaskId.evening && w.contains(nowMin));
    // Карточки не проявляются сразу поверх Мекки: сначала пользователь видит
    // движение цельного кадра, затем горизонт растворяется и только после
    // этого входит интерфейс второго экрана.
    final fade = const Interval(
      0.18,
      1.0,
      curve: Curves.easeOutCubic,
    ).transform(p.clamp(0.0, 1.0));

    // Стеклянный скролл-контент
    return Transform.translate(
      offset: Offset(0, h * (1 - p)),
      child: Opacity(
        opacity: fade,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: h * 0.10,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0B1512).withValues(alpha: 0.0),
                      const Color(0xFF0B1512).withValues(alpha: 0.55),
                      const Color(0xFF0B1512).withValues(alpha: 0.8),
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Stack(
                children: [
                  // Хват + строка даты сверху дня (тап по хвату — назад).
                  Positioned(
                    left: 28,
                    right: 28,
                    top: 8,
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: onCollapse,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: c.sub.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.place_outlined,
                                  size: 13,
                                  color: c.sub,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  app.city.name,
                                  style: JType.ui(12.5, color: c.sub),
                                ),
                              ],
                            ),
                            GestureDetector(
                              onTap: onToggleDate,
                              behavior: HitTestBehavior.opaque,
                              child: Text(
                                dateLine(s, schedule.now(), app.dateGregorian),
                                style: JType.ui(12.5, color: c.sub),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 28,
                    right: 28,
                    top: 48,
                    // Низ — над закреплёнными кнопками (не налезать на них).
                    bottom: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Карточка 1: Времена молитв (вертикальный список)
                        _GlassCard(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 8,
                          ),
                          child: _DayTimesList(
                            s: s,
                            c: c,
                            t: t,
                            nowMin: nowMin,
                          ),
                        ),

                        // Карточка 2: Сегодня (задачи)
                        _GlassCard(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 14,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(s.todayCaps, style: JType.caption(c.faint)),
                              const SizedBox(height: 8),
                              _TaskRow(
                                label: s.morningTitle,
                                done: app.isDone('morning'),
                                c: c,
                                onTap: () => onReader('morning'),
                              ),
                              if (t.isFriday)
                                _TaskRow(
                                  label: s.kahfTitle,
                                  done: app.isDone('kahf'),
                                  c: c,
                                  onTap: () => app.markDone('kahf'),
                                ),
                              _TaskRow(
                                label: s.eveningTitle,
                                done: app.isDone('evening'),
                                c: c,
                                active: eveningOpen && !app.isDone('evening'),
                                trailing: eveningOpen
                                    ? '${s.still} ${DayTimes.fmtDuration(t.times[Prayer.maghrib]! - nowMin)}'
                                    : null,
                                onTap: () => onReader('evening'),
                              ),
                              if (t.isFriday)
                                _TaskRow(
                                  label: s.duaTitle,
                                  done: app.isDone('dua'),
                                  c: c,
                                  onTap: () => app.markDone('dua'),
                                ),
                            ],
                          ),
                        ),

                        // Карточка 3: Тетрадь постоянства
                        _GlassCard(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 14,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${s.notebookTitle} · ${_gregMonthCaps(schedule.now())}',
                                style: JType.caption(c.faint),
                              ),
                              const SizedBox(height: 12),
                              _Notebook(c: c, app: app, now: schedule.now()),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                  // Кнопки закреплены внизу — всегда видны, не уезжают за экран.
                  Positioned(
                    left: 28,
                    right: 28,
                    bottom: 10,
                    child: Row(
                      children: [
                        Expanded(
                          child: _SmallOutlineButton(
                            label: s.remindersBtn,
                            c: c,
                            onTap: () => RemindersScreen.open(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SmallOutlineButton(
                            label: s.langBtn,
                            c: c,
                            onTap: () => LanguagePicker.open(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _gregMonthsNom = [
    'ЯНВАРЬ',
    'ФЕВРАЛЬ',
    'МАРТ',
    'АПРЕЛЬ',
    'МАЙ',
    'ИЮНЬ',
    'ИЮЛЬ',
    'АВГУСТ',
    'СЕНТЯБРЬ',
    'ОКТЯБРЬ',
    'НОЯБРЬ',
    'ДЕКАБРЬ',
  ];
  String _gregMonthCaps(DateTime now) =>
      '${_gregMonthsNom[now.month - 1]} ${now.year}';
}

// ── Современный нижний экран (эксперимент для проверки на iPhone) ───────────

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.palette,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final DaySurfacePalette palette;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            offset: const Offset(0, 12),
            blurRadius: 34,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StagedReveal extends StatelessWidget {
  const _StagedReveal({
    required this.progress,
    required this.start,
    required this.child,
  });

  final double progress, start;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final raw = ((progress - start) / (1 - start)).clamp(0.0, 1.0);
    final value = Curves.easeOutCubic.transform(raw);
    return IgnorePointer(
      ignoring: value < 0.5,
      child: Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

class _ModernDayLayer extends StatelessWidget {
  const _ModernDayLayer({
    required this.p,
    required this.s,
    required this.palette,
    required this.app,
    required this.t,
    required this.nowMin,
    required this.nowSec,
    required this.h,
    required this.schedule,
    required this.onReader,
    required this.onCollapse,
    required this.onToggleDate,
  });

  final double p, h;
  final S s;
  final DaySurfacePalette palette;
  final AppState app;
  final DayTimes t;
  final int nowMin, nowSec;
  final ScheduleService schedule;
  final void Function(String) onReader;
  final VoidCallback onCollapse, onToggleDate;

  @override
  Widget build(BuildContext context) {
    final c = palette.colors;
    final fade = const Interval(
      0.14,
      1.0,
      curve: Curves.easeOutCubic,
    ).transform(p.clamp(0.0, 1.0));
    final eveningOpen = windowsFor(
      t,
    ).any((w) => w.id == TaskId.evening && w.contains(nowMin));

    return Transform.translate(
      offset: Offset(0, h * (1 - p)),
      child: Opacity(
        opacity: fade,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Column(
              children: [
                _StagedReveal(
                  progress: p,
                  start: 0.14,
                  child: Center(
                    child: GestureDetector(
                      onTap: onCollapse,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 4,
                        ),
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: c.sub.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _StagedReveal(
                  progress: p,
                  start: 0.17,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          app.city.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: JType.ui(12.5, color: c.sub),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: onToggleDate,
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          dateLine(s, schedule.now(), app.dateGregorian),
                          maxLines: 1,
                          style: JType.ui(12.5, color: c.sub),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _StagedReveal(
                  progress: p,
                  start: 0.20,
                  child: _SurfaceCard(
                    palette: palette,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: _DayTimesList(
                      s: s,
                      c: c,
                      t: t,
                      nowMin: nowMin,
                      nowSec: nowSec,
                      compact: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _StagedReveal(
                  progress: p,
                  start: 0.28,
                  child: _ModernTasksCard(
                    s: s,
                    palette: palette,
                    app: app,
                    t: t,
                    nowMin: nowMin,
                    eveningOpen: eveningOpen,
                    onReader: onReader,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _StagedReveal(
                    progress: p,
                    start: 0.36,
                    child: _SurfaceCard(
                      palette: palette,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _sentenceCase(s.notebookTitle),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: JType.ui(
                                    15,
                                    w: FontWeight.w700,
                                    color: c.ink,
                                  ),
                                ),
                              ),
                              Text(
                                _monthYearLabel(s, schedule.now()),
                                style: JType.ui(11, color: c.sub),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: MediaQuery.sizeOf(context).width - 68,
                                child: _Notebook(
                                  c: c,
                                  app: app,
                                  now: schedule.now(),
                                  compact: true,
                                  onDayTap: (date) => _showDayDetailsSheet(
                                    context,
                                    date: date,
                                    s: s,
                                    app: app,
                                    palette: palette,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _StagedReveal(
                  progress: p,
                  start: 0.48,
                  child: _UtilityDock(
                    s: s,
                    palette: palette,
                    onReminders: () => RemindersScreen.open(context),
                    onLanguage: () => LanguagePicker.open(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernTasksCard extends StatelessWidget {
  const _ModernTasksCard({
    required this.s,
    required this.palette,
    required this.app,
    required this.t,
    required this.nowMin,
    required this.eveningOpen,
    required this.onReader,
  });

  final S s;
  final DaySurfacePalette palette;
  final AppState app;
  final DayTimes t;
  final int nowMin;
  final bool eveningOpen;
  final void Function(String) onReader;

  @override
  Widget build(BuildContext context) {
    final c = palette.colors;
    final tasks =
        <({String id, String label, bool active, VoidCallback onTap})>[
          (
            id: 'morning',
            label: s.morningTitle,
            active: false,
            onTap: () => onReader('morning'),
          ),
          if (t.isFriday)
            (
              id: 'kahf',
              label: s.kahfTitle,
              active: false,
              onTap: () => app.markDone('kahf'),
            ),
          (
            id: 'evening',
            label: s.eveningTitle,
            active: eveningOpen && !app.isDone('evening'),
            onTap: () => onReader('evening'),
          ),
          if (t.isFriday)
            (
              id: 'dua',
              label: s.duaTitle,
              active: false,
              onTap: () => app.markDone('dua'),
            ),
          for (final reminder in app.customReminders.where(
            (item) => app.reminderOccursOn(item, t.date),
          ))
            (
              id: 'custom:${reminder.id}',
              label: reminder.title,
              active: false,
              onTap: () => app.markDone('custom:${reminder.id}'),
            ),
        ];
    final doneCount = tasks.where((task) => app.isDone(task.id)).length;
    final hasCustomTasks = tasks.length > (t.isFriday ? 4 : 2);

    return _SurfaceCard(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hasCustomTasks
                      ? (s == S.kz ? 'Бүгінгі істер' : 'Дела сегодня')
                      : (s == S.kz ? 'Бүгінгі зікірлер' : 'Зикры сегодня'),
                  style: JType.ui(16, w: FontWeight.w700, color: c.ink),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: c.ink.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '$doneCount / ${tasks.length}',
                  style: JType.ui(10.5, w: FontWeight.w700, color: c.sub),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          _HorizontalTaskRail(tasks: tasks, app: app, c: c),
        ],
      ),
    );
  }
}

class _HorizontalTaskRail extends StatefulWidget {
  const _HorizontalTaskRail({
    required this.tasks,
    required this.app,
    required this.c,
  });

  final List<({String id, String label, bool active, VoidCallback onTap})>
  tasks;
  final AppState app;
  final JColors c;

  @override
  State<_HorizontalTaskRail> createState() => _HorizontalTaskRailState();
}

class _HorizontalTaskRailState extends State<_HorizontalTaskRail> {
  final _scroll = ScrollController();
  bool _hintScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleHint();
  }

  @override
  void didUpdateWidget(_HorizontalTaskRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasks.length != widget.tasks.length) {
      _hintScheduled = false;
      _scheduleHint();
    }
  }

  void _scheduleHint() {
    if (_hintScheduled || widget.tasks.length <= 2) return;
    _hintScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          !_scroll.hasClients ||
          _scroll.position.maxScrollExtent <= 0) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted || !_scroll.hasClients) return;
      final peek = math.min(28.0, _scroll.position.maxScrollExtent);
      await _scroll.animateTo(
        peek,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
      if (!mounted || !_scroll.hasClients) return;
      await Future<void>.delayed(const Duration(milliseconds: 110));
      if (!mounted || !_scroll.hasClients) return;
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutBack,
      );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final overflow = widget.tasks.length > 2;
        final tileWidth = overflow
            ? math.min(158.0, constraints.maxWidth * .47)
            : (constraints.maxWidth - 8) / 2;
        return SizedBox(
          height: 52,
          child: Stack(
            children: [
              ListView.separated(
                key: const ValueKey('today-task-rail'),
                controller: _scroll,
                primary: false,
                scrollDirection: Axis.horizontal,
                physics: overflow
                    ? const BouncingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.only(right: overflow ? 22 : 0),
                itemCount: widget.tasks.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final task = widget.tasks[index];
                  return SizedBox(
                    width: tileWidth,
                    child: _CompactTaskTile(
                      label: task.label,
                      done: widget.app.isDone(task.id),
                      active: task.active,
                      c: widget.c,
                      onTap: task.onTap,
                    ),
                  );
                },
              ),
              if (overflow)
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: 34,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            widget.c.bg.withValues(alpha: 0),
                            widget.c.bg.withValues(alpha: .72),
                          ],
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Icon(
                          CupertinoIcons.chevron_right,
                          size: 13,
                          color: widget.c.sub.withValues(alpha: .72),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CompactTaskTile extends StatelessWidget {
  const _CompactTaskTile({
    required this.label,
    required this.done,
    required this.active,
    required this.c,
    required this.onTap,
  });

  final String label;
  final bool done, active;
  final JColors c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: done,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: done
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? c.green : Colors.transparent,
                  border: done ? null : Border.all(color: c.hair, width: 1.2),
                ),
                child: done
                    ? const Icon(
                        CupertinoIcons.check_mark,
                        size: 13,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: JType.ui(
                    11.5,
                    w: active ? FontWeight.w700 : FontWeight.w600,
                    color: done ? c.sub : (active ? c.gold : c.ink),
                    h: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UtilityDock extends StatelessWidget {
  const _UtilityDock({
    required this.s,
    required this.palette,
    required this.onReminders,
    required this.onLanguage,
  });

  final S s;
  final DaySurfacePalette palette;
  final VoidCallback onReminders, onLanguage;

  @override
  Widget build(BuildContext context) {
    final c = palette.colors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            offset: const Offset(0, 10),
            blurRadius: 30,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              color: palette.dock,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: palette.dockBorder, width: 0.8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _DockAction(
                    icon: CupertinoIcons.bell,
                    label: s.remindersBtn,
                    color: c.ink,
                    onTap: onReminders,
                  ),
                ),
                Container(
                  width: 0.8,
                  height: 24,
                  color: c.hair.withValues(alpha: 0.65),
                ),
                Expanded(
                  child: _DockAction(
                    icon: CupertinoIcons.globe,
                    label: s.langBtn,
                    color: c.ink,
                    onTap: onLanguage,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockAction extends StatelessWidget {
  const _DockAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JType.ui(12.5, w: FontWeight.w700, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _sentenceCase(String value) {
  if (value.isEmpty) return value;
  final lower = value.toLowerCase();
  return '${lower[0].toUpperCase()}${lower.substring(1)}';
}

String _monthYearLabel(S s, DateTime now) {
  const ru = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];
  if (s == S.kz) {
    final month = _gregMonthsKz[now.month - 1];
    return '${month[0].toUpperCase()}${month.substring(1)} ${now.year}';
  }
  return '${ru[now.month - 1]} ${now.year}';
}

// ── Общие мелкие виджеты и утилиты ───────────────────────────────────────────
const _hijriMonthsRu = [
  'мухаррам',
  'сафар',
  'раби аль-авваль',
  'раби ас-сани',
  'джумада аль-уля',
  'джумада ас-сани',
  'раджаб',
  'шаабан',
  'рамадан',
  'шавваль',
  'зуль-каада',
  'зуль-хиджа',
];
const _gregMonthsRu = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];
const _gregMonthsKz = [
  'қаңтар',
  'ақпан',
  'наурыз',
  'сәуір',
  'мамыр',
  'маусым',
  'шілде',
  'тамыз',
  'қыркүйек',
  'қазан',
  'қараша',
  'желтоқсан',
];

/// «Пятница · 19 мухаррама» (хиджра) или «Пятница · 5 июля» (григорианский).
String dateLine(S s, DateTime now, bool gregorian) {
  final wd = s.weekdays[now.weekday - 1];
  if (gregorian) {
    final months = s == S.kz ? _gregMonthsKz : _gregMonthsRu;
    return '$wd · ${now.day} ${months[now.month - 1]}';
  }
  final hijri = HijriCalendar.fromDate(now);
  final months = s == S.kz ? s.hijriMonths : _hijriMonthsRu;
  return '$wd · ${hijri.hDay} ${months[hijri.hMonth - 1]}';
}

/// Цвета по актуальной теме (учитывает «системную»).
JColors jColorsOf(BuildContext context) {
  final app = AppScope.of(context);
  final isLight = switch (app.theme) {
    'light' => true,
    'system' => MediaQuery.platformBrightnessOf(context) == Brightness.light,
    _ => false,
  };
  return isLight ? JColors.light : JColors.dark;
}

/// Вертикальный список времён молитв на экране «дня»
class _DayTimesList extends StatelessWidget {
  const _DayTimesList({
    required this.s,
    required this.c,
    required this.t,
    required this.nowMin,
    this.nowSec,
    this.compact = false,
  });
  final S s;
  final JColors c;
  final DayTimes t;
  final int nowMin;
  final int? nowSec;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final currentSec = nowSec ?? nowMin * 60;
    var hl = Prayer.fajr;
    var targetSec = t.times[Prayer.fajr]! * 60 + 86400;
    for (final prayer in Prayer.values) {
      final candidate = t.times[prayer]! * 60;
      if (candidate > currentSec) {
        hl = prayer;
        targetSec = candidate;
        break;
      }
    }
    final countdown = _eventCountdown(targetSec - currentSec);

    return Column(
      children: [
        for (final (i, prayer) in Prayer.values.indexed)
          Builder(
            builder: (context) {
              final isCurrent = prayer == hl;

              return _ScalePressed(
                onTap: () {
                  final name = s.prayers[i];
                  _showQuickSettings(context, prayer.name, name, c);
                },
                child: Container(
                  constraints: BoxConstraints(minHeight: compact ? 40 : 48),
                  margin: EdgeInsets.symmetric(vertical: compact ? 0 : 1),
                  padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? c.gold.withValues(alpha: 0.11)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(
                          s.prayers[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: JType.ui(
                            compact ? 13.5 : 15,
                            w: isCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: isCurrent ? c.gold : c.ink,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: compact ? 82 : 92,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: isCurrent
                              ? Text(
                                  countdown,
                                  key: ValueKey(countdown),
                                  textAlign: TextAlign.center,
                                  style: JType.ui(
                                    compact ? 11.5 : 12.5,
                                    w: FontWeight.w600,
                                    color: c.gold.withValues(alpha: .92),
                                    ls: -.2,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      SizedBox(
                        width: compact ? 67 : 74,
                        child: Text(
                          t.fmt(prayer),
                          textAlign: TextAlign.right,
                          style: JType.ui(
                            compact ? 13.5 : 15,
                            w: isCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: isCurrent ? c.gold : c.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 12,
                        color: isCurrent
                            ? c.gold.withValues(alpha: 0.72)
                            : c.faint.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

String _eventCountdown(int seconds) {
  final safe = seconds.clamp(0, 86400);
  final h = safe ~/ 3600;
  final m = (safe % 3600) ~/ 60;
  final s = safe % 60;
  final value = h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '$m:${s.toString().padLeft(2, '0')}';
  return value;
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.label,
    required this.done,
    required this.c,
    this.active = false,
    this.trailing,
    this.onTap,
  });
  final String label;
  final bool done, active;
  final String? trailing;
  final JColors c;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: done ? 0.75 : 1.0,
      child: InkWell(
        onTap: done ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? c.green : null,
                  border: done
                      ? null
                      : Border.all(color: active ? c.gold : c.hair),
                ),
                child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: JType.ui(
                  14.5,
                  w: active ? FontWeight.w700 : FontWeight.w400,
                  color: done ? c.sub : c.ink,
                ),
              ),
              const Spacer(),
              if (trailing != null && !done)
                Text(
                  trailing!,
                  style: JType.ui(12, w: FontWeight.w700, color: c.gold),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Тетрадь постоянства — настоящий календарь текущего месяца, привязанный к
/// дням недели. Прошедшие дни — зеленая галочка / красный крестик.
/// Сегодня — в золотом круге с числом дня. Будущие — просто число дня.
class _Notebook extends StatelessWidget {
  const _Notebook({
    required this.c,
    required this.app,
    required this.now,
    this.onDayTap,
    this.compact = false,
  });
  final JColors c;
  final AppState app;
  final DateTime now;
  final ValueChanged<DateTime>? onDayTap;
  final bool compact;

  static const _weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

  @override
  Widget build(BuildContext context) {
    final first = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final lead = first.weekday - 1; // сколько пустых ячеек до 1-го числа
    final cells = <Widget>[];
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(now.year, now.month, day);
      final today = DateTime(now.year, now.month, now.day);
      cells.add(
        Center(
          child: Semantics(
            button: !date.isAfter(today) && onDayTap != null,
            label: '$day',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: date.isAfter(today) || onDayTap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onDayTap!(date);
                    },
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: _cell(date),
              ),
            ),
          ),
        ),
      );
    }

    final rows = <List<Widget>>[];
    for (var i = 0; i < cells.length; i += 7) {
      final rowCells = <Widget>[];
      for (var j = 0; j < 7; j++) {
        if (i + j < cells.length) {
          rowCells.add(Expanded(child: cells[i + j]));
        } else {
          rowCells.add(const Expanded(child: SizedBox.shrink()));
        }
      }
      rows.add(rowCells);
    }

    return Column(
      children: [
        Row(
          children: [
            for (final w in _weekdays)
              Expanded(
                child: Center(
                  child: Text(w, style: JType.ui(10, color: c.faint)),
                ),
              ),
          ],
        ),
        SizedBox(height: compact ? 4 : 8),
        for (final row in rows)
          Padding(
            padding: EdgeInsets.symmetric(vertical: compact ? 2.5 : 5.5),
            child: Row(children: row),
          ),
      ],
    );
  }

  /// Сколько реально запланированных задач дня выполнено и сколько всего.
  (int, int) _progress(DateTime date) {
    return app.taskProgressOn(date);
  }

  Widget _cell(DateTime date) {
    final today = DateTime(now.year, now.month, now.day);
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final isFuture = date.isAfter(today);

    if (isFuture) {
      return SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: Text(
            '${date.day}',
            style: JType.ui(
              11,
              w: FontWeight.w400,
              color: c.faint.withValues(alpha: 0.58),
            ),
          ),
        ),
      );
    }

    final (done, total) = _progress(date);
    final frac = done / total;
    return _RingCell(
      day: date.day,
      frac: frac,
      isToday: isToday,
      gold: c.gold,
      faint: c.faint,
    );
  }
}

/// Ячейка тетради: кольцо прогресса дня. Пусто — неактивное серое кольцо
/// (без «наказания»), частично — золотая дуга, полное — золотое кольцо с
/// мягким сиянием и заливкой (чувство полноты). Сегодня — золотое число.
class _RingCell extends StatelessWidget {
  const _RingCell({
    required this.day,
    required this.frac,
    required this.isToday,
    required this.gold,
    required this.faint,
  });
  final int day;
  final double frac;
  final bool isToday;
  final Color gold, faint;

  @override
  Widget build(BuildContext context) {
    final full = frac >= 1.0;
    return SizedBox(
      width: 28,
      height: 28,
      child: CustomPaint(
        painter: _RingPainter(frac: frac, gold: gold, faint: faint, full: full),
        child: Center(
          child: Text(
            '$day',
            style: JType.ui(
              10,
              w: isToday || full ? FontWeight.w800 : FontWeight.w500,
              color: isToday || full
                  ? gold
                  : (frac > 0 ? gold.withValues(alpha: 0.8) : faint),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.frac,
    required this.gold,
    required this.faint,
    required this.full,
  });
  final double frac;
  final Color gold, faint;
  final bool full;

  @override
  void paint(Canvas canvas, Size size) {
    final cCenter = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1.5;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = faint.withValues(alpha: 0.34);
    canvas.drawCircle(cCenter, r, base);
    if (frac <= 0) return;
    if (full) {
      // Сияние + лёгкая заливка — день полностью выполнен.
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = gold.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(cCenter, r, glow);
      canvas.drawCircle(
        cCenter,
        r - 1,
        Paint()..color = gold.withValues(alpha: 0.14),
      );
    }
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = gold;
    canvas.drawArc(
      Rect.fromCircle(center: cCenter, radius: r),
      -1.5708,
      6.2832 * frac.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.frac != frac || o.full != full;
}

class _SmallOutlineButton extends StatelessWidget {
  const _SmallOutlineButton({
    required this.label,
    required this.c,
    required this.onTap,
  });
  final String label;
  final JColors c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.0,
          ),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Center(
          child: FittedBox(
            child: Text(
              label,
              style: JType.ui(
                13,
                w: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showDayDetailsSheet(
  BuildContext context, {
  required DateTime date,
  required S s,
  required AppState app,
  required DaySurfacePalette palette,
}) {
  final c = palette.colors;
  final done = app.doneOn(date);
  final tasks = <(String, String)>[
    ('morning', s.morningTitle),
    if (date.weekday == DateTime.friday) ('kahf', s.kahfTitle),
    ('evening', s.eveningTitle),
    if (date.weekday == DateTime.friday) ('dua', s.duaTitle),
  ];

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.48,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: Container(
          color: palette.isLight
              ? const Color(0xFFF1F0EA)
              : const Color(0xFF111C22),
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.faint.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    dateLine(s, date, true),
                    style: JType.ui(22, w: FontWeight.w700, color: c.ink),
                  ),
                ),
                const SizedBox(height: 16),
                for (final task in tasks)
                  Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done.contains(task.$1)
                                ? c.green
                                : Colors.transparent,
                            border: done.contains(task.$1)
                                ? null
                                : Border.all(color: c.hair),
                          ),
                          child: done.contains(task.$1)
                              ? const Icon(
                                  CupertinoIcons.check_mark,
                                  size: 15,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            task.$2,
                            style: JType.ui(
                              15,
                              w: FontWeight.w500,
                              color: done.contains(task.$1) ? c.sub : c.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void _showQuickSettings(
  BuildContext context,
  String configId,
  String titleName,
  JColors c,
) {
  RemindersScreen.open(context, initialConfigId: configId);
}

/// Виджет для плавного сжатия (scale) при нажатии с последующей вибрацией на iOS (Haptic).
class _ScalePressed extends StatefulWidget {
  const _ScalePressed({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_ScalePressed> createState() => _ScalePressedState();
}

class _ScalePressedState extends State<_ScalePressed>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    lowerBound: 0.985,
    upperBound: 1.0,
    value: 1.0,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) {
        _controller.animateTo(0.985, curve: Curves.easeInOut);
      },
      onTapUp: (_) {
        _controller.animateTo(1.0, curve: Curves.easeInOut);
        HapticFeedback.lightImpact();
      },
      onTapCancel: () {
        _controller.animateTo(1.0, curve: Curves.easeInOut);
      },
      child: ScaleTransition(scale: _controller, child: widget.child),
    );
  }
}
