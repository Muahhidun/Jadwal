import 'dart:async';
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';
import '../data/app_state.dart';
import '../i18n/strings.dart';
import '../prayer/schedule.dart';
import '../prayer/schedule_service.dart';
import '../prayer/windows.dart';
import '../theme/tokens.dart';
import 'city_picker.dart';
import 'reader.dart';
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
  late final AnimationController _p =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
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
    final c = jColorsOf(context);
    final now = schedule.now();
    final t = schedule.timesFor(app.city, now);
    final nowSec = now.hour * 3600 + now.minute * 60 + now.second;
    final nowMin = nowSec ~/ 60;

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
                return Stack(
                  children: [
                    SceneBackground(progress: p, screenHeight: h),
                    if (t != null) ...[
                      _HomeLayer(
                        p: p,
                        s: s,
                        c: c,
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
                      _DayLayer(
                        p: p,
                        s: s,
                        c: c,
                        app: app,
                        t: t,
                        nowMin: nowMin,
                        h: h,
                        onReader: _openReader,
                        onCollapse: () => _p.animateTo(0, curve: Curves.easeOutCubic),
                        onToggleDate: () => app.dateGregorian = !app.dateGregorian,
                      ),
                      // Общие элементы поверх: таймер и сетка времён.
                      _HeroTimer(p: p, s: s, c: c, t: t, nowSec: nowSec, h: h, schedule: schedule, app: app),
                      _HeroTimes(p: p, s: s, c: c, t: t, nowMin: nowMin, h: h),
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
      required this.t,
      required this.nowSec,
      required this.h,
      required this.schedule,
      required this.app});
  final double p, h;
  final S s;
  final JColors c;
  final DayTimes t;
  final int nowSec;
  final ScheduleService schedule;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final nowMin = nowSec ~/ 60;
    final (caption, timer, _) = heroTimer(s, t, nowSec, nowMin, schedule, app);
    final top = lerpDouble(h * 0.36, h * 0.085, p)!;
    final size = lerpDouble(64.0, 46.0, p)!;
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      child: IgnorePointer(
        child: Column(
          children: [
            Text(caption, style: JType.caption(c.gold)),
            const SizedBox(height: 6),
            Text(timer, style: JType.timer(size, c.ink)),
          ],
        ),
      ),
    );
  }
}

/// Единый «геройский» таймер: что показывает большой счётчик сейчас.
/// В открытом окне — до конца окна; иначе — до следующей молитвы.
(String, String, String) heroTimer(
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
      DayTimes.fmtHMS(t.times[endPrayer]! * 60 - nowSec),
      s.atTpl.replaceFirst('{p}', s.prayers[endPrayer.index]).replaceFirst('{t}', t.fmt(endPrayer)),
    );
  }
  final called = justCalledPrayer(t, nowMin);
  if (called != null) {
    final next = nextPrayer(t, nowMin);
    return (
      s.afterAzanCaps[called.index],
      DayTimes.fmtHMS(nowSec - t.times[called]! * 60),
      next == null ? '' : s.atTpl.replaceFirst('{p}', s.prayers[next.index]).replaceFirst('{t}', t.fmt(next)),
    );
  }
  final next = nextPrayer(t, nowMin);
  if (next != null) {
    return (
      s.toPrayerCaps[next.index],
      DayTimes.fmtHMS(t.times[next]! * 60 - nowSec),
      s.atTpl.replaceFirst('{p}', s.prayers[next.index]).replaceFirst('{t}', t.fmt(next)),
    );
  }
  final tomorrow = schedule.timesFor(app.city, schedule.now().add(const Duration(days: 1)));
  final fajr = tomorrow?.times[Prayer.fajr] ?? 0;
  return (
    s.toPrayerCaps[Prayer.fajr.index],
    DayTimes.fmtHMS(24 * 3600 - nowSec + fajr * 60),
    tomorrow == null ? '' : s.atTpl.replaceFirst('{p}', s.prayers[Prayer.fajr.index]).replaceFirst('{t}', tomorrow.fmt(Prayer.fajr)),
  );
}

// ── Общий герой: сетка времён (морфинг 3+3 → ряд из 6) ────────────────────────
class _HeroTimes extends StatelessWidget {
  const _HeroTimes(
      {required this.p,
      required this.s,
      required this.c,
      required this.t,
      required this.nowMin,
      required this.h});
  final double p, h;
  final S s;
  final JColors c;
  final DayTimes t;
  final int nowMin;

  @override
  Widget build(BuildContext context) {
    final hl = nextPrayer(t, nowMin) ?? Prayer.fajr;
    final width = MediaQuery.of(context).size.width - 56;
    const gap3 = 10.0, gap6 = 6.0;
    final cellW3 = (width - 2 * gap3) / 3;
    final cellW6 = (width - 5 * gap6) / 6;
    const cellH = 52.0;
    final stripH = lerpDouble(cellH * 2 + 10, cellH, p)!;
    final top = lerpDouble(h * 0.60, h * 0.30, p)!;

    // В открытом окне на главном сетки нет: проявляем её по мере прокрутки.
    final w = currentWindow(t, nowMin, (id) => false);
    final baseOpacity = w != null ? Curves.easeIn.transform(p) : 1.0;

    return Positioned(
      left: 28,
      top: top,
      width: width,
      height: stripH,
      child: IgnorePointer(
        child: Opacity(
          opacity: baseOpacity,
          child: Stack(
            children: [
              for (final (i, prayer) in Prayer.values.indexed)
                _cell(i, prayer, hl, cellW3, cellW6, cellH, gap3, gap6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(int i, Prayer prayer, Prayer hl, double cellW3, double cellW6,
      double cellH, double gap3, double gap6) {
    final col3 = i % 3, row3 = i ~/ 3;
    final x3 = col3 * (cellW3 + gap3);
    final y3 = row3 * (cellH + 10);
    final x6 = i * (cellW6 + gap6);
    const y6 = 0.0;
    final x = lerpDouble(x3, x6, p)!;
    final y = lerpDouble(y3, y6, p)!;
    final wid = lerpDouble(cellW3, cellW6, p)!;
    final active = prayer == hl;
    return Positioned(
      left: x,
      top: y,
      width: wid,
      height: cellH,
      child: Container(
        decoration: BoxDecoration(
          color: active ? c.gdim : null,
          border: Border.all(color: active ? c.gold : c.hair),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
                child: Text(s.prayers[i],
                    style: JType.ui(11, color: active ? c.gold : c.faint))),
            const SizedBox(height: 2),
            FittedBox(
                child: Text(t.fmt(prayer),
                    style: JType.ui(14, w: FontWeight.w700, color: active ? c.gold : c.sub))),
          ],
        ),
      ),
    );
  }
}

// ── Слой «главный»: заголовок, карточка окна / бейдж, подсказка. Уезжает вверх ─
class _HomeLayer extends StatelessWidget {
  const _HomeLayer({
    required this.p,
    required this.s,
    required this.c,
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
          Text(s.windowOpen, style: JType.caption(c.gold)),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: JType.ui(34, w: FontWeight.w800, color: c.ink, h: 1.1)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(sub,
                textAlign: TextAlign.center, style: JType.ui(14, color: c.sub, h: 1.4)),
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
                              style: JType.ui(14, color: c.sub).copyWith(
                                  decoration: TextDecoration.underline,
                                  decorationColor: c.faint)),
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
              _AlreadyBar(s: s, c: c, app: app, top: h * 0.52),
              _swipeHint(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    // Лёгкая тень — читаемость шапки на художественном фоне.
    final shadow = [
      Shadow(color: c.bg.withValues(alpha: 0.6), blurRadius: 6),
    ];
    final style = JType.ui(12.5, color: c.sub).copyWith(shadows: shadow);
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
              Icon(Icons.place_outlined, size: 14, color: c.sub, shadows: shadow),
              const SizedBox(width: 3),
              Text(app.city.name, style: style),
              Icon(Icons.keyboard_arrow_down, size: 14, color: c.sub, shadows: shadow),
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
        child: GestureDetector(
          onTap: onExpand,
          behavior: HitTestBehavior.opaque,
          child: Column(
            children: [
              Container(
                  width: 36,
                  height: 4,
                  decoration:
                      BoxDecoration(color: c.hair, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 8),
              Text(s.swipe, style: JType.ui(11, color: c.faint)),
            ],
          ),
        ),
      );
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

class _AlreadyBar extends StatelessWidget {
  const _AlreadyBar({required this.s, required this.c, required this.app, required this.top});
  final S s;
  final JColors c;
  final AppState app;
  final double top;

  @override
  Widget build(BuildContext context) {
    final done = <String>[
      if (app.isDone('morning')) s.un[0],
      if (app.isDone('kahf')) s.un[1],
      if (app.isDone('evening')) s.un[2],
      if (app.isDone('dua')) s.un[3],
    ];
    if (done.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 44,
      child: Center(
        child: Text('${s.already} ${done.map((d) => '$d ✓').join(' · ')}',
            style: JType.caption(c.faint)),
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
  final void Function(String) onReader;
  final VoidCallback onCollapse, onToggleDate;

  @override
  Widget build(BuildContext context) {
    final eveningOpen =
        windowsFor(t).any((w) => w.id == TaskId.evening && w.contains(nowMin));
    final fade = Curves.easeIn.transform(p);
    // Контент дня начинается ниже геройской сетки (~0.42h) и «въезжает» снизу.
    return Transform.translate(
      offset: Offset(0, h * (1 - p)),
      child: Opacity(
        opacity: fade,
        child: SafeArea(
          child: Stack(
            children: [
              // Хэндл + «свайп вниз — назад» сверху дня.
              Positioned(
                left: 0,
                right: 0,
                top: 8,
                child: GestureDetector(
                  onTap: onCollapse,
                  behavior: HitTestBehavior.opaque,
                  child: Column(children: [
                    Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: c.hair, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 6),
                    Text(s.swipeBack, style: JType.ui(11, color: c.faint)),
                  ]),
                ),
              ),
              Positioned(
                left: 28,
                right: 28,
                top: h * 0.42,
                bottom: 0,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(s.todayCaps, style: JType.caption(c.faint)),
                      const SizedBox(height: 10),
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
                      const SizedBox(height: 22),
                      Text(_monthCaps(s, app), style: JType.caption(c.faint)),
                      const SizedBox(height: 12),
                      _Notebook(c: c),
                      const SizedBox(height: 10),
                      _Legend(s: s, c: c),
                      const SizedBox(height: 24),
                      Row(children: [
                        Expanded(
                            child: _SmallOutlineButton(
                                label: s.remindersBtn,
                                c: c,
                                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(app.lang == 'kz'
                                            ? 'Жасалуда…'
                                            : 'В разработке…'))))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _SmallOutlineButton(
                                label: s.themeBtn,
                                c: c,
                                onTap: () => app.theme = switch (app.theme) {
                                      'dark' => 'light',
                                      'light' => 'system',
                                      _ => 'dark',
                                    })),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _SmallOutlineButton(
                                label: s.langBtn,
                                c: c,
                                onTap: () => app.lang = app.lang == 'ru' ? 'kz' : 'ru')),
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _monthCaps(S s, AppState app) =>
      dateLine(s, DateTime.now(), app.dateGregorian).split(' ').last.toUpperCase();
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

class _TaskRow extends StatelessWidget {
  const _TaskRow(
      {required this.label,
      required this.done,
      required this.c,
      this.active = false,
      this.trailing,
      this.onTap});
  final String label;
  final bool done, active;
  final String? trailing;
  final JColors c;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: done ? .75 : 1,
      child: InkWell(
        onTap: done ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? c.green : null,
                border: done ? null : Border.all(color: active ? c.gold : c.hair),
              ),
              child: done ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
            ),
            const SizedBox(width: 12),
            Text(label,
                style: JType.ui(15,
                    w: active ? FontWeight.w700 : FontWeight.w400,
                    color: done ? c.sub : c.ink)),
            const Spacer(),
            if (trailing != null && !done)
              Text(trailing!, style: JType.ui(12, w: FontWeight.w700, color: c.gold)),
          ]),
        ),
      ),
    );
  }
}

class _Notebook extends StatelessWidget {
  const _Notebook({required this.c});
  final JColors c;
  static const _demo = 'ffpfffmffpfffffmffpt.';

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final ch in _demo.split(''))
          Center(
            child: switch (ch) {
              'f' => _dot(c.green, check: true),
              'p' => Transform.rotate(
                  angle: .785,
                  child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                          color: c.gold, borderRadius: BorderRadius.circular(5)))),
              'm' => _dot(c.red, cross: true),
              't' => Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, border: Border.all(color: c.gold, width: 2)),
                  child: _dot(c.gdim)),
              _ => Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, border: Border.all(color: c.hair))),
            },
          ),
      ],
    );
  }

  Widget _dot(Color color, {bool check = false, bool cross = false}) => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: check
            ? const Icon(Icons.check, size: 13, color: Colors.white)
            : cross
                ? const Icon(Icons.close, size: 13, color: Colors.white)
                : null,
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.s, required this.c});
  final S s;
  final JColors c;

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String label, {bool ring = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ring ? null : color,
                    border: ring ? Border.all(color: color, width: 2) : null)),
            const SizedBox(width: 5),
            Text(label, style: JType.ui(11, color: c.faint)),
          ],
        );
    return Wrap(spacing: 14, runSpacing: 6, children: [
      item(c.green, s.legendAll),
      item(c.gold, s.legendPart),
      item(c.red, s.legendMiss),
      item(c.gold, s.legendToday, ring: true),
    ]);
  }
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
            border: Border.all(color: c.hair), borderRadius: BorderRadius.circular(100)),
        child: Center(
          child: FittedBox(
              child: Text(label, style: JType.ui(13, w: FontWeight.w700, color: c.sub))),
        ),
      ),
    );
  }
}
