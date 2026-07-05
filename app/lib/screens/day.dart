import 'package:flutter/material.dart';
import '../data/app_state.dart';
import '../i18n/strings.dart';
import '../prayer/schedule.dart';
import '../prayer/schedule_service.dart';
import '../prayer/windows.dart';
import '../theme/tokens.dart';
import 'home.dart';
import 'reader.dart';

/// «День и тетрадь» (README §3): свайп вверх с главного. Таймер, все времена,
/// задачи дня и тетрадь постоянства. Свайп вниз или тап по хэндлу — назад.
class DayScreen extends StatelessWidget {
  const DayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final schedule = ScheduleScope.of(context);
    final s = S.of(app.lang);
    final c = jColorsOf(context);
    final now = schedule.now();
    final nowMin = now.hour * 60 + now.minute;
    final t = schedule.timesFor(app.city, now);
    if (t == null) {
      return Scaffold(
          backgroundColor: c.bg,
          body: Center(child: CircularProgressIndicator(color: c.gold)));
    }
    final next = nextPrayer(t, nowMin);
    final windows = windowsFor(t);
    final eveningOpen = windows
        .any((w) => w.id == TaskId.evening && w.contains(nowMin));

    return Scaffold(
      backgroundColor: c.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).pop();
        },
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: c.hair, borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(height: 6),
                      Text(s.swipeBack, style: JType.ui(11, color: c.faint)),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => app.dateGregorian = !app.dateGregorian,
                      behavior: HitTestBehavior.opaque,
                      child: Text(dateLine(s, now, app.dateGregorian),
                          style: JType.ui(13, color: c.sub)),
                    ),
                    Text(app.city.name, style: JType.ui(13, color: c.faint)),
                  ],
                ),
                const SizedBox(height: 20),
                if (next != null)
                  Center(
                    child: Column(
                      children: [
                        Text(s.toPrayerCaps[next.index], style: JType.caption(c.gold)),
                        const SizedBox(height: 4),
                        Text(DayTimes.fmtDuration(t.times[next]! - nowMin),
                            style: JType.timer(52, c.ink)),
                        Text(
                            s.atTpl
                                .replaceFirst('{p}', s.prayers[next.index])
                                .replaceFirst('{t}', t.fmt(next)),
                            style: JType.ui(12, color: c.faint)),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                _TimesRow(s: s, c: c, t: t, nowMin: nowMin),
                const SizedBox(height: 24),
                Text(s.todayCaps, style: JType.caption(c.faint)),
                const SizedBox(height: 10),
                _TaskRow(
                    label: s.morningTitle,
                    done: app.isDone(TaskId.morning.name),
                    c: c,
                    onTap: () => _openReader(context, 'morning')),
                if (t.isFriday)
                  _TaskRow(
                      label: s.kahfTitle,
                      done: app.isDone(TaskId.kahf.name),
                      c: c,
                      onTap: () => app.markDone(TaskId.kahf.name)),
                _TaskRow(
                    label: s.eveningTitle,
                    done: app.isDone(TaskId.evening.name),
                    c: c,
                    active: eveningOpen && !app.isDone(TaskId.evening.name),
                    trailing: eveningOpen
                        ? '${s.still} ${DayTimes.fmtDuration(t.times[Prayer.maghrib]! - nowMin)}'
                        : null,
                    onTap: () => _openReader(context, 'evening')),
                if (t.isFriday)
                  _TaskRow(
                      label: s.duaTitle,
                      done: app.isDone(TaskId.dua.name),
                      c: c,
                      onTap: () => app.markDone(TaskId.dua.name)),
                const SizedBox(height: 24),
                Text(_monthCaps(s, now, app.dateGregorian), style: JType.caption(c.faint)),
                const SizedBox(height: 12),
                _Notebook(c: c),
                const SizedBox(height: 10),
                _Legend(s: s, c: c),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                        child: _SmallOutlineButton(
                            label: s.remindersBtn,
                            c: c,
                            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        app.lang == 'kz' ? 'Жасалуда…' : 'В разработке…'))))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _SmallOutlineButton(
                            label: s.themeBtn,
                            c: c,
                            onTap: () => AppScope.of(context).theme = switch (app.theme) {
                                  'dark' => 'light',
                                  'light' => 'system',
                                  _ => 'dark',
                                })),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _SmallOutlineButton(
                            label: s.langBtn,
                            c: c,
                            onTap: () =>
                                AppScope.of(context).lang = app.lang == 'ru' ? 'kz' : 'ru')),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openReader(BuildContext context, String id) =>
      Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true, builder: (_) => ReaderScreen(collectionId: id)));

  static String _monthCaps(S s, DateTime now, bool gregorian) =>
      dateLine(s, now, gregorian).split(' ').last.toUpperCase();
}

class _TimesRow extends StatelessWidget {
  const _TimesRow({required this.s, required this.c, required this.t, required this.nowMin});
  final S s;
  final JColors c;
  final DayTimes t;
  final int nowMin;

  @override
  Widget build(BuildContext context) {
    final hl = nextPrayer(t, nowMin) ?? Prayer.fajr;
    return Row(
      children: [
        for (final (i, p) in Prayer.values.indexed) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: p == hl ? c.gdim : null,
                border: Border.all(color: p == hl ? c.gold : c.hair),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  FittedBox(
                      child: Text(s.prayers[i],
                          style: JType.ui(10, color: p == hl ? c.gold : c.faint))),
                  const SizedBox(height: 2),
                  FittedBox(
                      child: Text(t.fmt(p),
                          style: JType.ui(12,
                              w: FontWeight.w700, color: p == hl ? c.gold : c.sub))),
                ],
              ),
            ),
          ),
          if (p != Prayer.isha) const SizedBox(width: 6),
        ],
      ],
    );
  }
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
              Text(label,
                  style: JType.ui(15,
                      w: active ? FontWeight.w700 : FontWeight.w400,
                      color: done ? c.sub : c.ink)),
              const Spacer(),
              if (trailing != null && !done)
                Text(trailing!, style: JType.ui(12, w: FontWeight.w700, color: c.gold)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Тетрадь постоянства — демо-история месяца (реальная история появится
/// вместе с локальной БД отметок).
class _Notebook extends StatelessWidget {
  const _Notebook({required this.c});
  final JColors c;

  // 21 день: f=всё, p=частично, m=пропущен, t=сегодня, .=будущее
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
                        color: c.gold, borderRadius: BorderRadius.circular(5)),
                  ),
                ),
              'm' => _dot(c.red, cross: true),
              't' => Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, border: Border.all(color: c.gold, width: 2)),
                  child: _dot(c.gdim),
                ),
              _ => Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.hair, style: BorderStyle.solid),
                  ),
                ),
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
                border: ring ? Border.all(color: color, width: 2) : null,
              ),
            ),
            const SizedBox(width: 5),
            Text(label, style: JType.ui(11, color: c.faint)),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        item(c.green, s.legendAll),
        item(c.gold, s.legendPart),
        item(c.red, s.legendMiss),
        item(c.gold, s.legendToday, ring: true),
      ],
    );
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
          border: Border.all(color: c.hair),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Center(
          child: FittedBox(
            child: Text(label, style: JType.ui(13, w: FontWeight.w700, color: c.sub)),
          ),
        ),
      ),
    );
  }
}
