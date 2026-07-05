import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';
import '../data/app_state.dart';
import '../i18n/strings.dart';
import '../prayer/schedule.dart';
import '../prayer/schedule_service.dart';
import '../prayer/windows.dart';
import '../theme/tokens.dart';
import 'city_picker.dart';
import 'day.dart';
import 'reader.dart';

/// Главный экран «одно дело» (README §2): показывает ровно одну актуальную
/// вещь — открытое окно поклонения или таймер до следующей молитвы.
/// Времена — реальные (ДУМК/расчёт), таймер живой (посекундно).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _ticker;

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
    super.dispose();
  }

  void _openDay(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, _, _) => const DayScreen(),
      transitionsBuilder: (_, anim, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: const Cubic(.22, .8, .3, 1))),
        child: child,
      ),
    ));
  }

  void _openReader(BuildContext context, String collectionId) =>
      Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ReaderScreen(collectionId: collectionId)));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final schedule = ScheduleScope.of(context);
    final s = S.of(app.lang);
    final c = jColorsOf(context);
    final now = schedule.now();
    final t = schedule.timesFor(app.city, now);
    final nowMin = now.hour * 60 + now.minute;
    final nowSec = now.hour * 3600 + now.minute * 60 + now.second;

    Widget center;
    if (t == null) {
      center = CircularProgressIndicator(color: c.gold);
    } else {
      final w = currentWindow(t, nowMin, (id) => app.isDone(id.name));
      String toPrayer(Prayer p) => DayTimes.fmtHMS(t.times[p]! * 60 - nowSec);
      center = switch (w?.id) {
        TaskId.morning => _WindowCard(
            c: c,
            caption: s.windowOpen,
            title: s.morningTitle,
            sub: s.morningSub,
            timer: toPrayer(Prayer.sunrise),
            timerCaption: s.toPrayerCaps[Prayer.sunrise.index],
            buttonLabel: s.read,
            onButton: () => _openReader(context, 'morning'),
            linkLabel: s.markOnly,
            onLink: () => app.markDone(TaskId.morning.name),
          ),
        TaskId.kahf => _WindowCard(
            c: c,
            caption: s.windowOpen,
            title: s.kahfTitle,
            sub: s.kahfSub,
            timer: toPrayer(Prayer.dhuhr),
            timerCaption: s.toPrayerCaps[Prayer.dhuhr.index],
            buttonLabel: s.markKahf,
            onButton: () => app.markDone(TaskId.kahf.name),
          ),
        TaskId.evening => _WindowCard(
            c: c,
            caption: s.windowOpen,
            title: s.eveningTitle,
            sub: s.eveningSub,
            timer: toPrayer(Prayer.maghrib),
            timerCaption: s.toPrayerCaps[Prayer.maghrib.index],
            buttonLabel: s.read,
            onButton: () => _openReader(context, 'evening'),
            linkLabel: s.markOnly,
            onLink: () => app.markDone(TaskId.evening.name),
          ),
        TaskId.dua => _WindowCard(
            c: c,
            caption: s.windowOpen,
            title: s.duaTitle,
            sub: s.duaSub,
            timer: toPrayer(Prayer.maghrib),
            timerCaption: s.toPrayerCaps[Prayer.maghrib.index],
            buttonLabel: s.markDua,
            onButton: () => app.markDone(TaskId.dua.name),
          ),
        null => _StatusCenter(s: s, c: c, schedule: schedule, t: t, nowSec: nowSec),
      };
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -300) _openDay(context);
        },
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => CityPicker.open(context),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Icon(Icons.place_outlined, size: 14, color: c.faint),
                          const SizedBox(width: 3),
                          Text(app.city.name, style: JType.ui(12, color: c.faint)),
                          Icon(Icons.keyboard_arrow_down, size: 14, color: c.faint),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => app.dateGregorian = !app.dateGregorian,
                      behavior: HitTestBehavior.opaque,
                      child: Text(dateLine(s, now, app.dateGregorian),
                          style: JType.ui(12, color: c.faint)),
                    ),
                  ],
                ),
                Expanded(child: Center(child: center)),
                _AlreadyLine(s: s, c: c, app: app),
                const SizedBox(height: 14),
                _SwipeHint(s: s, c: c, onTap: () => _openDay(context)),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
  final h = HijriCalendar.fromDate(now);
  final months = s == S.kz ? s.hijriMonths : _hijriMonthsRu;
  return '$wd · ${h.hDay} ${months[h.hMonth - 1]}';
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

class _WindowCard extends StatelessWidget {
  const _WindowCard({
    required this.c,
    required this.caption,
    required this.title,
    required this.sub,
    required this.timer,
    required this.timerCaption,
    required this.buttonLabel,
    required this.onButton,
    this.linkLabel,
    this.onLink,
  });

  final JColors c;
  final String caption, title, sub, timer, timerCaption, buttonLabel;
  final VoidCallback onButton;
  final String? linkLabel;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(caption, style: JType.caption(c.gold)),
        const SizedBox(height: 14),
        Text(title,
            textAlign: TextAlign.center,
            style: JType.ui(38, w: FontWeight.w800, color: c.ink, h: 1.1)),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(sub,
              textAlign: TextAlign.center, style: JType.ui(14, color: c.sub, h: 1.4)),
        ),
        const SizedBox(height: 28),
        Text(timer, style: JType.timer(56, c.ink)),
        Text(timerCaption.toLowerCase(), style: JType.ui(13, color: c.faint)),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: onButton,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 16),
            decoration:
                BoxDecoration(color: c.btnbg, borderRadius: BorderRadius.circular(100)),
            child: Text(buttonLabel,
                style: JType.ui(16, w: FontWeight.w700, color: c.btnink)),
          ),
        ),
        if (linkLabel != null) ...[
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onLink,
            child: Text(linkLabel!,
                style: JType.ui(14, color: c.sub).copyWith(
                    decoration: TextDecoration.underline, decorationColor: c.faint)),
          ),
        ],
      ],
    );
  }
}

/// Состояние вне окон: таймер до следующей молитвы (или «после азана» —
/// первые минуты после наступления времени), сетка времён, бейдж «всё выполнено».
class _StatusCenter extends StatelessWidget {
  const _StatusCenter(
      {required this.s,
      required this.c,
      required this.schedule,
      required this.t,
      required this.nowSec});
  final S s;
  final JColors c;
  final ScheduleService schedule;
  final DayTimes t;
  final int nowSec;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final nowMin = nowSec ~/ 60;
    final done = allDone(t, (id) => app.isDone(id.name));

    // Режим «после азана»: удобно идущим в мечеть (джамаат через 10–20 мин).
    final called = justCalledPrayer(t, nowMin);
    final String caption, timer, subLine;
    if (called != null) {
      caption = s.afterAzanCaps[called.index];
      timer = DayTimes.fmtHMS(nowSec - t.times[called]! * 60);
      final next = nextPrayer(t, nowMin);
      subLine = next == null
          ? ''
          : s.atTpl.replaceFirst('{p}', s.prayers[next.index]).replaceFirst('{t}', t.fmt(next));
    } else {
      final next = nextPrayer(t, nowMin);
      if (next != null) {
        caption = s.toPrayerCaps[next.index];
        timer = DayTimes.fmtHMS(t.times[next]! * 60 - nowSec);
        subLine = s.atTpl
            .replaceFirst('{p}', s.prayers[next.index])
            .replaceFirst('{t}', t.fmt(next));
      } else {
        // Иша прошла — считаем до завтрашнего Фаджра.
        final tomorrow =
            schedule.timesFor(app.city, schedule.now().add(const Duration(days: 1)));
        final fajr = tomorrow?.times[Prayer.fajr] ?? 0;
        caption = s.toPrayerCaps[Prayer.fajr.index];
        timer = DayTimes.fmtHMS(24 * 3600 - nowSec + fajr * 60);
        subLine = tomorrow == null
            ? ''
            : s.atTpl
                .replaceFirst('{p}', s.prayers[Prayer.fajr.index])
                .replaceFirst('{t}', tomorrow.fmt(Prayer.fajr));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (done) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: c.green),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text('✓ ${s.allDone}',
                style: JType.ui(13, w: FontWeight.w700, color: c.green)),
          ),
          const SizedBox(height: 30),
        ],
        Text(caption, style: JType.caption(c.gold)),
        const SizedBox(height: 6),
        Text(timer, style: JType.timer(64, c.ink)),
        Text(subLine, style: JType.ui(13, color: c.faint)),
        const SizedBox(height: 30),
        PrayerGrid(s: s, c: c, t: t, nowMin: nowMin, columns: 3),
      ],
    );
  }
}

class PrayerGrid extends StatelessWidget {
  const PrayerGrid(
      {super.key,
      required this.s,
      required this.c,
      required this.t,
      required this.nowMin,
      required this.columns});
  final S s;
  final JColors c;
  final DayTimes t;
  final int nowMin;
  final int columns;

  /// Выделяем следующую молитву (или Фаджр, если день закончился).
  Prayer get highlighted => nextPrayer(t, nowMin) ?? Prayer.fajr;

  @override
  Widget build(BuildContext context) {
    final hl = highlighted;
    final cells = [
      for (final (i, p) in Prayer.values.indexed)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: p == hl ? c.gdim : null,
            border: Border.all(color: p == hl ? c.gold : c.hair),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                  child: Text(s.prayers[i],
                      style: JType.ui(11, color: p == hl ? c.gold : c.faint))),
              const SizedBox(height: 2),
              FittedBox(
                  child: Text(t.fmt(p),
                      style: JType.ui(14,
                          w: FontWeight.w700, color: p == hl ? c.gold : c.sub))),
            ],
          ),
        ),
    ];
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: columns == 3 ? 1.5 : 1.15,
      children: cells,
    );
  }
}

class _AlreadyLine extends StatelessWidget {
  const _AlreadyLine({required this.s, required this.c, required this.app});
  final S s;
  final JColors c;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final done = <String>[
      if (app.isDone(TaskId.morning.name)) s.un[0],
      if (app.isDone(TaskId.kahf.name)) s.un[1],
      if (app.isDone(TaskId.evening.name)) s.un[2],
      if (app.isDone(TaskId.dua.name)) s.un[3],
    ];
    if (done.isEmpty) return const SizedBox.shrink();
    return Text('${s.already} ${done.map((d) => '$d ✓').join(' · ')}',
        style: JType.caption(c.faint));
  }
}

/// Хэндл свайпа с периодическим подскоком-подсказкой (README: hintbounce).
class _SwipeHint extends StatefulWidget {
  const _SwipeHint({required this.s, required this.c, required this.onTap});
  final S s;
  final JColors c;
  final VoidCallback onTap;

  @override
  State<_SwipeHint> createState() => _SwipeHintState();
}

class _SwipeHintState extends State<_SwipeHint> with SingleTickerProviderStateMixin {
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
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _dy,
        builder: (_, child) => Transform.translate(offset: Offset(0, _dy.value), child: child),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: widget.c.hair, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            Text(widget.s.swipe, style: JType.ui(11, color: widget.c.faint)),
          ],
        ),
      ),
    );
  }
}
