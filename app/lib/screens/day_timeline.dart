part of 'home.dart';

// ── Прототип «Лента дня» ─────────────────────────────────────────────────────
// Нижний экран одной лентой: намазы — опорные точки, дела стоят под своим
// намазом. Включается в «Оформлении» (нижний экран → лента дня). Классический
// вид не меняется. Экран не прокручивается: вертикальный свайп принадлежит
// переходу к таймеру, поэтому лента рассчитана на то, чтобы помещаться.

const _weekdaysRuFull = [
  'Понедельник',
  'Вторник',
  'Среда',
  'Четверг',
  'Пятница',
  'Суббота',
  'Воскресенье',
];
const _weekdaysKzFull = [
  'Дүйсенбі',
  'Сейсенбі',
  'Сәрсенбі',
  'Бейсенбі',
  'Жұма',
  'Сенбі',
  'Жексенбі',
];
const _weekdaysRuShort = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
const _weekdaysKzShort = ['дс', 'сс', 'ср', 'бс', 'жм', 'сб', 'жс'];

/// «Вторник, 29 сентября · 17 раби ас-сани» — обе даты сразу, без скрытого тапа.
String _timelineDateLine(S s, DateTime now) {
  final kz = s == S.kz;
  final weekday = (kz ? _weekdaysKzFull : _weekdaysRuFull)[now.weekday - 1];
  final month = (kz ? _gregMonthsKz : _gregMonthsRu)[now.month - 1];
  final hijri = HijriCalendar.fromDate(now);
  final hMonth = (kz ? s.hijriMonths : _hijriMonthsRu)[hijri.hMonth - 1];
  return '$weekday, ${now.day} $month · ${hijri.hDay} $hMonth';
}

String _hhmm(int minutes) {
  final m = minutes % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

/// «через 1 ч 26 мин» — без секунд: в списке тикающие секунды только шумят,
/// посекундный таймер остаётся на главном экране.
String _timelineCountdown(S s, int seconds) {
  final minutes = ((seconds.clamp(0, 86400)) / 60).ceil();
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (s == S.kz) {
    if (h == 0) return '$m мин кейін';
    return m == 0 ? '$h сағ кейін' : '$h сағ $m мин кейін';
  }
  if (h == 0) return 'через $m мин';
  return m == 0 ? 'через $h ч' : 'через $h ч $m мин';
}

enum _TaskState { upcoming, open, done, passed }

class _TimelineTask {
  const _TimelineTask({
    required this.id,
    required this.label,
    required this.minute,
    required this.hint,
    required this.state,
    required this.onTap,
  });

  final String id, label, hint;
  final int minute;
  final _TaskState state;
  final VoidCallback onTap;
}

class _TimelineDayLayer extends StatelessWidget {
  const _TimelineDayLayer({
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
  });

  final double p, h;
  final S s;
  final DaySurfacePalette palette;
  final AppState app;
  final DayTimes t;
  final int nowMin, nowSec;
  final ScheduleService schedule;
  final void Function(String) onReader;
  final VoidCallback onCollapse;

  List<_TimelineTask> _tasks() {
    final kz = s == S.kz;
    final windows = {for (final w in windowsFor(t)) w.id: w};

    _TaskState stateOf(String id, int start, int end) {
      if (app.isDone(id)) return _TaskState.done;
      if (nowMin >= start && nowMin < end) return _TaskState.open;
      if (nowMin >= end) return _TaskState.passed;
      return _TaskState.upcoming;
    }

    String until(int end) => kz ? '${_hhmm(end)} дейін' : 'до ${_hhmm(end)}';

    final tasks = <_TimelineTask>[];
    void addWindow(TaskId id, String label, VoidCallback onTap, String hint) {
      final w = windows[id];
      if (w == null) return;
      tasks.add(
        _TimelineTask(
          id: id.name,
          label: label,
          minute: w.start,
          hint: hint,
          state: stateOf(id.name, w.start, w.end),
          onTap: onTap,
        ),
      );
    }

    final morning = windows[TaskId.morning];
    if (morning != null) {
      addWindow(
        TaskId.morning,
        s.morningTitle,
        () => onReader('morning'),
        until(morning.end),
      );
    }
    final kahf = windows[TaskId.kahf];
    if (kahf != null) {
      addWindow(
        TaskId.kahf,
        s.kahfTitle,
        () => onReader('kahf'),
        until(kahf.end),
      );
    }
    final evening = windows[TaskId.evening];
    if (evening != null) {
      addWindow(
        TaskId.evening,
        s.eveningTitle,
        () => onReader('evening'),
        until(evening.end),
      );
    }
    final dua = windows[TaskId.dua];
    if (dua != null) {
      addWindow(
        TaskId.dua,
        s.duaTitle,
        () => app.markDone('dua'),
        '${_hhmm(dua.start)}–${_hhmm(dua.end)}',
      );
    }

    for (final reminder in app.customReminders.where(
      (item) => app.reminderOccursOn(item, t.date),
    )) {
      final minute = reminder.isPrayerLinked
          ? t.times[Prayer.values[reminder.prayer.clamp(0, 5)]]! +
                reminder.offsetMin
          : reminder.fixedHour * 60 + reminder.fixedMinute;
      final id = 'custom:${reminder.id}';
      tasks.add(
        _TimelineTask(
          id: id,
          label: reminder.title,
          minute: minute,
          hint: _hhmm(minute),
          state: stateOf(id, minute, minute + taskRailGraceMinutes),
          onTap: () => app.markDone(id),
        ),
      );
    }
    return tasks;
  }

  @override
  Widget build(BuildContext context) {
    final c = palette.colors;
    final fade = const Interval(
      0.14,
      1.0,
      curve: Curves.easeOutCubic,
    ).transform(p.clamp(0.0, 1.0));
    final now = schedule.now();

    return Transform.translate(
      offset: Offset(0, h * (1 - p)),
      child: Opacity(
        opacity: fade,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final content = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    const SizedBox(height: 8),
                    _StagedReveal(
                      progress: p,
                      start: 0.17,
                      child: _TimelineHeader(s: s, c: c, app: app, now: now),
                    ),
                    const SizedBox(height: 12),
                    _StagedReveal(
                      progress: p,
                      start: 0.22,
                      child: _SurfaceCard(
                        palette: palette,
                        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                        child: _TimelineList(
                          s: s,
                          c: c,
                          t: t,
                          nowSec: nowSec,
                          tasks: _tasks(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _StagedReveal(
                      progress: p,
                      start: 0.32,
                      child: _SurfaceCard(
                        palette: palette,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: _WeekStrip(
                          s: s,
                          c: c,
                          app: app,
                          now: now,
                          palette: palette,
                        ),
                      ),
                    ),
                  ],
                );
                return Column(
                  children: [
                    Expanded(
                      // Страховка для маленьких экранов и длинного списка своих
                      // напоминаний: ленту не обрезаем, а аккуратно ужимаем.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          child: content,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _StagedReveal(
                      progress: p,
                      start: 0.42,
                      child: _TimelineDock(
                        s: s,
                        palette: palette,
                        onReminders: () => RemindersScreen.open(context),
                        onSettings: () => _showTimelineSettings(context),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({
    required this.s,
    required this.c,
    required this.app,
    required this.now,
  });

  final S s;
  final JColors c;
  final AppState app;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final kz = s == S.kz;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kz ? 'Бүгін' : 'Сегодня',
                style: JType.ui(26, w: FontWeight.w700, color: c.ink),
              ),
              const SizedBox(height: 2),
              Text(
                _timelineDateLine(s, now),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JType.ui(13, color: c.sub),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: kz ? 'Қаланы өзгерту' : 'Сменить город',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              CityPicker.open(context);
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: c.ink.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.location_solid, size: 13, color: c.sub),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      app.city.displayName(app.lang),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: JType.ui(13, w: FontWeight.w600, color: c.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Одна лента: намазы по порядку, дела — под своим намазом по времени начала.
class _TimelineList extends StatelessWidget {
  const _TimelineList({
    required this.s,
    required this.c,
    required this.t,
    required this.nowSec,
    required this.tasks,
  });

  final S s;
  final JColors c;
  final DayTimes t;
  final int nowSec;
  final List<_TimelineTask> tasks;

  @override
  Widget build(BuildContext context) {
    // Следующий намаз — тот же расчёт, что у классического списка.
    Prayer? next;
    var targetSec = t.times[Prayer.fajr]! * 60 + 86400;
    for (final prayer in Prayer.values) {
      final candidate = t.times[prayer]! * 60;
      if (candidate > nowSec) {
        next = prayer;
        targetSec = candidate;
        break;
      }
    }
    next ??= Prayer.fajr;
    final countdown = _timelineCountdown(s, targetSec - nowSec);

    final rows = <Widget>[];
    final sorted = [...tasks]..sort((a, b) => a.minute.compareTo(b.minute));
    var taskIndex = 0;
    final prayers = Prayer.values;
    for (var i = 0; i < prayers.length; i++) {
      final prayer = prayers[i];
      final at = t.times[prayer]!;
      // Дела, начавшиеся до этого намаза, стоят под предыдущим.
      while (taskIndex < sorted.length && sorted[taskIndex].minute < at) {
        rows.add(
          _TimelineTaskRow(task: sorted[taskIndex], c: c, s: s, isLast: false),
        );
        taskIndex++;
      }
      rows.add(
        _TimelinePrayerRow(
          name: s.prayers[i],
          time: t.fmt(prayer),
          isSunrise: prayer == Prayer.sunrise,
          isNext: prayer == next,
          isPast: at * 60 <= nowSec && prayer != next,
          countdown: prayer == next ? countdown : null,
          isFirst: i == 0,
          // Линия обрывается на последней строке ленты.
          isLast: i == prayers.length - 1 && taskIndex >= sorted.length,
          c: c,
          onTap: () => _showQuickSettings(context, prayer.name, s.prayers[i], c),
        ),
      );
    }
    while (taskIndex < sorted.length) {
      rows.add(
        _TimelineTaskRow(
          task: sorted[taskIndex],
          c: c,
          s: s,
          isLast: taskIndex == sorted.length - 1,
        ),
      );
      taskIndex++;
    }
    return Column(children: rows);
  }
}

/// Левая колонка ленты: сплошная вертикальная линия и точка намаза.
class _TimelineRail extends StatelessWidget {
  const _TimelineRail({
    required this.c,
    this.dot,
    this.top = true,
    this.bottom = true,
  });

  final JColors c;
  final Widget? dot;
  final bool top, bottom;

  @override
  Widget build(BuildContext context) {
    final line = c.hair.withValues(alpha: 0.9);
    return SizedBox(
      width: 26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            children: [
              Expanded(
                child: Container(width: 1.2, color: top ? line : null),
              ),
              Expanded(
                child: Container(width: 1.2, color: bottom ? line : null),
              ),
            ],
          ),
          ?dot,
        ],
      ),
    );
  }
}

class _TimelinePrayerRow extends StatelessWidget {
  const _TimelinePrayerRow({
    required this.name,
    required this.time,
    required this.isSunrise,
    required this.isNext,
    required this.isPast,
    required this.countdown,
    required this.isFirst,
    required this.isLast,
    required this.c,
    required this.onTap,
  });

  final String name, time;
  final String? countdown;
  final bool isSunrise, isNext, isPast, isFirst, isLast;
  final JColors c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Восход — граница времени Фаджра, а не намаз: мельче и тише.
    final color = isNext ? c.gold : (isPast || isSunrise ? c.sub : c.ink);
    final size = isSunrise ? 13.0 : (isNext ? 16.5 : 15.0);
    final weight = isNext
        ? FontWeight.w700
        : (isSunrise ? FontWeight.w400 : FontWeight.w500);
    final dotSize = isSunrise ? 6.0 : (isNext ? 12.0 : 8.0);
    final dot = Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isNext
            ? c.gold
            : isSunrise
            ? c.sub.withValues(alpha: 0.6)
            : (isPast ? c.sub.withValues(alpha: 0.7) : c.ink),
        boxShadow: isNext
            ? [BoxShadow(color: c.gold.withValues(alpha: 0.35), blurRadius: 8)]
            : null,
      ),
    );

    return _ScalePressed(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: isSunrise ? 34 : 44),
        decoration: BoxDecoration(
          color: isNext ? c.gold.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TimelineRail(c: c, dot: dot, top: !isFirst, bottom: !isLast),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JType.ui(size, w: weight, color: color),
                  ),
                ),
              ),
              if (countdown != null)
                Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      countdown!,
                      style: JType.ui(
                        12.5,
                        w: FontWeight.w600,
                        color: c.gold.withValues(alpha: 0.92),
                      ),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  time,
                  style: JType.ui(
                    size,
                    w: weight,
                    color: color,
                  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineTaskRow extends StatelessWidget {
  const _TimelineTaskRow({
    required this.task,
    required this.c,
    required this.s,
    required this.isLast,
  });

  final _TimelineTask task;
  final JColors c;
  final S s;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final kz = s == S.kz;
    final done = task.state == _TaskState.done;
    final open = task.state == _TaskState.open;
    final passed = task.state == _TaskState.passed;
    final labelColor = done || passed ? c.sub : (open ? c.gold : c.ink);
    final hint = done
        ? (kz ? 'орындалды' : 'выполнено')
        : open
        ? (kz ? 'қазір · ${task.hint}' : 'сейчас · ${task.hint}')
        : task.hint;

    return Semantics(
      button: !done,
      checked: done,
      label: task.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: done
            ? null
            : () {
                HapticFeedback.selectionClick();
                task.onTap();
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TimelineRail(c: c, bottom: !isLast),
                const SizedBox(width: 8),
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? c.green : Colors.transparent,
                      border: done
                          ? null
                          : Border.all(
                              color: open ? c.gold : c.hair,
                              width: open ? 1.6 : 1.2,
                            ),
                    ),
                    child: done
                        ? const Icon(
                            CupertinoIcons.check_mark,
                            size: 13,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: JType.ui(
                            14,
                            w: open ? FontWeight.w700 : FontWeight.w600,
                            color: labelColor,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: JType.ui(
                            11.5,
                            color: open
                                ? c.gold.withValues(alpha: 0.85)
                                : c.sub,
                          ),
                        ),
                      ],
                    ),
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

/// Постоянство за текущую неделю. Отсчёт — с первого дня пользования:
/// дней до установки просто нет. Полный месяц — по «Месяц ›».
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.s,
    required this.c,
    required this.app,
    required this.now,
    required this.palette,
  });

  final S s;
  final JColors c;
  final AppState app;
  final DateTime now;
  final DaySurfacePalette palette;

  @override
  Widget build(BuildContext context) {
    final kz = s == S.kz;
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final since = app.firstUseDate;
    final names = kz ? _weekdaysKzShort : _weekdaysRuShort;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _sentenceCase(s.notebookTitle),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JType.ui(15, w: FontWeight.w700, color: c.ink),
              ),
            ),
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _showMonthSheet(context);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Text(
                        kz ? 'Ай' : 'Месяц',
                        style: JType.ui(13, w: FontWeight.w600, color: c.sub),
                      ),
                      const SizedBox(width: 2),
                      Icon(CupertinoIcons.chevron_right, size: 12, color: c.sub),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: _weekDay(
                  context,
                  monday.add(Duration(days: i)),
                  names[i],
                  today,
                  since,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _weekDay(
    BuildContext context,
    DateTime date,
    String name,
    DateTime today,
    DateTime since,
  ) {
    final isToday = date == today;
    final inactive = date.isAfter(today) || date.isBefore(since);
    final (done, total) = app.taskProgressOn(date);
    final cell = inactive
        ? SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: Text(
                '${date.day}',
                style: JType.ui(11, color: c.faint),
              ),
            ),
          )
        : _RingCell(
            day: date.day,
            frac: total == 0 ? 0 : done / total,
            isToday: isToday,
            gold: c.gold,
            faint: c.faint,
          );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: inactive
          ? null
          : () {
              HapticFeedback.selectionClick();
              _showDayDetailsSheet(
                context,
                date: date,
                s: s,
                app: app,
                palette: palette,
              );
            },
      child: Column(
        children: [
          Text(
            name,
            style: JType.ui(
              10.5,
              w: isToday ? FontWeight.w700 : FontWeight.w400,
              color: isToday ? c.gold : c.faint,
            ),
          ),
          const SizedBox(height: 4),
          cell,
        ],
      ),
    );
  }

  void _showMonthSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (sheetContext) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: Container(
          color: palette.isLight
              ? const Color(0xFFF1F0EA)
              : const Color(0xFF111C22),
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.faint.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _sentenceCase(s.notebookTitle),
                        style: JType.ui(20, w: FontWeight.w700, color: c.ink),
                      ),
                    ),
                    Text(
                      _monthYearLabel(s, now),
                      style: JType.ui(13, color: c.sub),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _Notebook(
                  c: c,
                  app: app,
                  now: now,
                  since: app.firstUseDate,
                  onDayTap: (date) => _showDayDetailsSheet(
                    sheetContext,
                    date: date,
                    s: s,
                    app: app,
                    palette: palette,
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

class _TimelineDock extends StatelessWidget {
  const _TimelineDock({
    required this.s,
    required this.palette,
    required this.onReminders,
    required this.onSettings,
  });

  final S s;
  final DaySurfacePalette palette;
  final VoidCallback onReminders, onSettings;

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
                    icon: CupertinoIcons.gear,
                    label: s == S.kz ? 'Баптаулар' : 'Настройки',
                    color: c.ink,
                    onTap: onSettings,
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

/// Единое место настроек вместо разбросанных тапов по городу и дате.
void _showTimelineSettings(BuildContext context) {
  DauamSettingsSheet.open<void>(
    context,
    heightFactor: .62,
    builder: (_) => _TimelineSettingsPage(outer: context),
  );
}

class _TimelineSettingsPage extends StatelessWidget {
  const _TimelineSettingsPage({required this.outer});

  /// Контекст экрана дня: из него открываются вложенные листы после
  /// закрытия настроек, чтобы не складывать листы друг на друга.
  final BuildContext outer;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';

    void openAfterClose(void Function(BuildContext) open) {
      Navigator.of(context, rootNavigator: true).pop();
      open(outer);
    }

    return DauamSettingsPage(
      root: true,
      title: kz ? 'Баптаулар' : 'Настройки',
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            DauamSection(
              children: [
                DauamSettingsRow(
                  icon: CupertinoIcons.location,
                  title: kz ? 'Қала' : 'Город',
                  value: app.city.displayName(app.lang),
                  onTap: () => openAfterClose(CityPicker.open),
                ),
                DauamSettingsRow(
                  icon: CupertinoIcons.paintbrush,
                  title: kz ? 'Көрініс' : 'Оформление',
                  onTap: () => openAfterClose(AppearancePicker.open),
                ),
                DauamSettingsRow(
                  icon: CupertinoIcons.globe,
                  title: kz ? 'Тіл' : 'Язык',
                  value: kz ? 'Қазақша' : 'Русский',
                  onTap: () => openAfterClose(LanguagePicker.open),
                ),
              ],
            ),
            DauamSection(
              label: kz ? 'Прототип' : 'Прототип',
              footer: kz
                  ? 'Сынақ нұсқасы. Классикалық көріністі кез келген уақытта қайтаруға болады.'
                  : 'Пробный вариант. Классический вид можно вернуть в любой момент.',
              children: [
                DauamSwitchRow(
                  title: kz ? 'Күн таспасы' : 'Лента дня',
                  value: app.dayLayout == 'timeline',
                  onChanged: (on) => app.dayLayout = on ? 'timeline' : 'classic',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
