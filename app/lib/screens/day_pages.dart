part of 'home.dart';

// ── Прототип «Страницы» ──────────────────────────────────────────────────────
// Нижний экран — вертикальные страницы: Кибла ↑ Таймер ↓ Сегодня ↓ Постоянство.
//
// «Сегодня» — два отдельных блока: времена намазов и дела. Их не смешиваем в
// одну ленту (прошлый прототип показал, что так теряются оба), но держим на
// одной странице, чтобы она была наполненной.
//
// Переход — не слайд фотографии, а хореография: каждый элемент уходит и
// появляется со своей задержкой и со своего направления, фон движется
// медленнее контента. Всё вычисляется из положения пальца, поэтому переход
// можно «перематывать», а доводка после свайпа идёт неспешно — постановку
// видно и при обычном быстром свайпе. Когда элемент встаёт на место, Taptic
// Engine даёт короткий щелчок.
//
// Включается в «Оформлении» (нижний экран → страницы). Классический вид не
// меняется.

String _pagesHhmm(int minutes) {
  final m = minutes % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

/// «1 ч 26 мин» — без секунд: посекундный таймер живёт на главном.
String _pagesDuration(S s, int minutes) {
  final safe = minutes.clamp(0, 1440);
  final h = safe ~/ 60;
  final m = safe % 60;
  if (s == S.kz) {
    if (h == 0) return '$m мин';
    return m == 0 ? '$h сағ' : '$h сағ $m мин';
  }
  if (h == 0) return '$m мин';
  return m == 0 ? '$h ч' : '$h ч $m мин';
}

double _seg(double v, double start, double end) =>
    ((v - start) / (end - start)).clamp(0.0, 1.0);

/// Доля свайпа, после которой начинает входить страница. С таймера — позже:
/// сначала по очереди уходят подпись, таймер и кнопки главного экрана.
double _enterStart(int page) => page == 1 ? 0.5 : 0.35;

// ── Хореография ─────────────────────────────────────────────────────────────

/// Моменты (в долях входа страницы), когда элементы «встают на место».
/// По ним же звучит Taptic Engine — вибрация совпадает с движением.
const _todayBeats = [0.40, 0.46, 0.52, 0.58, 0.64, 0.70, 0.80, 0.86, 0.92];
const _consistencyBeats = [0.40, 0.62, 0.80];

/// Один элемент страницы в хореографии перехода.
///
/// [enter] — насколько страница вошла (0…1), [leave] — насколько ушла вверх.
/// Элемент появляется в окне [at]…[at]+[span], прилетая со смещения [from];
/// уходит — всплывая вверх и растворяясь, чуть раньше или позже соседей.
class _Beat extends StatelessWidget {
  const _Beat({
    required this.enter,
    required this.leave,
    required this.at,
    required this.child,
    this.span = 0.3,
    this.from = const Offset(0, 26),
    this.leaveAt = 0.0,
  });

  final double enter, leave, at, span, leaveAt;
  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final i = Curves.easeOutCubic.transform(_seg(enter, at, at + span));
    // Уход быстрее входа: к моменту, когда начинает входить следующая
    // страница, прежние элементы уже растворились.
    final o = Curves.easeIn.transform(_seg(leave, leaveAt, leaveAt + 0.3));
    final opacity = (i * (1 - o)).clamp(0.0, 1.0);
    final scale = (0.94 + 0.06 * i) * (1 - 0.06 * o);
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(from.dx * (1 - i), from.dy * (1 - i) - 46 * o),
        child: Transform.scale(scale: scale, child: child),
      ),
    );
  }
}

/// Уход элемента главного экрана при свайпе к страницам: каждый элемент —
/// в свою сторону и в своё время, а не весь экран одной картинкой.
class _Leave extends StatelessWidget {
  const _Leave({
    required this.p,
    required this.start,
    required this.child,
    this.span = 0.3,
    this.to = const Offset(0, -40),
    this.scaleTo = 0.94,
  });

  final double p, start, span, scaleTo;
  final Offset to;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final o = Curves.easeInCubic.transform(_seg(p, start, start + span));
    if (o <= 0) return child;
    return Opacity(
      opacity: (1 - o).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: to * o,
        child: Transform.scale(scale: 1 + (scaleTo - 1) * o, child: child),
      ),
    );
  }
}

class _PagesDayLayer extends StatefulWidget {
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

  /// Сырой прогресс ленты: 0 — таймер, 1 — Сегодня, 2 — Постоянство.
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
  State<_PagesDayLayer> createState() => _PagesDayLayerState();
}

class _PagesDayLayerState extends State<_PagesDayLayer> {
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  /// Все моменты «элемент встал на место» в координатах ленты.
  static final List<double> _beats = [
    for (final (page, beats) in const [
      (1, _todayBeats),
      (2, _consistencyBeats),
    ])
      for (final b in beats)
        page - 1 + _enterStart(page) + b * (1 - _enterStart(page)),
  ];

  @override
  void didUpdateWidget(_PagesDayLayer old) {
    super.didUpdateWidget(old);
    final from = old.p, to = widget.p;
    if (from == to) return;
    final lo = math.min(from, to), hi = math.max(from, to);
    if (!_beats.any((b) => b > lo && b <= hi)) return;
    // Не чаще раза в 45 мс: при быстром свайпе — мягкий каскад,
    // при медленном — отдельные щелчки, как у застёжки-молнии.
    final now = DateTime.now();
    if (now.difference(_lastTick).inMilliseconds < 45) return;
    _lastTick = now;
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final c = w.palette.colors;

    Widget page(int index, Widget Function(double enter, double leave) build) {
      final d = index - w.p;
      if (d.abs() >= 1.0) return const SizedBox.shrink();
      final enter = d > 0 ? _seg(1 - d, _enterStart(index), 1.0) : 1.0;
      final leave = d < 0 ? (-d).clamp(0.0, 1.0) : 0.0;
      return Positioned.fill(
        // Сама страница едет лишь чуть-чуть — основное движение делают
        // её элементы, каждый по-своему.
        child: Transform.translate(
          offset: Offset(0, w.h * d * 0.10),
          child: IgnorePointer(
            ignoring: d.abs() > 0.5,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 30, 6),
                child: build(enter, leave),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Сплошной фон страниц закрывает картину главного экрана целиком:
        // иначе сверху оставался «хвост» Мекки или пейзажа.
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: _seg(w.p, 0.3, 0.85),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [w.palette.top, w.palette.middle, w.palette.bottom],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: _PagesAmbience(p: w.p, c: c, isLight: w.palette.isLight),
          ),
        ),
        page(
          1,
          (enter, leave) => _TodayPage(
            enter: enter,
            leave: leave,
            s: w.s,
            c: c,
            palette: w.palette,
            app: w.app,
            t: w.t,
            nowMin: w.nowMin,
            nowSec: w.nowSec,
            onReader: w.onReader,
            onNext: () => w.onGoTo(2),
          ),
        ),
        page(
          2,
          (enter, leave) => _ConsistencyPage(
            enter: enter,
            leave: leave,
            s: w.s,
            c: c,
            palette: w.palette,
            app: w.app,
            now: w.schedule.now(),
          ),
        ),
      ],
    );
  }
}

/// Фон страниц: тонкий узор восьмиконечных звёзд и мягкое золотое свечение.
/// Узор движется медленнее контента — отсюда ощущение глубины.
class _PagesAmbience extends StatelessWidget {
  const _PagesAmbience({
    required this.p,
    required this.c,
    required this.isLight,
  });

  final double p;
  final JColors c;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _seg(p, 0.3, 1.0),
      child: CustomPaint(
        painter: _AmbiencePainter(
          p: p,
          line: c.ink.withValues(alpha: isLight ? 0.045 : 0.05),
          glow: c.gold.withValues(alpha: isLight ? 0.10 : 0.13),
        ),
      ),
    );
  }
}

class _AmbiencePainter extends CustomPainter {
  _AmbiencePainter({required this.p, required this.line, required this.glow});

  final double p;
  final Color line, glow;

  @override
  void paint(Canvas canvas, Size size) {
    // Свечение плывёт между главными местами страниц: над следующим
    // намазом и над хадисом.
    final k = (p - 1).clamp(0.0, 1.0);
    final y = size.height * (0.28 + (0.24 - 0.28) * k);
    final x = size.width * (0.5 + 0.18 * math.sin(p * 1.9));
    final r = size.width * 0.78;
    canvas.drawCircle(
      Offset(x, y),
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [glow, glow.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: Offset(x, y), radius: r)),
    );

    // Узор: сетка восьмиконечных звёзд, параллакс 0.35 от контента.
    final step = size.width / 4;
    final radius = step * 0.28;
    final rowStep = step * 0.9;
    final shift = -(p * size.height * 0.35) % rowStep;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = line;
    for (var row = -1; row * rowStep < size.height + step; row++) {
      final cy = row * rowStep + shift;
      final offset = row.isOdd ? step / 2 : 0.0;
      for (var i = -1; i <= 4; i++) {
        final center = Offset(i * step + offset, cy);
        for (final turn in const [0.0, math.pi / 4]) {
          final path = Path();
          for (var v = 0; v < 4; v++) {
            final a = turn + v * math.pi / 2;
            final pt = center + Offset(math.cos(a), math.sin(a)) * radius;
            v == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
          }
          canvas.drawPath(path..close(), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_AmbiencePainter o) =>
      o.p != p || o.line != line || o.glow != glow;
}

/// Индикатор страниц у правого края — на всех экранах ленты, от Киблы до
/// Постоянства. Активная точка вытягивается плавно вместе с пальцем.
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.progress,
    required this.color,
    required this.labels,
  });

  /// 0 — Кибла, 1 — Таймер, 2 — Сегодня, 3 — Постоянство.
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
                final eased = Curves.easeOut.transform(near);
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  width: 4,
                  height: 5 + 13 * eased,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.25 + 0.6 * eased),
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

/// Маленькая золотая подпись в разрядку — как «ДО АСРА» на главном экране.
class _PageCaption extends StatelessWidget {
  const _PageCaption(this.text, {required this.c});

  final String text;
  final JColors c;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: JType.caption(c.gold, size: 11.5),
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: JType.ui(12.5, w: FontWeight.w600, color: c.sub),
              ),
              Icon(CupertinoIcons.chevron_down, size: 14, color: c.sub),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Страница 1: Сегодня ─────────────────────────────────────────────────────

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

  bool get isCustom => id.startsWith('custom:');
}

class _TodayPage extends StatelessWidget {
  const _TodayPage({
    required this.enter,
    required this.leave,
    required this.s,
    required this.c,
    required this.palette,
    required this.app,
    required this.t,
    required this.nowMin,
    required this.nowSec,
    required this.onReader,
    required this.onNext,
  });

  final double enter, leave;
  final S s;
  final JColors c;
  final DaySurfacePalette palette;
  final AppState app;
  final DayTimes t;
  final int nowMin, nowSec;
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
    final left = _pagesDuration(s, ((targetSec - nowSec) / 60).ceil());

    final deeds = _deeds();
    // Главное дело — открытое сейчас, иначе ближайшее следующее. Если на
    // сегодня таких нет, остаётся просто список — без лишних объявлений.
    _Deed? hero;
    for (final state in const [_DeedState.open, _DeedState.upcoming]) {
      for (final deed in deeds) {
        if (_stateOf(deed) == state) {
          hero = deed;
          break;
        }
      }
      if (hero != null) break;
    }
    final others = [
      for (final d in deeds)
        if (d != hero) d,
    ];

    return LayoutBuilder(
      builder: (context, box) {
        // На маленьких экранах (iPhone SE) — плотнее, чтобы всё поместилось
        // без прокрутки: свайп принадлежит ленте страниц.
        final dense = box.maxHeight < 640;
        final maxRows = dense ? 3 : 4;
        final shown = others.take(maxRows).toList();
        final hidden = others.length - shown.length;

        final body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Beat(
              enter: enter,
              leave: leave,
              at: 0.0,
              from: const Offset(-18, 0),
              child: _PageCaption(
                kz ? 'Намаз уақыттары' : 'Время намазов',
                c: c,
              ),
            ),
            _Beat(
              enter: enter,
              leave: leave,
              at: 0.04,
              from: const Offset(0, 30),
              leaveAt: 0.04,
              child: _SurfaceCard(
                palette: palette,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Column(
                  children: [
                    for (final (i, prayer) in Prayer.values.indexed)
                      _Beat(
                        enter: enter,
                        leave: leave,
                        at: _todayBeats[i] - 0.3,
                        // Строки прилетают попеременно слева и справа и
                        // сходятся в один столбец.
                        from: Offset(i.isEven ? -34 : 34, 8),
                        leaveAt: 0.012 * i,
                        child: _PrayerRow(
                          name: s.prayers[i],
                          time: t.fmt(prayer),
                          isSunrise: prayer == Prayer.sunrise,
                          isNext: prayer == next,
                          isPast:
                              t.times[prayer]! * 60 <= nowSec && prayer != next,
                          left: prayer == next
                              ? (kz ? '$left кейін' : 'через $left')
                              : null,
                          dense: dense,
                          c: c,
                          onTap: () => _showQuickSettings(
                            context,
                            prayer.name,
                            s.prayers[i],
                            c,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: dense ? 14 : 22),
            _Beat(
              enter: enter,
              leave: leave,
              at: 0.34,
              from: const Offset(-18, 0),
              leaveAt: 0.06,
              child: _PageCaption(kz ? 'Бүгінгі істер' : 'Дела сегодня', c: c),
            ),
            if (hero != null)
              _Beat(
                enter: enter,
                leave: leave,
                at: _todayBeats[6] - 0.32,
                span: 0.32,
                from: const Offset(0, 44),
                leaveAt: 0.07,
                child: _HeroDeed(
                  deed: hero,
                  state: _stateOf(hero),
                  nowMin: nowMin,
                  dense: dense,
                  s: s,
                  c: c,
                  palette: palette,
                ),
              ),
            if (hero != null && shown.isNotEmpty) const SizedBox(height: 10),
            if (shown.isNotEmpty)
              _Beat(
                enter: enter,
                leave: leave,
                at: 0.5,
                from: const Offset(0, 30),
                leaveAt: 0.08,
                child: _SurfaceCard(
                  palette: palette,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Column(
                    children: [
                      for (final (i, deed) in shown.indexed)
                        _Beat(
                          enter: enter,
                          leave: leave,
                          at:
                              _todayBeats[math.min(
                                7 + i,
                                _todayBeats.length - 1,
                              )] -
                              0.3,
                          from: Offset(i.isEven ? 30 : -30, 8),
                          leaveAt: 0.08 + 0.012 * i,
                          child: _DeedRow(
                            deed: deed,
                            state: _stateOf(deed),
                            s: s,
                            c: c,
                          ),
                        ),
                      if (hidden > 0)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => RemindersScreen.open(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Text(
                              kz ? 'Тағы $hidden' : 'Ещё $hidden',
                              textAlign: TextAlign.center,
                              style: JType.ui(
                                13,
                                w: FontWeight.w600,
                                color: c.sub,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            // На маленьком экране ссылка уступает место: кнопка «Напоминания»
            // есть и на странице постоянства.
            if (!dense)
              _Beat(
                enter: enter,
                leave: leave,
                at: 0.66,
                leaveAt: 0.1,
                child: Semantics(
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
                          Icon(CupertinoIcons.bell, size: 14, color: c.sub),
                          const SizedBox(width: 6),
                          Text(
                            kz
                                ? 'Еске салуларды баптау'
                                : 'Настроить напоминания',
                            style: JType.ui(
                              13,
                              w: FontWeight.w600,
                              color: c.sub,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
        // Содержимое по центру; если не помещается (маленький экран, много
        // своих напоминаний) — ужимается целиком, а не обрезается.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, inner) => FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(width: inner.maxWidth, child: body),
                ),
              ),
            ),
            _Beat(
              enter: enter,
              leave: leave,
              at: 0.7,
              from: const Offset(0, 10),
              child: _NextHint(
                label: _sentenceCase(s.notebookTitle),
                c: c,
                onTap: onNext,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PrayerRow extends StatelessWidget {
  const _PrayerRow({
    required this.name,
    required this.time,
    required this.isSunrise,
    required this.isNext,
    required this.isPast,
    required this.left,
    required this.dense,
    required this.c,
    required this.onTap,
  });

  final String name, time;
  final String? left;
  final bool isSunrise, isNext, isPast, dense;
  final JColors c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Восход — граница времени Фаджра, а не намаз: мельче и тише.
    final color = isNext ? c.gold : (isPast || isSunrise ? c.sub : c.ink);
    final size = isSunrise ? 13.0 : 16.0;
    final weight = isNext
        ? FontWeight.w700
        : (isSunrise ? FontWeight.w400 : FontWeight.w500);
    return _ScalePressed(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(
          minHeight: isSunrise ? (dense ? 28 : 32) : (dense ? 40 : 44),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isNext ? c.gold.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JType.ui(size, w: weight, color: color),
              ),
            ),
            if (left != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  left!,
                  style: JType.ui(
                    12,
                    w: FontWeight.w600,
                    color: c.gold.withValues(alpha: 0.9),
                  ),
                ),
              ),
            Text(
              time,
              style: JType.ui(
                size,
                w: weight,
                color: color,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Главная карточка дел: что сделать сейчас или следующим.
class _HeroDeed extends StatelessWidget {
  const _HeroDeed({
    required this.deed,
    required this.state,
    required this.nowMin,
    required this.dense,
    required this.s,
    required this.c,
    required this.palette,
  });

  final _Deed deed;
  final _DeedState state;
  final int nowMin;
  final bool dense;
  final S s;
  final JColors c;
  final DaySurfacePalette palette;

  @override
  Widget build(BuildContext context) {
    final kz = s == S.kz;
    final open = state == _DeedState.open;
    final caption = open
        ? (kz ? 'Қазір' : 'Сейчас')
        : (kz ? 'Келесі' : 'Далее');
    final String detail;
    if (deed.isCustom) {
      detail = kz
          ? '${_pagesHhmm(deed.minute)} уақыты'
          : 'В ${_pagesHhmm(deed.minute)}';
    } else if (open) {
      final left = _pagesDuration(s, deed.end - nowMin);
      detail = kz
          ? '$left қалды · ${_pagesHhmm(deed.end)} дейін'
          : 'Осталось $left · до ${_pagesHhmm(deed.end)}';
    } else {
      detail = kz
          ? '${_pagesHhmm(deed.minute)}–${_pagesHhmm(deed.end)}'
          : 'С ${_pagesHhmm(deed.minute)} до ${_pagesHhmm(deed.end)}';
    }
    final windowFrac = deed.end > deed.minute
        ? ((nowMin - deed.minute) / (deed.end - deed.minute)).clamp(0.0, 1.0)
        : 0.0;
    final action = deed.readable
        ? (kz ? 'Оқу' : 'Читать')
        : (kz ? 'Белгілеу' : 'Отметить');

    return Semantics(
      button: true,
      label: '$caption. ${deed.label}. $detail',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.mediumImpact();
          deed.onTap();
        },
        child: Container(
          padding: EdgeInsets.fromLTRB(
            18,
            dense ? 12 : 14,
            14,
            dense ? 12 : 14,
          ),
          decoration: BoxDecoration(
            color: open
                ? c.gold.withValues(alpha: palette.isLight ? 0.13 : 0.12)
                : c.ink.withValues(alpha: palette.isLight ? 0.06 : 0.07),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: open ? c.gold.withValues(alpha: 0.5) : c.hair,
              width: open ? 1.1 : 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                caption.toUpperCase(),
                style: JType.caption(open ? c.gold : c.sub, size: 10.5),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deed.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: JType.ui(17, w: FontWeight.w700, color: c.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: JType.ui(12.5, color: open ? c.gold : c.sub),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: open ? c.gold : c.ink.withValues(alpha: 0.10),
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
              ),
              if (open && !deed.isCustom && !dense) ...[
                const SizedBox(height: 12),
                // Сколько времени окна уже прошло — справка, не оценка.
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 3,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ColoredBox(
                            color: c.gold.withValues(alpha: 0.18),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: windowFrac,
                          child: ColoredBox(color: c.gold),
                        ),
                      ],
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

class _DeedRow extends StatelessWidget {
  const _DeedRow({
    required this.deed,
    required this.state,
    required this.s,
    required this.c,
  });

  final _Deed deed;
  final _DeedState state;
  final S s;
  final JColors c;

  @override
  Widget build(BuildContext context) {
    final kz = s == S.kz;
    final done = state == _DeedState.done;
    final passed = state == _DeedState.passed;
    final hint = done
        ? (kz ? 'орындалды' : 'выполнено')
        : deed.isCustom
        ? _pagesHhmm(deed.minute)
        : deed.id == 'dua'
        ? '${_pagesHhmm(deed.minute)}–${_pagesHhmm(deed.end)}'
        : (kz ? '${_pagesHhmm(deed.end)} дейін' : 'до ${_pagesHhmm(deed.end)}');
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
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
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    deed.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JType.ui(
                      15,
                      w: FontWeight.w600,
                      color: done || passed ? c.sub : c.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(hint, style: JType.ui(12.5, color: c.sub)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Страница 2: Постоянство ─────────────────────────────────────────────────

class _ConsistencyPage extends StatelessWidget {
  const _ConsistencyPage({
    required this.enter,
    required this.leave,
    required this.s,
    required this.c,
    required this.palette,
    required this.app,
    required this.now,
  });

  final double enter, leave;
  final S s;
  final JColors c;
  final DaySurfacePalette palette;
  final AppState app;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final kz = s == S.kz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        // Хадис о постоянстве — тот же утверждённый текст, что в онбординге.
        _Beat(
          enter: enter,
          leave: leave,
          at: _consistencyBeats[0] - 0.34,
          span: 0.4,
          from: const Offset(0, 18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.posterQuote,
                  style: TextStyle(
                    fontFamily: 'Literata',
                    fontStyle: FontStyle.italic,
                    fontSize: 17,
                    height: 1.4,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(s.posterSrc, style: JType.ui(11.5, color: c.sub)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        _Beat(
          enter: enter,
          leave: leave,
          at: _consistencyBeats[1] - 0.3,
          span: 0.36,
          from: const Offset(0, 36),
          leaveAt: 0.05,
          child: _SurfaceCard(
            palette: palette,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _monthYearLabel(s, now),
                        style: JType.ui(14, w: FontWeight.w700, color: c.ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _Notebook(
                  c: c,
                  app: app,
                  now: now,
                  compact: true,
                  since: app.firstUseDate,
                  softEmpty: true,
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
        ),
        const Spacer(),
        _Beat(
          enter: enter,
          leave: leave,
          at: _consistencyBeats[2] - 0.24,
          from: const Offset(0, 16),
          child: Row(
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
        ),
        const SizedBox(height: 6),
      ],
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
          height: 46,
          decoration: BoxDecoration(
            color: c.ink.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: c.hair, width: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: c.ink),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JType.ui(13.5, w: FontWeight.w700, color: c.ink),
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
