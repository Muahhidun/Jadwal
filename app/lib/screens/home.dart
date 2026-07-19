import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';
import '../data/app_state.dart';
import '../i18n/strings.dart';
import '../notifications/notifications.dart';
import '../prayer/schedule.dart';
import '../prayer/schedule_service.dart';
import '../prayer/windows.dart';
import '../theme/tokens.dart';
import 'city_picker.dart';
import 'reader.dart';
import 'reminders.dart';
import 'scene_background.dart';

/// Главный экран = вертикальная лента из двух «страниц» (README §2–3).
/// Прокрутка снизу вверх (как в TikTok/Shorts): контент реально скроллится,
/// а таймер и сетка времён — общие элементы: переезжают и перестраиваются
/// (3+3 → ряд из 6). Сзади — художественный фон на два экрана.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  Timer? _ticker;
  String _lastNotifSig = '';
  late final AnimationController _p =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Разрешение на уведомления (iOS покажет диалог один раз; тем, кто
      // прошёл онбординг на старом билде, попросим сейчас).
      await gNotifier?.requestPermission();
      if (!mounted) return;
      syncNotifications(AppScope.of(context), ScheduleScope.of(context));
      // По тапу на уведомление зикров — открыть соответствующий сборник.
      final pending = gNotifier?.pendingCollection;
      if (pending != null && pending.isNotEmpty && mounted) {
        gNotifier!.pendingCollection = null;
        _openReader(pending);
      }
    });
  }

  /// Перепланировать уведомления, только когда изменилось что-то значимое
  /// (город / язык / набор выполненного за сегодня).
  void _syncNotificationsIfNeeded(AppState app, ScheduleService schedule) {
    final sig = '${app.city.name}|${app.lang}|'
        '${TaskId.values.where((id) => app.isDone(id.name)).join(",")}';
    if (sig == _lastNotifSig) return;
    _lastNotifSig = sig;
    syncNotifications(app, schedule);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _p.dispose();
    super.dispose();
  }

  void _openReader(String collectionId) => Navigator.of(context).push(
      MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ReaderScreen(collectionId: collectionId)));

  void _onDragUpdate(DragUpdateDetails d, double h) {
    _p.value = (_p.value - d.primaryDelta! / h).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final target = v < -300
        ? 1.0
        : v > 300
            ? 0.0
            : (_p.value > 0.5 ? 1.0 : 0.0);
    _p.animateTo(target, curve: Curves.easeOutCubic);
  }

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

    return Scaffold(
      backgroundColor: c.bg,
      body: LayoutBuilder(
        builder: (context, box) {
          final h = box.maxHeight;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) => _onDragUpdate(d, h),
            onVerticalDragEnd: _onDragEnd,
            child: AnimatedBuilder(
              animation: _p,
              builder: (context, _) {
                final p = _p.value;
                final fg = t != null ? skyForeground(t, nowSec) : null;
                return Stack(
                  children: [
                    if (t != null)
                      SceneBackground(
                          progress: p, screenHeight: h, times: t, nowSec: nowSec),
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
                          onReader: _openReader,
                          onToggleDate: () => app.dateGregorian = !app.dateGregorian,
                          onExpand: () => _p.animateTo(1, curve: Curves.easeOutCubic),
                        ),
                      ),
                      Positioned.fill(
                        child: _DayLayer(
                          p: p,
                          s: s,
                          c: c,
                          app: app,
                          t: t,
                          nowMin: nowMin,
                          h: h,
                          schedule: schedule,
                          onReader: _openReader,
                          onCollapse: () => _p.animateTo(0, curve: Curves.easeOutCubic),
                          onToggleDate: () => app.dateGregorian = !app.dateGregorian,
                        ),
                      ),
                      // Общий элемент поверх: только таймер (переезжает наверх).
                      // Времена молитв — на экране «дня» (сеткой 3+3), не на главном.
                      _HeroTimer(p: p, s: s, c: c, fg: fg, t: t, nowSec: nowSec, h: h, schedule: schedule, app: app),
                    ] else
                      Center(child: CircularProgressIndicator(color: c.gold)),
                  ],
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
  const _HeroTimer(
      {required this.p,
      required this.s,
      required this.c,
      required this.fg,
      required this.t,
      required this.nowSec,
      required this.h,
      required this.schedule,
      required this.app});
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
      top: h * 0.38 - h * p,
      child: IgnorePointer(
        child: Opacity(
          opacity: fade,
          child: Column(
            children: [
              Text(caption,
                  style: JType.caption(fg.accent, size: 15).copyWith(shadows: fg.shadows)),
              const SizedBox(height: 6),
              Text(value,
                  style: JType.timer(v >= 3600 ? 76 : 84, fg.text)
                      .copyWith(shadows: fg.shadows)),
              _DoneChips(app: app, s: s, fg: fg),
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
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final name in done)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                border: Border.all(color: fg.accent.withValues(alpha: 0.45)),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check, size: 14, color: fg.accent),
                const SizedBox(width: 6),
                Text(name, style: JType.ui(13, w: FontWeight.w600, color: fg.text)),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Единый «геройский» таймер: что показывает большой счётчик сейчас.
/// В открытом окне — до конца окна; иначе — до следующей молитвы.
(String, int, String) heroTimer(
    S s, DayTimes t, int nowSec, int nowMin, ScheduleService schedule, AppState app) {
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
      s.atTpl.replaceFirst('{p}', s.prayers[endPrayer.index]).replaceFirst('{t}', t.fmt(endPrayer)),
    );
  }
  final called = justCalledPrayer(t, nowMin);
  if (called != null) {
    final next = nextPrayer(t, nowMin);
    return (
      s.afterAzanCaps[called.index],
      nowSec - t.times[called]! * 60,
      next == null ? '' : s.atTpl.replaceFirst('{p}', s.prayers[next.index]).replaceFirst('{t}', t.fmt(next)),
    );
  }
  final next = nextPrayer(t, nowMin);
  if (next != null) {
    return (
      s.toPrayerCaps[next.index],
      t.times[next]! * 60 - nowSec,
      s.atTpl.replaceFirst('{p}', s.prayers[next.index]).replaceFirst('{t}', t.fmt(next)),
    );
  }
  final tomorrow = schedule.timesFor(app.city, schedule.now().add(const Duration(days: 1)));
  final fajr = tomorrow?.times[Prayer.fajr] ?? 0;
  return (
    s.toPrayerCaps[Prayer.fajr.index],
    24 * 3600 - nowSec + fajr * 60,
    tomorrow == null ? '' : s.atTpl.replaceFirst('{p}', s.prayers[Prayer.fajr.index]).replaceFirst('{t}', tomorrow.fmt(Prayer.fajr)),
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
  final VoidCallback onCity, onToggleDate, onExpand;
  final void Function(String) onReader;

  @override
  Widget build(BuildContext context) {
    final w = currentWindow(t, nowMin, (id) => app.isDone(id.name));
    final done = allDone(t, (id) => app.isDone(id.name));
    final fade = (1 - p * 1.4).clamp(0.0, 1.0);

    // Верхний блок окна (над геройским таймером): caption, title, sub.
    Widget topBlock;
    if (w != null) {
      final (title, sub, btn, link, onBtn, onLink) = _windowLabels(w, s, app, onReader);
      topBlock = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: JType.ui(34, w: FontWeight.w800, color: fg.text, h: 1.1).copyWith(shadows: fg.shadows)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(sub,
                textAlign: TextAlign.center, style: JType.ui(14, color: fg.faint, h: 1.4).copyWith(shadows: fg.shadows)),
          ),
        ],
      );
      // Кнопка окна — ниже геройского таймера.
      return Transform.translate(
        offset: Offset(0, -h * p),
        child: Opacity(
          opacity: fade,
          child: SafeArea(
            child: Stack(
              children: [
                _header(context),
                Positioned(
                  left: 0,
                  right: 0,
                  top: h * 0.16,
                  child: topBlock,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: h * 0.60,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: onBtn,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 16),
                          decoration: BoxDecoration(
                              color: c.btnbg, borderRadius: BorderRadius.circular(100)),
                          child: Text(btn,
                              style: JType.ui(16, w: FontWeight.w700, color: c.btnink)),
                        ),
                      ),
                      if (link != null) ...[
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: onLink,
                          child: Text(link,
                              style: JType.ui(14, color: fg.faint).copyWith(
                                  decoration: TextDecoration.underline,
                                  decorationColor: fg.faint)),
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
          child: Stack(
            children: [
              _header(context),
              if (done)
                Positioned(
                  left: 0,
                  right: 0,
                  top: h * 0.24,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: c.green),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text('✓ ${s.allDone}',
                          style: JType.ui(13, w: FontWeight.w700, color: c.green)),
                    ),
                  ),
                ),
              _swipeHint(context),
            ],
          ),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: onCity,
            behavior: HitTestBehavior.opaque,
            child: Row(children: [
              Icon(Icons.place_outlined, size: 14, color: fg.faint),
              const SizedBox(width: 3),
              Text(app.city.name, style: style),
              Icon(Icons.keyboard_arrow_down, size: 14, color: fg.faint),
            ]),
          ),
          GestureDetector(
            onTap: onToggleDate,
            behavior: HitTestBehavior.opaque,
            child: Text(dateLine(s, schedule.now(), app.dateGregorian), style: style),
          ),
        ],
      ),
    );
  }

  Widget _swipeHint(BuildContext context) => Positioned(
        left: 0,
        right: 0,
        bottom: 12,
        child: _BouncingHint(s: s, color: fg.faint, shadows: fg.shadows, onTap: onExpand),
      );
}

/// Подсказка свайпа с периодическим подскоком (README: hintbounce) —
/// намекает, что экран можно свайпнуть вверх.
class _BouncingHint extends StatefulWidget {
  const _BouncingHint(
      {required this.s, required this.color, required this.shadows, required this.onTap});
  final S s;
  final Color color;
  final List<Shadow> shadows;
  final VoidCallback onTap;

  @override
  State<_BouncingHint> createState() => _BouncingHintState();
}

class _BouncingHintState extends State<_BouncingHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
  late final Animation<double> _dy = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0), weight: 72),
    TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -8.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 6),
    TweenSequenceItem(
        tween: Tween(begin: -8.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 6),
    TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -4.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 6),
    TweenSequenceItem(
        tween: Tween(begin: -4.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 6),
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
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            Text(widget.s.swipe,
                style: JType.ui(11, color: color).copyWith(shadows: widget.shadows)),
          ],
        ),
      ),
    );
  }
}

(String, String, String, String?, VoidCallback, VoidCallback?) _windowLabels(
    WorshipWindow w, S s, AppState app, void Function(String) onReader) {
  switch (w.id) {
    case TaskId.morning:
      return (s.morningTitle, s.morningSub, s.read, s.markOnly,
          () => onReader('morning'), () => app.markDone('morning'));
    case TaskId.kahf:
      return (s.kahfTitle, s.kahfSub, s.markKahf, null,
          () => app.markDone('kahf'), null);
    case TaskId.evening:
      return (s.eveningTitle, s.eveningSub, s.read, s.markOnly,
          () => onReader('evening'), () => app.markDone('evening'));
    case TaskId.dua:
      return (s.duaTitle, s.duaSub, s.markDua, null,
          () => app.markDone('dua'), null);
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: padding ?? const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
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
    final eveningOpen =
        windowsFor(t).any((w) => w.id == TaskId.evening && w.contains(nowMin));
    final fade = Curves.easeIn.transform(p);
    
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
                                  borderRadius: BorderRadius.circular(2))),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              Icon(Icons.place_outlined, size: 13, color: c.sub),
                              const SizedBox(width: 3),
                              Text(app.city.name, style: JType.ui(12.5, color: c.sub)),
                            ]),
                            GestureDetector(
                              onTap: onToggleDate,
                              behavior: HitTestBehavior.opaque,
                              child: Text(dateLine(s, schedule.now(), app.dateGregorian),
                                  style: JType.ui(12.5, color: c.sub)),
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
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Карточка 1: Времена молитв (вертикальный список)
                          _GlassCard(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            child: _DayTimesList(s: s, c: c, t: t, nowMin: nowMin),
                          ),
                          
                          // Карточка 2: Сегодня (задачи)
                          _GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(s.todayCaps, style: JType.caption(c.faint)),
                                const SizedBox(height: 8),
                                _TaskRow(
                                    label: s.morningTitle,
                                    done: app.isDone('morning'),
                                    c: c,
                                    onTap: () => onReader('morning')),
                                if (t.isFriday)
                                  _TaskRow(
                                      label: s.kahfTitle,
                                      done: app.isDone('kahf'),
                                      c: c,
                                      onTap: () => app.markDone('kahf')),
                                _TaskRow(
                                    label: s.eveningTitle,
                                    done: app.isDone('evening'),
                                    c: c,
                                    active: eveningOpen && !app.isDone('evening'),
                                    trailing: eveningOpen
                                        ? '${s.still} ${DayTimes.fmtDuration(t.times[Prayer.maghrib]! - nowMin)}'
                                        : null,
                                    onTap: () => onReader('evening')),
                                if (t.isFriday)
                                  _TaskRow(
                                      label: s.duaTitle,
                                      done: app.isDone('dua'),
                                      c: c,
                                      onTap: () => app.markDone('dua')),
                              ],
                            ),
                          ),
                          
                          // Карточка 3: Тетрадь постоянства
                          _GlassCard(
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
                  ),
                  // Кнопки закреплены внизу — всегда видны, не уезжают за экран.
                  Positioned(
                    left: 28,
                    right: 28,
                    bottom: 10,
                    child: Row(children: [
                      Expanded(
                          child: _SmallOutlineButton(
                              label: s.remindersBtn,
                              c: c,
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => const RemindersScreen())))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _SmallOutlineButton(
                              label: s.themeBtn,
                              c: c,
                              onTap: () => app.theme = switch (app.theme) {
                                    'dark' => 'light',
                                    'light' => 'system',
                                    _ => 'dark',
                                  })),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _SmallOutlineButton(
                              label: s.langBtn,
                              c: c,
                              onTap: () => app.lang = app.lang == 'ru' ? 'kz' : 'ru')),
                    ]),
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
    'ЯНВАРЬ', 'ФЕВРАЛЬ', 'МАРТ', 'АПРЕЛЬ', 'МАЙ', 'ИЮНЬ', 'ИЮЛЬ', 'АВГУСТ',
    'СЕНТЯБРЬ', 'ОКТЯБРЬ', 'НОЯБРЬ', 'ДЕКАБРЬ'
  ];
  String _gregMonthCaps(DateTime now) => '${_gregMonthsNom[now.month - 1]} ${now.year}';
}

// ── Общие мелкие виджеты и утилиты ───────────────────────────────────────────
const _hijriMonthsRu = [
  'мухаррама', 'сафара', 'раби аль-авваля', 'раби ас-сани', 'джумада аль-уля',
  'джумада ас-сани', 'раджаба', 'шаабана', 'рамадана', 'шавваля', 'зуль-каады',
  'зуль-хиджжи'
];
const _gregMonthsRu = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа',
  'сентября', 'октября', 'ноября', 'декабря'
];
const _gregMonthsKz = [
  'қаңтар', 'ақпан', 'наурыз', 'сәуір', 'мамыр', 'маусым', 'шілде', 'тамыз',
  'қыркүйек', 'қазан', 'қараша', 'желтоқсан'
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
  });
  final S s;
  final JColors c;
  final DayTimes t;
  final int nowMin;

  @override
  Widget build(BuildContext context) {
    final hl = nextPrayer(t, nowMin) ?? Prayer.fajr;
    final app = AppScope.of(context);

    return Column(
      children: [
        for (final (i, prayer) in Prayer.values.indexed)
          Builder(
            builder: (context) {
              final isCurrent = prayer == hl;
              final rc = app.getReminderConfig(prayer.name, app.lang);
              final isNotifEnabled = rc.enabled;

              return GestureDetector(
                onTap: () => _showQuickSettings(context, prayer.name, s.prayers[i], c),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isCurrent ? c.gold.withValues(alpha: 0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isNotifEnabled
                                ? Icons.notifications_active_outlined
                                : Icons.notifications_off_outlined,
                            size: 15,
                            color: isNotifEnabled
                                ? (isCurrent ? c.gold : c.ink.withValues(alpha: 0.85))
                                : c.faint.withValues(alpha: 0.4),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            s.prayers[i],
                            style: JType.ui(
                              14.5,
                              w: isCurrent ? FontWeight.w700 : FontWeight.w400,
                              color: isCurrent ? c.gold : c.ink.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        t.fmt(prayer),
                        style: JType.ui(
                          15,
                          w: isCurrent ? FontWeight.w700 : FontWeight.w500,
                          color: isCurrent ? c.gold : c.ink,
                        ),
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
                  border: done ? null : Border.all(color: active ? c.gold : c.hair),
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
  const _Notebook({required this.c, required this.app, required this.now});
  final JColors c;
  final AppState app;
  final DateTime now;

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
      cells.add(Center(child: _cell(date)));
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
        const SizedBox(height: 8),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.5),
            child: Row(children: row),
          ),
      ],
    );
  }

  /// Сколько задач дня выполнено и сколько всего (пятница — 4, иначе 2).
  (int, int) _progress(DateTime date) {
    final tasks = date.weekday == DateTime.friday
        ? const ['morning', 'evening', 'kahf', 'dua']
        : const ['morning', 'evening'];
    final done = app.doneOn(date);
    return (tasks.where(done.contains).length, tasks.length);
  }

  Widget _cell(DateTime date) {
    final today = DateTime(now.year, now.month, now.day);
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final isFuture = date.isAfter(today);

    if (isFuture) {
      return SizedBox(
        width: 26,
        height: 26,
        child: Center(
          child: Text('${date.day}',
              style: JType.ui(11,
                  w: FontWeight.w400, color: c.faint.withValues(alpha: 0.45))),
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
  const _RingCell(
      {required this.day,
      required this.frac,
      required this.isToday,
      required this.gold,
      required this.faint});
  final int day;
  final double frac;
  final bool isToday;
  final Color gold, faint;

  @override
  Widget build(BuildContext context) {
    final full = frac >= 1.0;
    return SizedBox(
      width: 26,
      height: 26,
      child: CustomPaint(
        painter: _RingPainter(frac: frac, gold: gold, faint: faint, full: full),
        child: Center(
          child: Text(
            '$day',
            style: JType.ui(10,
                w: isToday || full ? FontWeight.w800 : FontWeight.w500,
                color: isToday || full
                    ? gold
                    : (frac > 0 ? gold.withValues(alpha: 0.8) : faint)),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(
      {required this.frac, required this.gold, required this.faint, required this.full});
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
      ..color = Colors.white.withValues(alpha: 0.10);
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
          cCenter, r - 1, Paint()..color = gold.withValues(alpha: 0.14));
    }
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = gold;
    canvas.drawArc(Rect.fromCircle(center: cCenter, radius: r), -1.5708,
        6.2832 * frac.clamp(0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.frac != frac || o.full != full;
}

class _SmallOutlineButton extends StatelessWidget {
  const _SmallOutlineButton({required this.label, required this.c, required this.onTap});
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
          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Center(
          child: FittedBox(
            child: Text(
              label,
              style: JType.ui(13, w: FontWeight.w700, color: Colors.white.withValues(alpha: 0.9)),
            ),
          ),
        ),
      ),
    );
  }
}

void _showQuickSettings(BuildContext context, String configId, String titleName, JColors c) {
  final app = AppScope.of(context);
  final schedule = ScheduleScope.of(context);
  final kz = app.lang == 'kz';
  // Общий стиль настроек: тёплая ночная палитра (как экраны «Напоминания»).
  const darkC = JColors.night;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: darkC.bg,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final rc = app.getReminderConfig(configId, app.lang);
          final offsetMinAbs = rc.offsetMin.abs();
          final isBefore = rc.offsetMin <= 0;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        titleName,
                        style: JType.ui(20, w: FontWeight.w800, color: darkC.ink),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: darkC.faint),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: darkC.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        // Включение / выключение
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(rc.enabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, color: darkC.gold, size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  kz ? 'Хабарландыру' : 'Уведомления',
                                  style: JType.ui(15, w: FontWeight.w600, color: darkC.ink),
                                ),
                              ],
                            ),
                            Switch(
                              value: rc.enabled,
                              activeTrackColor: darkC.gold.withValues(alpha: 0.5),
                              thumbColor: WidgetStatePropertyAll(rc.enabled ? darkC.gold : darkC.faint),
                              onChanged: (v) {
                                final updated = rc.copyWith(enabled: v);
                                app.saveReminderConfig(updated);
                                syncNotifications(app, schedule);
                              },
                            ),
                          ],
                        ),
                        const Divider(height: 24, thickness: 0.5, color: Colors.white10),
                        // Регулировка времени
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.history_toggle_off_outlined, color: darkC.gold, size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  kz ? 'Түзету' : 'Регулировка времени',
                                  style: JType.ui(15, w: FontWeight.w600, color: darkC.ink),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Text(
                                  rc.offsetMin == 0
                                      ? (kz ? 'Дәл уақыты' : 'В момент')
                                      : '${isBefore ? (kz ? 'дейін' : 'до') : (kz ? 'кейін' : 'после')} $offsetMinAbs мин',
                                  style: JType.ui(14, color: darkC.faint),
                                ),
                                const SizedBox(width: 8),
                                 Icon(Icons.chevron_right, size: 16, color: darkC.faint),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: darkC.gold,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        // Перейти к детальному экрану
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReminderDetailScreen(configId: configId),
                          ),
                        );
                      },
                      child: Text(
                        kz ? 'Толығырақ баптау' : 'Другие настройки',
                        style: JType.ui(15, w: FontWeight.w700, color: darkC.bg),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
