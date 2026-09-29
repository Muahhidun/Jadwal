part of 'home.dart';

// ── Прототип «Страницы» ──────────────────────────────────────────────────────
// Нижний экран разложен на вертикальные страницы, как лента коротких видео:
// Таймер ↓ Намазы ↓ Дела ↓ Постоянство. Одна страница — одна тема. Все
// страницы живут на том же контроллере свайпа, что и переход к таймеру, —
// одинаковая физика и мягкий хаптик на каждой странице. Включается в
// «Оформлении» (нижний экран → страницы). Классический вид не меняется.

const _pagesWeekdaysRu = [
  'Понедельник',
  'Вторник',
  'Среда',
  'Четверг',
  'Пятница',
  'Суббота',
  'Воскресенье',
];
const _pagesWeekdaysKz = [
  'Дүйсенбі',
  'Сейсенбі',
  'Сәрсенбі',
  'Бейсенбі',
  'Жұма',
  'Сенбі',
  'Жексенбі',
];

/// «Четверг, 23 июля · 9 сафар» — обе даты сразу.
String _pagesDateLine(S s, DateTime now) {
  final kz = s == S.kz;
  final weekday = (kz ? _pagesWeekdaysKz : _pagesWeekdaysRu)[now.weekday - 1];
  final month = (kz ? _gregMonthsKz : _gregMonthsRu)[now.month - 1];
  final hijri = HijriCalendar.fromDate(now);
  final hMonth = (kz ? s.hijriMonths : _hijriMonthsRu)[hijri.hMonth - 1];
  return '$weekday, ${now.day} $month · ${hijri.hDay} $hMonth';
}

String _pagesHhmm(int minutes) {
  final m = minutes % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

/// «через 1 ч 26 мин» — без секунд: посекундный таймер живёт на главном.
String _pagesCountdown(S s, int seconds) {
  final minutes = (seconds.clamp(0, 86400) / 60).ceil();
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (s == S.kz) {
    if (h == 0) return '$m мин кейін';
    return m == 0 ? '$h сағ кейін' : '$h сағ $m мин кейін';
  }
  if (h == 0) return 'через $m мин';
  return m == 0 ? 'через $h ч' : 'через $h ч $m мин';
}

class _PagesDayLayer extends StatelessWidget {
  const _PagesDayLayer({
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
    required this.onGoTo,
  });

  /// Сырой прогресс ленты: 0 — таймер, 1 — Намазы, 2 — Дела, 3 — Постоянство.
  final double p, h;
  final S s;
  final DaySurfacePalette palette;
  final AppState app;
  final DayTimes t;
  final int nowMin, nowSec;
  final ScheduleService schedule;
  final void Function(String) onReader;
  final void Function(double) onGoTo;

  @override
  Widget build(BuildContext context) {
    final c = palette.colors;
    final kz = s == S.kz;
    final pages = <Widget Function()>[
      () => _PrayersPage(
        s: s,
        c: c,
        palette: palette,
        app: app,
        t: t,
        nowSec: nowSec,
        now: schedule.now(),
        onNext: () => onGoTo(2),
      ),
      () => _DeedsPage(
        s: s,
        c: c,
        palette: palette,
        app: app,
        t: t,
        nowMin: nowMin,
        onReader: onReader,
        onNext: () => onGoTo(3),
      ),
      () => _ConsistencyPage(
        s: s,
        c: c,
        palette: palette,
        app: app,
        now: schedule.now(),
        onTop: () => onGoTo(0),
      ),
    ];

    return Stack(
      children: [
        for (var i = 0; i < pages.length; i++)
          Builder(
            builder: (context) {
              final index = i + 1;
              final distance = index - p;
              // Страницы дальше соседней не строим вовсе.
              if (distance.abs() >= 1.0) return const SizedBox.shrink();
              // Первая страница проявляется так же, как прежний экран дня;
              // между страницами — лёгкое затухание уходящей, как в ленте.
              final enter = index == 1 && p < 1
                  ? const Interval(
                      0.14,
                      1.0,
                      curve: Curves.easeOutCubic,
                    ).transform(p.clamp(0.0, 1.0))
                  : 1.0;
              final leave = distance < 0
                  ? (1 + distance * 1.25).clamp(0.0, 1.0)
                  : 1.0;
              return Positioned.fill(
                child: Transform.translate(
                  offset: Offset(0, h * distance),
                  child: Opacity(
                    opacity: (enter * leave).clamp(0.0, 1.0),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 10, 30, 10),
                        child: pages[i](),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        if (p > 0.5)
          Positioned(
            right: 9,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: ((p - 0.5) * 2).clamp(0.0, 1.0),
                child: Center(
                  child: _PageDots(
                    progress: p,
                    color: c.ink,
                    labels: [
                      kz ? 'Таймер' : 'Таймер',
                      kz ? 'Намаздар' : 'Намазы',
                      kz ? 'Істер' : 'Дела',
                      kz ? 'Тұрақтылық' : 'Постоянство',
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Индикатор страниц у правого края: активная точка вытягивается плавно
/// вместе с пальцем, а не прыгает — чтобы листание было приятно смотреть.
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.progress,
    required this.color,
    required this.labels,
  });

  final double progress;
  final Color color;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: labels[progress.round().clamp(0, labels.length - 1)],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            Builder(
              builder: (context) {
                final near = (1 - (progress - i).abs()).clamp(0.0, 1.0);
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  width: 4,
                  height: 5 + 13 * near,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.22 + 0.6 * near),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Подсказка внизу страницы: что будет дальше. Нажимается.
class _NextHint extends StatelessWidget {
  const _NextHint({required this.label, required this.c, required this.onTap});

  final String label;
  final JColors c;
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
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: JType.ui(13, w: FontWeight.w600, color: c.sub),
              ),
              const SizedBox(height: 2),
              Icon(CupertinoIcons.chevron_down, size: 15, color: c.sub),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, required this.c});

  final String title;
  final JColors c;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: JType.ui(30, w: FontWeight.w700, color: c.ink),
    );
  }
}

/// Контент страницы по вертикали: сверху заголовок, внизу подсказка.
/// Экран не прокручивается (свайп принадлежит ленте страниц), поэтому
/// при нехватке места содержимое аккуратно ужимается, а не обрезается.
class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.header, required this.body, this.footer});

  final Widget header, body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 18),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => FittedBox(
              fit: BoxFit.scaleDown,
              // Чуть выше центра: страница читается как спокойная карточка,
              // а не как список, прилипший к заголовку.
              alignment: const Alignment(0, -0.3),
              child: SizedBox(width: box.maxWidth, child: body),
            ),
          ),
        ),
        ?footer,
      ],
    );
  }
}

// ── Страница 1: Намазы ──────────────────────────────────────────────────────

class _PrayersPage extends StatelessWidget {
  const _PrayersPage({
    required this.s,
    required this.c,
    required this.palette,
    required this.app,
    required this.t,
    required this.nowSec,
    required this.now,
    required this.onNext,
  });

  final S s;
  final JColors c;
  final DaySurfacePalette palette;
  final AppState app;
  final DayTimes t;
  final int nowSec;
  final DateTime now;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final kz = s == S.kz;
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

    return _PageFrame(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _pagesDateLine(s, now),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JType.ui(13, color: c.sub),
                ),
              ),
              const SizedBox(width: 8),
              _CityPill(app: app, c: c, kz: kz),
            ],
          ),
          const SizedBox(height: 6),
          _PageTitle(title: kz ? 'Намаздар' : 'Намазы', c: c),
        ],
      ),
      body: _SurfaceCard(
        palette: palette,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          children: [
            for (final (i, prayer) in Prayer.values.indexed)
              _BigPrayerRow(
                name: s.prayers[i],
                time: t.fmt(prayer),
                isSunrise: prayer == Prayer.sunrise,
                isNext: prayer == next,
                isPast: t.times[prayer]! * 60 <= nowSec && prayer != next,
                countdown: prayer == next
                    ? _pagesCountdown(s, targetSec - nowSec)
                    : null,
                c: c,
                onTap: () =>
                    _showQuickSettings(context, prayer.name, s.prayers[i], c),
              ),
          ],
        ),
      ),
      footer: _NextHint(
        label: kz ? 'Бүгінгі істер' : 'Дела сегодня',
        c: c,
        onTap: onNext,
      ),
    );
  }
}

class _CityPill extends StatelessWidget {
  const _CityPill({required this.app, required this.c, required this.kz});

  final AppState app;
  final JColors c;
  final bool kz;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: kz ? 'Қаланы өзгерту' : 'Сменить город',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          CityPicker.open(context);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: c.ink.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.location_solid, size: 12, color: c.sub),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  app.city.displayName(app.lang),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JType.ui(12.5, w: FontWeight.w600, color: c.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigPrayerRow extends StatelessWidget {
  const _BigPrayerRow({
    required this.name,
    required this.time,
    required this.isSunrise,
    required this.isNext,
    required this.isPast,
    required this.countdown,
    required this.c,
    required this.onTap,
  });

  final String name, time;
  final String? countdown;
  final bool isSunrise, isNext, isPast;
  final JColors c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Восход — граница времени Фаджра, а не намаз: мельче и тише.
    final color = isNext ? c.gold : (isPast || isSunrise ? c.sub : c.ink);
    final size = isSunrise ? 15.0 : (isNext ? 25.0 : 21.0);
    final weight = isNext
        ? FontWeight.w700
        : (isSunrise ? FontWeight.w400 : FontWeight.w500);
    final timeStyle = JType.ui(
      size,
      w: weight,
      color: color,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    return _ScalePressed(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: isSunrise ? 42 : 62),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isNext ? c.gold.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JType.ui(size, w: weight, color: color),
                  ),
                  if (countdown != null)
                    Text(
                      countdown!,
                      style: JType.ui(
                        13,
                        w: FontWeight.w600,
                        color: c.gold.withValues(alpha: 0.9),
                      ),
                    ),
                ],
              ),
            ),
            Text(time, style: timeStyle),
          ],
        ),
      ),
    );
  }
}

// ── Страница 2: Дела ────────────────────────────────────────────────────────

enum _DeedState { upcoming, open, done, passed }

class _Deed {
  const _Deed({
    required this.id,
    required this.label,
    required this.minute,
    required this.end,
    required this.readable,
    required this.onTap,
  });

  final String id, label;
  final int minute, end;

  /// Открывает чтение (зикры, аль-Кахф); иначе — просто отметка.
  final bool readable;
  final VoidCallback onTap;
}

class _DeedsPage extends StatelessWidget {
  const _DeedsPage({
    required this.s,
    required this.c,
    required this.palette,
    required this.app,
    required this.t,
    required this.nowMin,
    required this.onReader,
    required this.onNext,
  });

  final S s;
  final JColors c;
  final DaySurfacePalette palette;
  final AppState app;
  final DayTimes t;
  final int nowMin;
  final void Function(String) onReader;
  final VoidCallback onNext;

  List<_Deed> _deeds() {
    final deeds = <_Deed>[];
    for (final w in windowsFor(t)) {
      final (label, readable) = switch (w.id) {
        TaskId.morning => (s.morningTitle, true),
        TaskId.kahf => (s.kahfTitle, true),
        TaskId.evening => (s.eveningTitle, true),
        TaskId.dua => (s.duaTitle, false),
      };
      final id = w.id.name;
      deeds.add(
        _Deed(
          id: id,
          label: label,
          minute: w.start,
          end: w.end,
          readable: readable,
          onTap: readable ? () => onReader(id) : () => app.markDone(id),
        ),
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
      deeds.add(
        _Deed(
          id: id,
          label: reminder.title,
          minute: minute,
          end: minute + taskRailGraceMinutes,
          readable: false,
          onTap: () => app.markDone(id),
        ),
      );
    }
    deeds.sort((a, b) => a.minute.compareTo(b.minute));
    return deeds;
  }

  _DeedState _stateOf(_Deed deed) {
    if (app.isDone(deed.id)) return _DeedState.done;
    if (nowMin >= deed.minute && nowMin < deed.end) return _DeedState.open;
    if (nowMin >= deed.end) return _DeedState.passed;
    return _DeedState.upcoming;
  }

  @override
  Widget build(BuildContext context) {
    final kz = s == S.kz;
    final deeds = _deeds();
    return _PageFrame(
      header: _PageTitle(title: kz ? 'Бүгінгі істер' : 'Дела сегодня', c: c),
      body: Column(
        children: [
          for (final deed in deeds) ...[
            _DeedCard(
              deed: deed,
              state: _stateOf(deed),
              s: s,
              c: c,
              palette: palette,
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                RemindersScreen.open(context);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.bell, size: 16, color: c.sub),
                    const SizedBox(width: 6),
                    Text(
                      kz ? 'Еске салуларды баптау' : 'Настроить напоминания',
                      style: JType.ui(14, w: FontWeight.w600, color: c.sub),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      footer: _NextHint(
        label: _sentenceCase(s.notebookTitle),
        c: c,
        onTap: onNext,
      ),
    );
  }
}

class _DeedCard extends StatelessWidget {
  const _DeedCard({
    required this.deed,
    required this.state,
    required this.s,
    required this.c,
    required this.palette,
  });

  final _Deed deed;
  final _DeedState state;
  final S s;
  final JColors c;
  final DaySurfacePalette palette;

  @override
  Widget build(BuildContext context) {
    final kz = s == S.kz;
    final done = state == _DeedState.done;
    final open = state == _DeedState.open;
    final passed = state == _DeedState.passed;
    final until = kz
        ? '${_pagesHhmm(deed.end)} дейін'
        : 'до ${_pagesHhmm(deed.end)}';
    final window = deed.id.startsWith('custom:')
        ? _pagesHhmm(deed.minute)
        : deed.id == 'dua'
        ? '${_pagesHhmm(deed.minute)}–${_pagesHhmm(deed.end)}'
        : until;
    final hint = switch (state) {
      _DeedState.done => kz ? 'Орындалды' : 'Выполнено',
      _DeedState.open => kz ? 'Қазір · $window' : 'Сейчас · $window',
      // У часа дуа и своих напоминаний время уже в окне — без повтора.
      _DeedState.upcoming
          when deed.id == 'dua' || deed.id.startsWith('custom:') =>
        window,
      _DeedState.upcoming =>
        kz
            ? '${_pagesHhmm(deed.minute)} бастап · $window'
            : 'С ${_pagesHhmm(deed.minute)} · $window',
      _DeedState.passed => window,
    };
    final action = done
        ? null
        : deed.readable
        ? (kz ? 'Оқу' : 'Читать')
        : (kz ? 'Белгілеу' : 'Отметить');

    return Semantics(
      button: !done,
      checked: done,
      label: deed.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: done
            ? null
            : () {
                HapticFeedback.selectionClick();
                deed.onTap();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: open
                ? c.gold.withValues(alpha: palette.isLight ? 0.12 : 0.16)
                : c.ink.withValues(alpha: palette.isLight ? 0.05 : 0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: open ? c.gold.withValues(alpha: 0.55) : c.hair,
              width: open ? 1.2 : 0.8,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? c.green : Colors.transparent,
                  border: done
                      ? null
                      : Border.all(
                          color: open ? c.gold : c.hair,
                          width: open ? 1.8 : 1.3,
                        ),
                ),
                child: done
                    ? const Icon(
                        CupertinoIcons.check_mark,
                        size: 16,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deed.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: JType.ui(
                        17,
                        w: FontWeight.w700,
                        color: done || passed ? c.sub : c.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: JType.ui(
                        13,
                        w: open ? FontWeight.w600 : FontWeight.w400,
                        color: open ? c.gold : c.sub,
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null && !passed) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: open ? c.gold : c.ink.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    action,
                    style: JType.ui(
                      13,
                      w: FontWeight.w700,
                      color: open
                          ? (palette.isLight ? Colors.white : c.bg)
                          : c.ink,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Страница 3: Постоянство ─────────────────────────────────────────────────

class _ConsistencyPage extends StatelessWidget {
  const _ConsistencyPage({
    required this.s,
    required this.c,
    required this.palette,
    required this.app,
    required this.now,
    required this.onTop,
  });

  final S s;
  final JColors c;
  final DaySurfacePalette palette;
  final AppState app;
  final DateTime now;
  final VoidCallback onTop;

  @override
  Widget build(BuildContext context) {
    final kz = s == S.kz;
    return _PageFrame(
      header: _PageTitle(title: _sentenceCase(s.notebookTitle), c: c),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Хадис о постоянстве — тот же утверждённый текст, что в онбординге.
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.posterQuote,
                  style: JType.ui(
                    16,
                    color: c.ink,
                    h: 1.4,
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 6),
                Text(s.posterSrc, style: JType.ui(12, color: c.sub)),
              ],
            ),
          ),
          _SurfaceCard(
            palette: palette,
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _monthYearLabel(s, now),
                        style: JType.ui(15, w: FontWeight.w700, color: c.ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _Notebook(
                  c: c,
                  app: app,
                  now: now,
                  since: app.firstUseDate,
                  onDayTap: (date) => _showDayDetailsSheet(
                    context,
                    date: date,
                    s: s,
                    app: app,
                    palette: palette,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _PagesButton(
                  icon: CupertinoIcons.bell,
                  label: s.remindersBtn,
                  c: c,
                  onTap: () => RemindersScreen.open(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PagesButton(
                  icon: CupertinoIcons.gear,
                  label: kz ? 'Баптаулар' : 'Настройки',
                  c: c,
                  onTap: () => _showPagesSettings(context),
                ),
              ),
            ],
          ),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onTop();
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.chevron_up, size: 14, color: c.sub),
                    const SizedBox(width: 4),
                    Text(
                      kz ? 'Таймерге' : 'К таймеру',
                      style: JType.ui(13, w: FontWeight.w600, color: c.sub),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PagesButton extends StatelessWidget {
  const _PagesButton({
    required this.icon,
    required this.label,
    required this.c,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final JColors c;
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
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: c.ink.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: c.hair, width: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: c.ink),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JType.ui(14, w: FontWeight.w700, color: c.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Единое место настроек вместо разбросанных тапов по городу и дате.
void _showPagesSettings(BuildContext context) {
  DauamSettingsSheet.open<void>(
    context,
    heightFactor: .62,
    builder: (_) => _PagesSettingsPage(outer: context),
  );
}

class _PagesSettingsPage extends StatelessWidget {
  const _PagesSettingsPage({required this.outer});

  /// Контекст экрана: из него открываются вложенные листы после закрытия
  /// настроек, чтобы не складывать листы друг на друга.
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
          ],
        ),
      ),
    );
  }
}
