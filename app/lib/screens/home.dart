import 'package:flutter/material.dart';
import '../data/app_state.dart';
import '../i18n/strings.dart';
import '../prayer/schedule.dart';
import '../theme/tokens.dart';
import 'day.dart';
import 'reader.dart';

/// Главный экран «одно дело» (README §2): показывает ровно одну актуальную
/// вещь — открытое окно поклонения, час дуа или таймер до следующей молитвы.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const schedule = DemoScheduleProvider();

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

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = S.of(app.lang);
    final c = jColorsOf(context);
    final day = schedule.today();
    final toMaghrib = day.minutesUntil(Prayer.maghrib);

    final Widget center;
    if (!app.isDone('evening')) {
      center = _WindowCard(
        s: s,
        c: c,
        caption: s.windowOpen,
        title: s.eveningTitle,
        sub: s.eveningSub,
        timer: DaySchedule.fmtDuration(toMaghrib),
        timerCaption: s.toMaghrib,
        buttonLabel: s.read,
        onButton: () => Navigator.of(context).push(MaterialPageRoute(
            fullscreenDialog: true, builder: (_) => const ReaderScreen(collectionId: 'evening'))),
        linkLabel: s.markOnly,
        onLink: () => app.markDone('evening'),
      );
    } else if (day.isFriday && !app.isDone('dua')) {
      center = _WindowCard(
        s: s,
        c: c,
        caption: s.windowOpen,
        title: s.duaTitle,
        sub: s.duaSub,
        timer: DaySchedule.fmtDuration(toMaghrib),
        timerCaption: s.toMaghrib,
        buttonLabel: s.markDua,
        onButton: () => app.markDone('dua'),
      );
    } else {
      center = _AllDone(s: s, c: c, day: day);
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
                    Text(cities[app.city], style: JType.ui(12, color: c.faint)),
                    Text(_dateLine(app.lang), style: JType.ui(12, color: c.faint)),
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

  static String _dateLine(String lang) =>
      lang == 'kz' ? 'Жұма · 19 мухаррам' : 'Пятница · 19 мухаррама';
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
    required this.s,
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

  final S s;
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
        Text(sub,
            textAlign: TextAlign.center, style: JType.ui(14, color: c.sub, h: 1.4)),
        const SizedBox(height: 28),
        Text(timer, style: JType.timer(64, c.ink)),
        Text(timerCaption, style: JType.ui(13, color: c.faint)),
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

class _AllDone extends StatelessWidget {
  const _AllDone({required this.s, required this.c, required this.day});
  final S s;
  final JColors c;
  final DaySchedule day;

  @override
  Widget build(BuildContext context) {
    final toMaghrib = day.minutesUntil(Prayer.maghrib);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
        Text(s.nextPrayerCaps, style: JType.caption(c.gold)),
        const SizedBox(height: 6),
        Text(DaySchedule.fmtDuration(toMaghrib), style: JType.timer(72, c.ink)),
        Text(s.maghribAt, style: JType.ui(13, color: c.faint)),
        const SizedBox(height: 30),
        _PrayerGrid(s: s, c: c, day: day, columns: 3),
      ],
    );
  }
}

class _PrayerGrid extends StatelessWidget {
  const _PrayerGrid({required this.s, required this.c, required this.day, required this.columns});
  final S s;
  final JColors c;
  final DaySchedule day;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final cells = [
      for (final (i, p) in Prayer.values.indexed)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: p == Prayer.maghrib ? c.gdim : null,
            border: Border.all(color: p == Prayer.maghrib ? c.gold : c.hair),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(s.prayers[i],
                  style: JType.ui(11, color: p == Prayer.maghrib ? c.gold : c.faint)),
              const SizedBox(height: 2),
              Text(day.fmt(p),
                  style: JType.ui(14,
                      w: FontWeight.w700,
                      color: p == Prayer.maghrib ? c.gold : c.sub)),
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
      if (app.isDone('morning')) s.un[0],
      if (app.isDone('kahf')) s.un[1],
      if (app.isDone('evening')) s.un[2],
      if (app.isDone('dua')) s.un[3],
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
