part of 'home.dart';

// ── Прототип «Страницы» ──────────────────────────────────────────────────────
// Нижний экран — вертикальные страницы: Таймер ↓ Намазы ↓ Дела ↓ Постоянство.
//
// Переход — не слайд фотографии, а хореография: каждый элемент появляется со
// своей задержкой и со своего направления, дуга солнца рисуется линией, фон
// двигается медленнее контента. Всё вычисляется из положения пальца, поэтому
// переход можно «перематывать»: вести медленно, остановиться, вернуться.
// Когда элемент встаёт на место, Taptic Engine даёт короткий щелчок.
//
// Включается в «Оформлении» (нижний экран → страницы). Классический вид не
// меняется.

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

/// «Вторник, 29 сентября · 18 раби ас-сани» — обе даты сразу.
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
/// сначала должны раствориться таймер и кнопки главного экрана.
double _enterStart(int page) => page == 1 ? 0.55 : 0.35;

// ── Хореография ─────────────────────────────────────────────────────────────

/// Моменты (в долях входа страницы), когда элементы «встают на место».
/// По ним же звучит Taptic Engine — вибрация совпадает с движением.
const _prayerRowBeats = [0.34, 0.42, 0.50, 0.58, 0.66, 0.74];
const _deedBeats = [0.40, 0.56, 0.66, 0.76, 0.86];
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
    this.span = 0.34,
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
  State<_PagesDayLayer> createState() => _PagesDayLayerState();
}

class _PagesDayLayerState extends State<_PagesDayLayer> {
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  /// Все моменты «элемент встал на место» в координатах ленты.
  static final List<double> _beats = [
    for (final (page, beats) in const [
      (1, _prayerRowBeats),
      (2, _deedBeats),
      (3, _consistencyBeats),
    ])
      for (final b in beats)
        page - 1 + _enterStart(page) + (b + 0.16) * (1 - _enterStart(page)),
  ];

  @override
  void didUpdateWidget(_PagesDayLayer old) {
    super.didUpdateWidget(old);
    final from = old.p, to = widget.p;
    if (from == to) return;
    final lo = math.min(from, to), hi = math.max(from, to);
    final crossed = _beats.any((b) => b > lo && b <= hi);
    if (!crossed) return;
    // Не чаще раза в 45 мс: при быстром свайпе получается мягкий каскад,
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
    final now = w.schedule.now();

    Widget page(int index, Widget Function(double enter, double leave) build) {
      final d = index - w.p;
      if (d.abs() >= 1.0) return const SizedBox.shrink();
      // Новая страница начинает появляться, когда старая почти ушла:
      // сначала уходит прежнее, потом приходит новое, с короткой перекличкой.
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
                padding: const EdgeInsets.fromLTRB(22, 6, 30, 6),
                child: build(enter, leave),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: _PagesAmbience(p: w.p, c: c, isLight: w.palette.isLight),
          ),
        ),
        page(
          1,
          (enter, leave) => _PrayersPage(
            enter: enter,
            leave: leave,
            s: w.s,
            c: c,
            palette: w.palette,
            app: w.app,
            t: w.t,
            nowSec: w.nowSec,
            now: now,
            onNext: () => w.onGoTo(2),
          ),
        ),
        page(
          2,
          (enter, leave) => _DeedsPage(
            enter: enter,
            leave: leave,
            s: w.s,
            c: c,
            palette: w.palette,
            app: w.app,
            t: w.t,
            nowMin: w.nowMin,
            onReader: w.onReader,
            onNext: () => w.onGoTo(3),
          ),
        ),
        page(
          3,
          (enter, leave) => _ConsistencyPage(
            enter: enter,
            leave: leave,
            s: w.s,
            c: c,
            palette: w.palette,
            app: w.app,
            now: now,
          ),
        ),
      ],
    );
  }
}

/// Фон страниц: тонкий узор восьмиконечных звёзд и мягкое золотое свечение.
/// Узор движется медленнее контента — отсюда ощущение глубины, а страница
/// не выглядит пустой даже там, где нет элементов.
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
    final appear = _seg(p, 0.2, 1.0);
    return Opacity(
      opacity: appear,
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
    // Свечение плывёт между «главными» местами страниц: над дугой солнца,
    // над карточкой дела, над хадисом.
    const anchors = [0.26, 0.30, 0.24];
    final k = (p - 1).clamp(0.0, 2.0);
    final lo = k.floor().clamp(0, 2), hi = k.ceil().clamp(0, 2);
    final f = k - lo;
    final y = size.height * (anchors[lo] + (anchors[hi] - anchors[lo]) * f);
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

  /// 0 — Кибла, 1 — Таймер, 2 — Намазы, 3 — Дела, 4 — Постоянство.
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
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: JType.caption(c.gold, size: 12),
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

// ── Страница 1: Намазы ──────────────────────────────────────────────────────

class _PrayersPage extends StatelessWidget {
  const _PrayersPage({
    required this.enter,
    required this.leave,
    required this.s,
    required this.c,
    required this.palette,
    required this.app,
    required this.t,
    required this.nowSec,
    required this.now,
    required this.onNext,
  });

  final double enter, leave;
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
    final left = _pagesDuration(s, ((targetSec - nowSec) / 60).ceil());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Beat(
          enter: enter,
          leave: leave,
          at: 0.0,
          from: const Offset(-18, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PageCaption(
                      kz ? 'Намаз уақыттары' : 'Время намазов',
                      c: c,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _pagesDateLine(s, now),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: JType.ui(12.5, color: c.sub),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _CityPill(app: app, c: c, kz: kz),
            ],
          ),
        ),
        const Spacer(),
        // Дуга солнца рисуется линией по мере свайпа.
        _Beat(
          enter: enter,
          leave: leave,
          at: 0.06,
          span: 0.5,
          from: const Offset(0, 14),
          leaveAt: 0.05,
          child: SizedBox(
            height: 150,
            child: CustomPaint(
              painter: _SunArcPainter(
                t: t,
                nowSec: nowSec,
                next: next,
                draw: Curves.easeInOutCubic.transform(_seg(enter, 0.08, 0.62)),
                c: c,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Beat(
          enter: enter,
          leave: leave,
          at: 0.1,
          span: 0.3,
          from: const Offset(0, 30),
          leaveAt: 0.05,
          child: _SurfaceCard(
            palette: palette,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Column(
              children: [
                for (final (i, prayer) in Prayer.values.indexed)
                  _Beat(
                    enter: enter,
                    leave: leave,
                    at: _prayerRowBeats[i] - 0.18,
                    // Строки прилетают попеременно слева и справа и сходятся
                    // в один столбец.
                    from: Offset(i.isEven ? -34 : 34, 10),
                    leaveAt: 0.012 * i,
                    child: _PrayerRow(
                      name: s.prayers[i],
                      time: t.fmt(prayer),
                      isSunrise: prayer == Prayer.sunrise,
                      isNext: prayer == next,
                      isPast: t.times[prayer]! * 60 <= nowSec && prayer != next,
                      left: prayer == next
                          ? (kz ? '$left кейін' : 'через $left')
                          : null,
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
        const Spacer(flex: 2),
        _Beat(
          enter: enter,
          leave: leave,
          at: 0.7,
          span: 0.3,
          from: const Offset(0, 10),
          child: _NextHint(
            label: kz ? 'Бүгінгі істер' : 'Дела сегодня',
            c: c,
            onTap: onNext,
          ),
        ),
      ],
    );
  }
}

/// Путь солнца за день. Горизонт — линия восхода и Магриба: днём солнце
/// идёт дугой над ним, а Фаджр и Иша лежат под горизонтом, как в жизни.
/// Пройденная часть дня — золотая, следующий намаз — яркая точка.
class _SunArcPainter extends CustomPainter {
  _SunArcPainter({
    required this.t,
    required this.nowSec,
    required this.next,
    required this.draw,
    required this.c,
  });

  final DayTimes t;
  final int nowSec;
  final Prayer next;

  /// Насколько дуга «дорисована» (0…1) — привязано к свайпу.
  final double draw;
  final JColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final fajr = t.times[Prayer.fajr]!.toDouble();
    final sunrise = t.times[Prayer.sunrise]!.toDouble();
    final maghrib = t.times[Prayer.maghrib]!.toDouble();
    final isha = t.times[Prayer.isha]!.toDouble();
    const pad = 14.0;
    final base = size.height * 0.66;
    final ry = base - 14;

    Offset at(double minute) {
      final m = minute.clamp(fajr, isha);
      final x = pad + (size.width - pad * 2) * (m - fajr) / (isha - fajr);
      final sine = math.sin(math.pi * (m - sunrise) / (maghrib - sunrise));
      // Под горизонтом кривая неглубокая: сумерки, а не полночь.
      return Offset(x, base - ry * math.max(sine, -0.42));
    }

    final path = Path();
    const samples = 90;
    for (var i = 0; i <= samples; i++) {
      final pt = at(fajr + (isha - fajr) * i / samples);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    final metric = path.computeMetrics().first;
    final full = metric.length;
    double lengthAt(double minute) {
      final f = ((minute - fajr) / (isha - fajr)).clamp(0.0, 1.0);
      // Длина по кривой почти пропорциональна времени — для обрезки хватает.
      return full * f;
    }

    // Горизонт проявляется от центра к краям.
    final half = size.width / 2 * Curves.easeOut.transform(_seg(draw, 0, 0.5));
    canvas.drawLine(
      Offset(size.width / 2 - half, base),
      Offset(size.width / 2 + half, base),
      Paint()
        ..color = c.hair
        ..strokeWidth = 1,
    );

    canvas.drawPath(
      metric.extractPath(0, full * draw),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = c.sub.withValues(alpha: 0.42),
    );

    final nowMin = nowSec / 60;
    // После Иша впереди уже завтрашний день — пройденного на нём нет.
    final passedLen = nowMin >= isha
        ? 0.0
        : math.min(lengthAt(nowMin), full * draw);
    if (nowMin > fajr && passedLen > 0) {
      canvas.drawPath(
        metric.extractPath(0, passedLen),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = c.gold.withValues(alpha: 0.85),
      );
    }

    // Точки намазов появляются, когда до них дорисовалась кривая.
    for (final prayer in Prayer.values) {
      final m = t.times[prayer]!.toDouble();
      final f = ((m - fajr) / (isha - fajr)).clamp(0.0, 1.0);
      final show = _seg(draw, f - 0.02, f + 0.06);
      if (show <= 0) continue;
      final pt = at(m);
      final isNext = prayer == next;
      final isSunrise = prayer == Prayer.sunrise;
      final r = (isNext ? 5.5 : (isSunrise ? 2.5 : 3.5)) * show;
      if (isNext) {
        canvas.drawCircle(
          pt,
          r * 3,
          Paint()
            ..color = c.gold.withValues(alpha: 0.28 * show)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawCircle(
        pt,
        r,
        Paint()
          ..color = isNext
              ? c.gold
              : (m <= nowMin && nowMin < isha
                    ? c.gold.withValues(alpha: 0.9)
                    : c.sub),
      );
    }

    // Светило: днём — солнце над горизонтом, в сумерках — тусклая точка.
    if (nowMin > fajr && nowMin < isha) {
      final f = (nowMin - fajr) / (isha - fajr);
      final show = _seg(draw, f - 0.02, f + 0.1);
      if (show > 0) {
        final pt = at(nowMin);
        final day = nowMin > sunrise && nowMin < maghrib;
        final light = day ? const Color(0xFFFFE2A3) : c.sub;
        canvas.drawCircle(
          pt,
          (day ? 18 : 10) * show,
          Paint()
            ..color = light.withValues(alpha: (day ? 0.35 : 0.2) * show)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
        canvas.drawCircle(pt, (day ? 7 : 4) * show, Paint()..color = light);
      }
    }
  }

  @override
  bool shouldRepaint(_SunArcPainter o) =>
      o.draw != draw || o.nowSec ~/ 60 != nowSec ~/ 60 || o.next != next;
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
          constraints: const BoxConstraints(minHeight: 32),
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

class _PrayerRow extends StatelessWidget {
  const _PrayerRow({
    required this.name,
    required this.time,
    required this.isSunrise,
    required this.isNext,
    required this.isPast,
    required this.left,
    required this.c,
    required this.onTap,
  });

  final String name, time;
  final String? left;
  final bool isSunrise, isNext, isPast;
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
        constraints: BoxConstraints(minHeight: isSunrise ? 34 : 46),
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

  bool get isCustom => id.startsWith('custom:');
}

class _DeedsPage extends StatelessWidget {
  const _DeedsPage({
    required this.enter,
    required this.leave,
    required this.s,
    required this.c,
    required this.palette,
    required this.app,
    required this.t,
    required this.nowMin,
    required this.onReader,
    required this.onNext,
  });

  final double enter, leave;
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
    // Главное дело — открытое сейчас, иначе ближайшее следующее.
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
    // Экран не прокручивается (свайп — у ленты страниц), поэтому длинный
    // список своих напоминаний сворачивается в строку «ещё N».
    const maxRows = 5;
    final shown = others.take(maxRows).toList();
    final hidden = others.length - shown.length;
    final allDone = deeds.every((d) => app.isDone(d.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Beat(
          enter: enter,
          leave: leave,
          at: 0.0,
          from: const Offset(-18, 0),
          child: _PageCaption(kz ? 'Бүгінгі істер' : 'Дела сегодня', c: c),
        ),
        const Spacer(),
        _Beat(
          enter: enter,
          leave: leave,
          at: _deedBeats[0] - 0.26,
          span: 0.4,
          from: const Offset(0, 40),
          child: hero != null
              ? _HeroDeed(
                  deed: hero,
                  state: _stateOf(hero),
                  nowMin: nowMin,
                  s: s,
                  c: c,
                  palette: palette,
                )
              : _RestCard(allDone: allDone, s: s, c: c, palette: palette),
        ),
        const SizedBox(height: 14),
        if (shown.isNotEmpty)
          _Beat(
            enter: enter,
            leave: leave,
            at: 0.3,
            span: 0.3,
            from: const Offset(0, 30),
            leaveAt: 0.05,
            child: _SurfaceCard(
              palette: palette,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                children: [
                  for (final (i, deed) in shown.indexed)
                    _Beat(
                      enter: enter,
                      leave: leave,
                      at:
                          _deedBeats[math.min(i + 1, _deedBeats.length - 1)] -
                          0.18,
                      from: Offset(i.isEven ? 30 : -30, 8),
                      leaveAt: 0.012 * i,
                      child: _DeedRow(
                        deed: deed,
                        state: _stateOf(deed),
                        s: s,
                        c: c,
                      ),
                    ),
                  if (hidden > 0)
                    _Beat(
                      enter: enter,
                      leave: leave,
                      at: 0.8,
                      span: 0.2,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => RemindersScreen.open(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
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
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
        _Beat(
          enter: enter,
          leave: leave,
          at: 0.66,
          span: 0.3,
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
                      kz ? 'Еске салуларды баптау' : 'Настроить напоминания',
                      style: JType.ui(13, w: FontWeight.w600, color: c.sub),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Spacer(flex: 2),
        _Beat(
          enter: enter,
          leave: leave,
          at: 0.7,
          span: 0.3,
          from: const Offset(0, 10),
          child: _NextHint(
            label: _sentenceCase(s.notebookTitle),
            c: c,
            onTap: onNext,
          ),
        ),
      ],
    );
  }
}

/// Главная карточка страницы дел: что сделать сейчас или следующим.
class _HeroDeed extends StatelessWidget {
  const _HeroDeed({
    required this.deed,
    required this.state,
    required this.nowMin,
    required this.s,
    required this.c,
    required this.palette,
  });

  final _Deed deed;
  final _DeedState state;
  final int nowMin;
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
    final at = kz
        ? '${_pagesHhmm(deed.minute)} уақыты'
        : 'В ${_pagesHhmm(deed.minute)}';
    final String detail;
    if (deed.isCustom) {
      detail = at;
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
          padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
          decoration: BoxDecoration(
            color: open
                ? c.gold.withValues(alpha: palette.isLight ? 0.13 : 0.12)
                : c.ink.withValues(alpha: palette.isLight ? 0.06 : 0.07),
            borderRadius: BorderRadius.circular(24),
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
                style: JType.caption(open ? c.gold : c.sub, size: 11),
              ),
              const SizedBox(height: 6),
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
                          style: JType.ui(19, w: FontWeight.w700, color: c.ink),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: JType.ui(13, color: open ? c.gold : c.sub),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: open ? c.gold : c.ink.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      action,
                      style: JType.ui(
                        13.5,
                        w: FontWeight.w700,
                        color: open
                            ? (palette.isLight ? Colors.white : c.bg)
                            : c.ink,
                      ),
                    ),
                  ),
                ],
              ),
              if (open && !deed.isCustom) ...[
                const SizedBox(height: 14),
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

/// Когда открытых и будущих дел не осталось.
class _RestCard extends StatelessWidget {
  const _RestCard({
    required this.allDone,
    required this.s,
    required this.c,
    required this.palette,
  });

  final bool allDone;
  final S s;
  final JColors c;
  final DaySurfacePalette palette;

  @override
  Widget build(BuildContext context) {
    final kz = s == S.kz;
    final title = allDone
        ? (kz ? 'Бүгінгі істер белгіленді' : 'Дела на сегодня отмечены')
        : (kz ? 'Бүгінгі уақыттар өтті' : 'Окна на сегодня закрыты');
    final sub = kz
        ? 'Ертең таңғы зікірлер — бамдаттан кейін'
        : 'Завтра утренние зикры — после Фаджра';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.ink.withValues(alpha: palette.isLight ? 0.06 : 0.07),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.hair, width: 0.8),
      ),
      child: Row(
        children: [
          Icon(
            allDone ? CupertinoIcons.checkmark_seal : CupertinoIcons.moon_stars,
            size: 26,
            color: allDone ? c.green : c.gold,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: JType.ui(17, w: FontWeight.w700, color: c.ink),
                ),
                const SizedBox(height: 3),
                Text(sub, style: JType.ui(13, color: c.sub)),
              ],
            ),
          ),
        ],
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
          constraints: const BoxConstraints(minHeight: 46),
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

// ── Страница 3: Постоянство ─────────────────────────────────────────────────

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
        _Beat(
          enter: enter,
          leave: leave,
          at: 0.0,
          from: const Offset(-18, 0),
          child: _PageCaption(s.notebookTitle, c: c),
        ),
        const Spacer(),
        // Хадис о постоянстве — тот же утверждённый текст, что в онбординге.
        _Beat(
          enter: enter,
          leave: leave,
          at: _consistencyBeats[0] - 0.3,
          span: 0.45,
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
        const SizedBox(height: 18),
        _Beat(
          enter: enter,
          leave: leave,
          at: _consistencyBeats[1] - 0.28,
          span: 0.4,
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
        const Spacer(flex: 2),
        _Beat(
          enter: enter,
          leave: leave,
          at: _consistencyBeats[2] - 0.2,
          span: 0.3,
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
