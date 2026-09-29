import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../prayer/schedule.dart';
import '../prayer/city.dart';
import '../theme/home_scene.dart';
import '../theme/tokens.dart';

/// Динамическое «живое небо», привязанное к реальному времени суток
/// (через времена молитв города): солнце/луна плавно идут по дуге, цвета неба
/// перетекают ночь→рассвет→день→закат→ночь, на горизонте силуэт города-мечети,
/// ниже — город, который ночью оживает (окна, фонари). Цвет текста на главном
/// экране подстраивается под яркость неба (см. [skyForeground]).
class SceneBackground extends StatefulWidget {
  const SceneBackground({
    super.key,
    required this.progress,
    required this.screenHeight,
    required this.times,
    required this.nowSec,
    required this.city,
    required this.variant,
  });

  final double progress; // 0 — главный (небо), 1 — «день» (город внизу)
  final double screenHeight;
  final DayTimes times;
  final int nowSec;
  final City city;
  final HomeScene variant;

  @override
  State<SceneBackground> createState() => _SceneBackgroundState();
}

/// Верхняя часть общей вертикальной сцены. Нижний цвет намеренно совпадает
/// с самым верхним цветом главного неба: при свайпе два полноэкранных слоя
/// встречаются без отдельной линии или цветового скачка.
class QiblaSceneBackground extends StatelessWidget {
  const QiblaSceneBackground({
    super.key,
    required this.progress,
    required this.screenHeight,
    required this.times,
    required this.nowSec,
  });

  final double progress;
  final double screenHeight;
  final DayTimes times;
  final int nowSec;

  @override
  Widget build(BuildContext context) {
    final sky = _skyAt(times, nowSec ~/ 60);
    final deep = Color.lerp(sky.top, const Color(0xFF07101B), 0.78)!;
    final middle = Color.lerp(deep, sky.top, 0.46)!;

    return Positioned(
      left: 0,
      right: 0,
      top: -screenHeight * (1 + progress),
      // Небольшой физический нахлёст исключает субпиксельную щель во время
      // интерактивного жеста. Слой рисуется после главного неба, поэтому эти
      // четыре пикселя принадлежат верхней странице и не дают линии на стыке.
      height: screenHeight + (progress < 0 ? 4 : 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [deep, middle, sky.top],
            stops: const [0.0, 0.58, 1.0],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.62, -0.22),
              radius: 1.15,
              colors: [sky.bottom.withValues(alpha: 0.14), Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }
}

class _SceneBackgroundState extends State<SceneBackground>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _introController;
  late Animation<double> _introAnimation;
  double _startX = 0;
  double _startY = 0;
  double _len = 80;
  ui.Image? _meccaDayImage;
  ui.Image? _meccaTwilightImage;
  ui.Image? _meccaNightImage;
  ui.Image? _natureImage;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _introAnimation = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    );
    if (widget.nowSec % 24 == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startShootingStar();
      });
    }
    _loadSceneImages();
    _introController.forward(from: 0.0);
  }

  Future<ui.Image> _loadImage(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<void> _loadSceneImages() async {
    try {
      final images = await Future.wait([
        _loadImage('assets/images/mecca_architecture_day_v3.png'),
        _loadImage('assets/images/mecca_architecture_twilight_v3.png'),
        _loadImage('assets/images/mecca_architecture_night_v3.png'),
        _loadImage('assets/images/nature_landscape_v2.png'),
      ]);
      if (mounted) {
        setState(() {
          _meccaDayImage = images[0];
          _meccaTwilightImage = images[1];
          _meccaNightImage = images[2];
          _natureImage = images[3];
        });
      }
    } catch (e) {
      debugPrint('Error loading scene artwork: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _introController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SceneBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.nowSec != oldWidget.nowSec && widget.nowSec % 24 == 0) {
      _startShootingStar();
    }
    if (widget.city.name != oldWidget.city.name ||
        widget.times.date != oldWidget.times.date ||
        widget.variant != oldWidget.variant) {
      _introController.forward(from: 0.0);
    }
  }

  void _startShootingStar() {
    if (!mounted) return;
    final r = Random(widget.nowSec);
    final width = MediaQuery.of(context).size.width;
    final horizon = widget.screenHeight;
    _startX = width * (0.15 + r.nextDouble() * 0.55);
    _startY = horizon * (0.05 + r.nextDouble() * 0.25);
    _len = 60.0 + r.nextDouble() * 40.0;
    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    // Вся двухэкранная сцена едет за пальцем 1:1 — как вертикальная лента.
    // Мекку намеренно не замедляем отдельно: при классическом параллаксе она
    // задерживалась и оказывалась под карточками экрана «дня».
    final dy = -widget.progress * widget.screenHeight;
    final transitionSky = _skyAt(widget.times, widget.nowSec ~/ 60);
    final horizonVeil = Color.lerp(
      transitionSky.bottom,
      const Color(0xFF0B0F1C),
      0.62,
    )!;
    final transitionOpacity = sin(pi * widget.progress).clamp(0.0, 1.0);
    return Positioned(
      left: 0,
      right: 0,
      top: dy,
      height: widget.screenHeight * 2,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([_controller, _introAnimation]),
                builder: (context, _) {
                  return CustomPaint(
                    painter: _ScenePainter(
                      times: widget.times,
                      nowSec: widget.nowSec,
                      shootingStarVal: _controller.value,
                      startX: _startX,
                      startY: _startY,
                      len: _len,
                      meccaDayImage: _meccaDayImage,
                      meccaTwilightImage: _meccaTwilightImage,
                      meccaNightImage: _meccaNightImage,
                      natureImage: _natureImage,
                      introVal: _introAnimation.value,
                      variant: widget.variant,
                    ),
                    size: Size.infinite,
                  );
                },
              ),
            ),
          ),
          // Дымка существует только во время жеста. Она закрывает математическую
          // границу двух кадров, но сама едет вместе со сценой, поэтому свайп
          // по-прежнему ощущается как перелистывание целого экрана.
          Positioned(
            left: 0,
            right: 0,
            top: widget.screenHeight - 150,
            height: 300,
            child: IgnorePointer(
              child: Opacity(
                opacity: transitionOpacity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        horizonVeil.withValues(alpha: 0.0),
                        horizonVeil.withValues(alpha: 0.18),
                        horizonVeil.withValues(alpha: 0.72),
                        horizonVeil.withValues(alpha: 0.88),
                        horizonVeil.withValues(alpha: 0.52),
                        horizonVeil.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.22, 0.42, 0.54, 0.72, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Модель неба: цвета и «дневность» по времени ──────────────────────────────

class _SkyKey {
  final int min;
  final Color top, bottom;
  final double day; // 0 ночь … 1 полдень (для яркости/текста)
  const _SkyKey(this.min, this.top, this.bottom, this.day);
}

/// Ключевые кадры неба по времени дня, привязанные к молитвам города.
List<_SkyKey> _skyKeys(DayTimes t) {
  final fajr = t.times[Prayer.fajr]!;
  final sun = t.times[Prayer.sunrise]!;
  final dhuhr = t.times[Prayer.dhuhr]!;
  final asr = t.times[Prayer.asr]!;
  final magh = t.times[Prayer.maghrib]!;
  final isha = t.times[Prayer.isha]!;
  return [
    _SkyKey(0, const Color(0xFF090D1C), const Color(0xFF10182C), 0),
    _SkyKey(fajr, const Color(0xFF161A34), const Color(0xFF3A2E50), 0.06),
    _SkyKey(
      (fajr + sun) ~/ 2,
      const Color(0xFF2A3560),
      const Color(0xFF9A6E7A),
      0.18,
    ),
    _SkyKey(sun, const Color(0xFF4E74B4), const Color(0xFFE7B078), 0.4),
    _SkyKey(dhuhr, const Color(0xFF4F93D8), const Color(0xFFCFE3F2), 1.0),
    _SkyKey(asr, const Color(0xFF5A93CE), const Color(0xFFD8E0EA), 0.85),
    _SkyKey(magh - 30, const Color(0xFF3A5590), const Color(0xFFE8A768), 0.45),
    _SkyKey(magh, const Color(0xFF2A3568), const Color(0xFFDB7A50), 0.28),
    _SkyKey(isha, const Color(0xFF0E1428), const Color(0xFF1E2038), 0.05),
    _SkyKey(1440, const Color(0xFF090D1C), const Color(0xFF10182C), 0),
  ];
}

class _Sky {
  final Color top, bottom;
  final double day;
  const _Sky(this.top, this.bottom, this.day);
}

_Sky _skyAt(DayTimes t, int nowMin) {
  final keys = _skyKeys(t);
  _SkyKey a = keys.first, b = keys.last;
  for (var i = 0; i < keys.length - 1; i++) {
    if (nowMin >= keys[i].min && nowMin <= keys[i + 1].min) {
      a = keys[i];
      b = keys[i + 1];
      break;
    }
  }
  final span = (b.min - a.min);
  final x = span == 0 ? 0.0 : (nowMin - a.min) / span;
  return _Sky(
    Color.lerp(a.top, b.top, x)!,
    Color.lerp(a.bottom, b.bottom, x)!,
    a.day + (b.day - a.day) * x,
  );
}

/// Цвета текста/акцента для главного экрана — подстраиваются под яркость неба.
class SkyFg {
  final Color text, faint, accent;
  final List<Shadow> shadows;
  const SkyFg(this.text, this.faint, this.accent, this.shadows);
}

/// Палитра второго экрана. Она использует ту же фазу суток, что и небо,
/// но намеренно не повторяет солнце, луну и город: только свет, глубину и
/// оттенок атмосферы. Так два экрана принадлежат одной сцене без перегруза.
class DaySurfacePalette {
  const DaySurfacePalette({
    required this.colors,
    required this.isLight,
    required this.top,
    required this.middle,
    required this.bottom,
    required this.glow,
    required this.surface,
    required this.border,
    required this.dock,
    required this.dockBorder,
    required this.shadow,
  });

  final JColors colors;
  final bool isLight;
  final Color top, middle, bottom, glow;
  final Color surface, border, dock, dockBorder, shadow;
}

double _smoothStep(double edge0, double edge1, double value) {
  final x = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0).toDouble();
  return x * x * (3 - 2 * x);
}

/// WCAG-контраст двух непрозрачных цветов. Нижний экран использует стекло,
/// поэтому фактический фон текста сначала нужно получить через [compositeOver].
double colorContrastRatio(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return (max(a, b) + 0.05) / (min(a, b) + 0.05);
}

/// Результат наложения полупрозрачного [foreground] на [background].
Color compositeOver(Color foreground, Color background) {
  final alpha = foreground.a;
  return Color.from(
    alpha: 1,
    red: foreground.r * alpha + background.r * (1 - alpha),
    green: foreground.g * alpha + background.g * (1 - alpha),
    blue: foreground.b * alpha + background.b * (1 - alpha),
  );
}

double _minimumContrast(Color color, Iterable<Color> backgrounds) => backgrounds
    .map((background) => colorContrastRatio(color, background))
    .reduce(min);

Color _ensureContrast(
  Color color,
  Color endpoint,
  Iterable<Color> backgrounds, {
  double minimum = 4.5,
}) {
  if (_minimumContrast(color, backgrounds) >= minimum) return color;

  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 14; i++) {
    final t = (low + high) / 2;
    final candidate = Color.lerp(color, endpoint, t)!;
    if (_minimumContrast(candidate, backgrounds) >= minimum) {
      high = t;
    } else {
      low = t;
    }
  }
  return Color.lerp(color, endpoint, high)!;
}

DaySurfacePalette daySurfacePalette(DayTimes t, int nowSec) {
  final sky = _skyAt(t, nowSec ~/ 60);
  final fajrSec = t.times[Prayer.fajr]! * 60;
  final sunriseSec = t.times[Prayer.sunrise]! * 60;
  final maghribSec = t.times[Prayer.maghrib]! * 60;
  final ishaSec = t.times[Prayer.isha]! * 60;

  // Небо начинает краснеть заранее, но это не повод заранее смешивать
  // светлую поверхность с тёмно-серой темой. Именно такая смесь делала весь
  // нижний экран мутным за 20–30 минут до Магриба. До самого Магриба держим
  // чистую светлую основу; затем плавно переходим в ночную к Иша. На рассвете
  // выполняем обратный переход от Фаджра до восхода.
  final double nightBlend;
  if (nowSec < fajrSec) {
    nightBlend = 1;
  } else if (nowSec < sunriseSec) {
    final dawnProgress = (nowSec - fajrSec) / (sunriseSec - fajrSec);
    nightBlend = 1 - _smoothStep(0, 1, dawnProgress);
  } else if (nowSec < maghribSec) {
    nightBlend = 0;
  } else if (nowSec < ishaSec) {
    final duskProgress = (nowSec - maghribSec) / (ishaSec - maghribSec);
    nightBlend = _smoothStep(0, 1, duskProgress);
  } else {
    nightBlend = 1;
  }
  final surfaceBlend = _smoothStep(0.18, 0.92, nightBlend);

  final lightTop = Color.lerp(const Color(0xFFDDE8ED), sky.bottom, 0.38)!;
  final lightMiddle = Color.lerp(const Color(0xFFCAD8DE), sky.top, 0.16)!;
  final lightBottom = Color.lerp(lightMiddle, const Color(0xFFB8C9C8), 0.64)!;

  final darkTop = Color.lerp(const Color(0xFF172235), sky.bottom, 0.30)!;
  final darkMiddle = Color.lerp(const Color(0xFF101B24), sky.top, 0.18)!;
  final darkBottom = Color.lerp(darkMiddle, const Color(0xFF061112), 0.78)!;

  const lightColors = JColors(
    bg: Color(0xFFD7E2E4),
    ink: Color(0xFF1E2830),
    sub: Color(0xFF34434C),
    faint: Color(0xFF3D4B54),
    hair: Color(0xFFB6C1C4),
    gold: Color(0xFF855B0B),
    green: Color(0xFF4F7460),
    gdim: Color(0xFFD8E4DC),
    red: Color(0xFF9E4B43),
    card: Color(0xFFF7F4EC),
    btnbg: Color(0xFF1E2830),
    btnink: Color(0xFFF7F4EC),
  );
  const darkColors = JColors(
    bg: Color(0xFF0D171D),
    ink: Color(0xFFF1EFE7),
    sub: Color(0xFFD3D9D5),
    faint: Color(0xFFB1BCB7),
    hair: Color(0xFF35423F),
    gold: Color(0xFFE0AE4A),
    green: Color(0xFF678A74),
    gdim: Color(0xFF26362E),
    red: Color(0xFFB45B52),
    card: Color(0xFF172127),
    btnbg: Color(0xFFF1EFE7),
    btnink: Color(0xFF10191E),
  );

  final top = Color.lerp(lightTop, darkTop, nightBlend)!;
  final middle = Color.lerp(lightMiddle, darkMiddle, nightBlend)!;
  final bottom = Color.lerp(lightBottom, darkBottom, nightBlend)!;

  // За полчаса до Магриба фон уже заметно темнеет, но прежнее стекло всё ещё
  // пропускало его примерно на 30%. На серо-синем результате вторичный текст
  // и календарь падали до 1.5–2.4:1. В сумерках делаем карточку плотнее, при
  // этом сама атмосферная смена цвета остаётся плавной.
  final twilightReadability =
      _smoothStep(0.24, 0.50, nightBlend) *
      (1 - _smoothStep(0.66, 0.84, nightBlend));
  final baseSurface = Color.lerp(
    const Color(0xB8FFFFFF),
    const Color(0xA6172228),
    surfaceBlend,
  )!;
  final surface = baseSurface.withValues(
    alpha: (baseSurface.a + 0.18 * twilightReadability).clamp(0.0, 1.0),
  );
  final cardBackgrounds = [
    compositeOver(surface, top),
    compositeOver(surface, middle),
    compositeOver(surface, bottom),
  ];

  // Не интерполируем светлый и тёмный текст через средне-серый: именно эта
  // промежуточная смесь теряла читаемость. Выбираем полярность по худшему из
  // трёх участков градиента, затем аккуратно усиливаем каждый смысловой цвет
  // до 4.5:1 на фактической (уже скомпонованной) подложке.
  const darkEndpoint = Color(0xFF05090C);
  const lightEndpoint = Color(0xFFFCFAF4);
  final darkScore = _minimumContrast(darkEndpoint, cardBackgrounds);
  final lightScore = _minimumContrast(lightEndpoint, cardBackgrounds);
  final useDarkText = darkScore >= lightScore;
  final baseColors = useDarkText ? lightColors : darkColors;
  final endpoint = useDarkText ? darkEndpoint : lightEndpoint;
  final colors = JColors(
    bg: baseColors.bg,
    ink: _ensureContrast(baseColors.ink, endpoint, cardBackgrounds),
    sub: _ensureContrast(baseColors.sub, endpoint, cardBackgrounds),
    faint: _ensureContrast(baseColors.faint, endpoint, cardBackgrounds),
    hair: _ensureContrast(
      baseColors.hair,
      endpoint,
      cardBackgrounds,
      minimum: 3,
    ),
    gold: _ensureContrast(baseColors.gold, endpoint, cardBackgrounds),
    green: baseColors.green,
    gdim: baseColors.gdim,
    red: baseColors.red,
    card: baseColors.card,
    btnbg: baseColors.btnbg,
    btnink: baseColors.btnink,
  );
  final isLight = useDarkText;

  return DaySurfacePalette(
    colors: colors,
    isLight: isLight,
    top: top,
    middle: middle,
    bottom: bottom,
    glow: sky.bottom,
    surface: surface,
    border: Color.lerp(
      const Color(0x8AFFFFFF),
      const Color(0x1FFFFFFF),
      surfaceBlend,
    )!,
    dock: Color.lerp(
      const Color(0xC7F8F7F2),
      const Color(0xB518232A),
      surfaceBlend,
    )!,
    dockBorder: Color.lerp(
      const Color(0xA8FFFFFF),
      const Color(0x2BFFFFFF),
      surfaceBlend,
    )!,
    shadow: Color.lerp(
      const Color(0x260D1B22),
      const Color(0x66000000),
      surfaceBlend,
    )!,
  );
}

/// Днём — тёмный текст, ночью — светлый. Без бледных промежуточных цветов:
/// на пёстром небе (закат/рассвет) они нечитаемы. Вместо этого — жёсткий
/// выбор день/ночь + мягкая контрастная тень, сильнее всего в переходные фазы.
SkyFg skyForeground(DayTimes t, int nowSec) {
  final sky = _skyAt(t, nowSec ~/ 60);

  // Вычисляем примерный цвет неба позади текста (верхняя треть экрана)
  final textBgColor = Color.lerp(sky.top, sky.bottom, 0.25)!;

  const darkText = Color(0xFF1B2230);
  const lightText = Color(0xFFF2EFE6);

  double contrastRatio(Color foreground, Color background) {
    final a = foreground.computeLuminance();
    final b = background.computeLuminance();
    return (max(a, b) + 0.05) / (min(a, b) + 0.05);
  }

  // Старый фиксированный порог 0.43 ошибочно считал полуденное голубое небо
  // «тёмным» и оставлял белую ночную палитру. Выбираем тот вариант, который
  // реально даёт больший контраст на текущем небе.
  final useDarkText =
      contrastRatio(darkText, textBgColor) >=
      contrastRatio(lightText, textBgColor);

  // Тени полностью убираем по запросу пользователя
  const shadows = <Shadow>[];

  return useDarkText
      ? SkyFg(
          darkText,
          const Color(0xFF34445A),
          const Color(0xFF7A540B),
          shadows,
        )
      : SkyFg(
          lightText,
          const Color(0xFFC9CDC2),
          const Color(0xFFE2B85E),
          shadows,
        );
}

// ── Художник сцены ───────────────────────────────────────────────────────────

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.times,
    required this.nowSec,
    required this.shootingStarVal,
    required this.startX,
    required this.startY,
    required this.len,
    required this.introVal,
    required this.variant,
    this.meccaDayImage,
    this.meccaTwilightImage,
    this.meccaNightImage,
    this.natureImage,
  });
  final DayTimes times;
  final int nowSec;
  final double shootingStarVal;
  final double startX;
  final double startY;
  final double len;
  final double introVal;
  final HomeScene variant;
  final ui.Image? meccaDayImage;
  final ui.Image? meccaTwilightImage;
  final ui.Image? meccaNightImage;
  final ui.Image? natureImage;

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width, H = size.height;
    final horizon = H * 0.5; // низ главного экрана / линия горизонта
    final nowMin = nowSec ~/ 60;

    // Вычисляем времена молитв для определения фаз дня и ночи
    final sun = times.times[Prayer.sunrise]!;
    final dhuhr = times.times[Prayer.dhuhr]!;
    final magh = times.times[Prayer.maghrib]!;
    final isDay = nowMin >= sun && nowMin <= magh;

    // Intro-анимация выполняется только при первом создании сцены и реальной
    // смене города/дня. Стабильные ключи в HomeScreen не дают ей повториться
    // после обычного перехода на экран Киблы и обратно.
    final startMin = isDay ? sun : magh;
    final startSky = _skyAt(times, startMin);
    final targetSky = _skyAt(times, nowMin);
    final skyTop = Color.lerp(startSky.top, targetSky.top, introVal)!;
    final skyBottom = Color.lerp(startSky.bottom, targetSky.bottom, introVal)!;
    final skyDay = startSky.day + (targetSky.day - startSky.day) * introVal;
    final night = (1 - skyDay * 2).clamp(0.0, 1.0); // 1 глубокая ночь … 0 день
    final sky = _Sky(skyTop, skyBottom, skyDay);
    final daySurface = daySurfacePalette(times, nowSec);

    // Небо и нижний экран — один непрерывный градиент на всю высоту сцены.
    // Отдельные прямоугольники раньше давали заметный горизонтальный стык
    // после свайпа, особенно на светлом дневном небе.
    final sceneRect = Rect.fromLTRB(0, 0, W, H);
    canvas.drawRect(
      sceneRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            skyTop,
            skyBottom,
            daySurface.top,
            daySurface.middle,
            daySurface.bottom,
          ],
          stops: const [0.0, 0.43, 0.53, 0.72, 1.0],
        ).createShader(sceneRect),
    );

    // На втором экране движется только атмосферный свет: большой мягкий
    // отблеск того же горизонта, что и на главном, без новых объектов.
    final lowerRect = Rect.fromLTRB(0, horizon, W, H);
    canvas.drawRect(
      lowerRect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(W * 0.78, horizon + (H - horizon) * 0.08),
          W * 1.05,
          [
            daySurface.glow.withValues(alpha: daySurface.isLight ? 0.28 : 0.20),
            daySurface.glow.withValues(alpha: 0.0),
          ],
        ),
    );

    // Звёзды и падающая звезда — ночью
    if (night > 0.15) {
      _stars(canvas, W, horizon, night);
      _shootingStar(canvas, night);
    }

    // 2. Координаты солнца/луны (расчет целевых значений)
    double targetFracX, targetAlt; // targetAlt: 0 у горизонта … 1 зенит
    if (isDay) {
      if (nowMin <= dhuhr) {
        final f = (nowMin - sun) / max(1, dhuhr - sun);
        targetFracX = 0.12 + f * 0.38;
        targetAlt = f;
      } else {
        final f = (nowMin - dhuhr) / max(1, magh - dhuhr);
        targetFracX = 0.5 + f * 0.38;
        targetAlt = 1.0 - f;
      }
    } else {
      final total = (1440 - magh) + sun;
      final nm = nowMin >= magh ? nowMin - magh : nowMin + (1440 - magh);
      final f = nm / max(1, total);
      targetFracX = 0.12 + f * 0.76;
      targetAlt = sin(f * pi);
    }

    // 3. Интерполяция координат (восхождение солнца/луны от горизонта по дуге)
    // Анимируем координаты от старта (горизонт: 0.12, 0.0) до цели
    final fracX = 0.12 + (targetFracX - 0.12) * introVal;
    final alt = 0.0 + (targetAlt - 0.0) * introVal;

    final cx = W * fracX;
    final cy = horizon * 0.92 - alt * horizon * 0.78;

    // Затемнение к низу — читаемость карточек «дня»
    final scrim = Rect.fromLTRB(0, horizon, W, H);
    canvas.drawRect(
      scrim,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: daySurface.isLight
              ? [const Color(0x00FFFFFF), const Color(0x12FFFFFF)]
              : [const Color(0x00061112), const Color(0x52061112)],
        ).createShader(scrim),
    );

    // Солнце / луна по дуге
    _celestial(canvas, cx, cy, horizon, isDay);

    // Художественный горизонт выбирается отдельно от геолокации пользователя.
    switch (variant) {
      case HomeScene.mecca:
        _mecca(canvas, W, horizon, H, sky, night, cx, cy, isDay, alt);
      case HomeScene.nature:
        _nature(canvas, W, horizon, sky, night, cx, cy, isDay, alt);
      case HomeScene.minimal:
        _minimalHorizon(canvas, W, horizon, sky, night);
    }
  }

  void _stars(Canvas canvas, double W, double horizon, double night) {
    final rnd = Random(7);
    final p = Paint()..color = Colors.white;
    for (var i = 0; i < 90; i++) {
      final x = rnd.nextDouble() * W;
      final y = rnd.nextDouble() * horizon * 0.85;
      final tw = 0.4 + 0.6 * (0.5 + 0.5 * sin((nowSec / 3 + i) * 0.7));
      p.color = Colors.white.withValues(
        alpha: (0.15 + rnd.nextDouble() * 0.5) * night * tw,
      );
      canvas.drawCircle(Offset(x, y), rnd.nextDouble() * 1.2 + 0.4, p);
    }
  }

  void _shootingStar(Canvas canvas, double night) {
    if (shootingStarVal <= 0.0 || shootingStarVal >= 1.0) return;

    final prog = shootingStarVal;
    final dx = startX + prog * 120.0;
    final dy = startY + prog * 60.0;
    final a = (1.0 - prog) * night;
    if (a <= 0) return;

    final head = Offset(dx, dy);
    final tail = Offset(dx - len * 0.7, dy - len * 0.35);

    final paint = Paint()
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.linear(head, tail, [
        Colors.white.withValues(alpha: a),
        Colors.white.withValues(alpha: 0.0),
      ]);

    canvas.drawLine(head, tail, paint);
  }

  void _celestial(
    Canvas canvas,
    double cx,
    double cy,
    double horizon,
    bool isDay,
  ) {
    if (isDay) {
      // солнце с мягким свечением
      final glow = Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFFFFF3C8).withValues(alpha: 0.85),
                const Color(0xFFFFE29A).withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromCircle(center: Offset(cx, cy), radius: horizon * 0.19),
            );
      canvas.drawCircle(Offset(cx, cy), horizon * 0.19, glow);
      canvas.drawCircle(
        Offset(cx, cy),
        horizon * 0.048,
        Paint()..color = const Color(0xFFFFF0C0),
      );
    } else {
      final glow = Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFFE9E2C2).withValues(alpha: 0.35),
                const Color(0xFFE9E2C2).withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromCircle(center: Offset(cx, cy), radius: horizon * 0.13),
            );
      canvas.drawCircle(Offset(cx, cy), horizon * 0.13, glow);
      // На 20% меньше прежнего: луна не спорит с таймером за внимание.
      final r = horizon * 0.042;
      final path1 = Path()
        ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      final path2 = Path()
        ..addOval(
          Rect.fromCircle(
            center: Offset(cx + r * 0.55, cy - r * 0.25),
            radius: r,
          ),
        );
      final crescent = Path.combine(PathOperation.difference, path1, path2);
      canvas.drawPath(crescent, Paint()..color = const Color(0xFFDCCB8E));
    }
  }

  void _mecca(
    Canvas canvas,
    double W,
    double horizon,
    double H,
    _Sky sky,
    double night,
    double celX,
    double celY,
    bool isDay,
    double alt,
  ) {
    final base = horizon;

    // 1. Атмосферное свечение за зданиями (sunset/sunrise glow)
    if (isDay && alt < 0.35) {
      final glowFactor = 1.0 - (alt / 0.35);
      final glowRect = Rect.fromLTRB(0, 0, W, base + 10);
      final glowPaint = Paint()
        ..shader = ui.Gradient.radial(
          Offset(celX, base - 10),
          W * 0.45,
          [
            const Color(0xFFE88A50).withValues(alpha: 0.35 * glowFactor),
            const Color(0xFFD9AE52).withValues(alpha: 0.12 * glowFactor),
            const Color(0x00000000),
          ],
          [0.0, 0.4, 1.0],
        );
      canvas.drawRect(glowRect, glowPaint);
    } else if (!isDay && alt > 0.1) {
      final glowFactor = (alt - 0.1) / 0.9;
      final glowRect = Rect.fromLTRB(0, 0, W, base + 10);
      final glowPaint = Paint()
        ..shader = ui.Gradient.radial(Offset(celX, base - 10), W * 0.3, [
          const Color(0xFFB0BEC5).withValues(alpha: 0.12 * glowFactor),
          const Color(0x00000000),
        ]);
      canvas.drawRect(glowRect, glowPaint);
    }

    // 2. Один фиксированный ракурс Мекки. День, переходный свет и ночь
    // сделаны из одного мастера и совпадают по пикселям: архитектура не
    // «прыгает», плавно меняется только освещение.
    final nightImage = meccaNightImage;
    final twilightImage = meccaTwilightImage;
    final dayImage = meccaDayImage;
    if (nightImage != null && twilightImage != null && dayImage != null) {
      // V3 содержит не только полную Каабу, но и площадь до нижней кромки.
      // Нижнюю кромку совмещаем с краем первого экрана: под изображением не
      // остаётся ни прозрачной, ни цветной полосы.
      final dstWidth = W * 1.11;
      final dstHeight = dstWidth * (nightImage.height / nightImage.width);
      final destRect = Rect.fromLTWH(
        (W - dstWidth) / 2,
        base - dstHeight,
        dstWidth,
        dstHeight,
      );
      final sourceRect = Rect.fromLTWH(
        0,
        0,
        nightImage.width.toDouble(),
        nightImage.height.toDouble(),
      );

      double smoothStep(double edge0, double edge1, double value) {
        final x = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
        return x * x * (3 - 2 * x);
      }

      // Полдень даёт нейтральный фасад, у горизонта появляется тепло,
      // после Иша остаются только реальные огни арок, минаретов и башни.
      final dayBlend = smoothStep(0.32, 0.70, sky.day);
      final twilightBlend = smoothStep(0.04, 0.28, sky.day) * (1 - dayBlend);

      // Последние пиксели площади раньше заканчивались ровной границей
      // изображения и выдавали стык двух экранов. Растушёвываем только
      // нижние ~9% площади в уже нарисованный общий градиент; Кааба и
      // архитектура выше этой зоны остаются полностью резкими.
      canvas.saveLayer(destRect, Paint());
      canvas.drawImageRect(nightImage, sourceRect, destRect, Paint());
      if (twilightBlend > 0.001) {
        canvas.drawImageRect(
          twilightImage,
          sourceRect,
          destRect,
          Paint()..color = Colors.white.withValues(alpha: twilightBlend),
        );
      }
      if (dayBlend > 0.001) {
        canvas.drawImageRect(
          dayImage,
          sourceRect,
          destRect,
          Paint()..color = Colors.white.withValues(alpha: dayBlend),
        );
      }
      canvas.drawRect(
        destRect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.91, 1.0],
          ).createShader(destRect),
      );
      canvas.restore();
    }
  }

  void _nature(
    Canvas canvas,
    double width,
    double horizon,
    _Sky sky,
    double night,
    double celestialX,
    double celestialY,
    bool isDay,
    double altitude,
  ) {
    // Мягкое естественное свечение связывает горный горизонт с тем же
    // солнцем/луной, которое движется в остальных темах.
    final glowStrength = isDay
        ? (1 - altitude).clamp(0.0, 1.0) * .24
        : night * .10;
    // Свечение должно затухать самим радиальным градиентом. Ограничение его
    // прямоугольником от середины экрана давало заметную горизонтальную
    // границу, пока солнце проходило рядом с верхним краем этого прямоугольника.
    final glowRect = Rect.fromLTRB(0, 0, width, horizon + 12);
    canvas.drawRect(
      glowRect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(celestialX, min(celestialY, horizon - 8)),
          width * .58,
          [
            (isDay ? const Color(0xFFFFC77B) : const Color(0xFFB8C8DD))
                .withValues(alpha: glowStrength),
            Colors.transparent,
          ],
        ),
    );

    final image = natureImage;
    if (image != null) {
      // В исходнике верхняя часть прозрачна, а сам пейзаж занимает нижнюю
      // половину. Берём только полезную область и вписываем её с cover:
      // на телефоне сохраняется выразительная глубина долины, а на Fold
      // изображение заполняет широкую сцену без растяжения и пустых краёв.
      final source = Rect.fromLTRB(
        0,
        image.height * .47,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      // Пейзаж остаётся нижним акцентом и занимает не более 30% главного
      // экрана: основное пространство принадлежит небу, таймеру и действию.
      final destination = Rect.fromLTRB(0, horizon * .70, width, horizon + 10);
      final fitted = applyBoxFit(BoxFit.cover, source.size, destination.size);
      final sourceRect = Alignment.center.inscribe(fitted.source, source);
      final destinationRect = Alignment.center.inscribe(
        fitted.destination,
        destination,
      );

      // Нейтральный мастер получает освещение от живого неба приложения.
      // Днём сохраняются естественные оттенки, ночью детали остаются
      // различимыми, но уходят в холодный сине-зелёный тон.
      final nightTint = Color.lerp(
        Colors.white,
        const Color(0xFF456476),
        night * .72,
      )!;
      canvas.saveLayer(destination, Paint());
      canvas.drawImageRect(
        image,
        sourceRect,
        destinationRect,
        Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high
          ..colorFilter = ColorFilter.mode(nightTint, BlendMode.modulate),
      );
      canvas.drawRect(
        destination,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.white, Colors.white],
            stops: [0, .12, 1],
          ).createShader(destination),
      );
      canvas.restore();

      final shade = Rect.fromLTRB(0, horizon * .78, width, horizon + 10);
      canvas.drawRect(
        shade,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              const Color(0xFF071817).withValues(alpha: .12 + night * .24),
            ],
          ).createShader(shade),
      );

      // Земля продолжается под кадром: при свайпе вниз край пейзажа не
      // обрывается ровной линией, а мягко уходит в фон нижних экранов.
      // Цвет — средний тон нижнего края картинки с тем же ночным оттенком.
      final ground = Color.lerp(
        const Color(0xFF282512),
        const Color(0xFF101C20),
        night * .8,
      )!;
      final below = Rect.fromLTRB(0, horizon - 40, width, horizon * 1.45);
      final seam = 50 / below.height;
      canvas.drawRect(
        below,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              ground.withValues(alpha: 0),
              ground,
              ground.withValues(alpha: .55),
              ground.withValues(alpha: 0),
            ],
            stops: [0, seam, seam + .25, 1],
          ).createShader(below),
      );
    }

    // Тонкая атмосферная растушёвка не даёт пейзажу обрываться ровно по
    // границе экранов во время интерактивного свайпа.
    final veil = Rect.fromLTRB(0, horizon * .88, width, horizon + 10);
    canvas.drawRect(
      veil,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, sky.bottom.withValues(alpha: .18)],
        ).createShader(veil),
    );
  }

  void _minimalHorizon(
    Canvas canvas,
    double width,
    double horizon,
    _Sky sky,
    double night,
  ) {
    // В минимальной теме остаются только небо и свет. Небольшая дымка
    // визуально завершает первый экран, не превращаясь в объект или город.
    final rect = Rect.fromLTRB(0, horizon * .72, width, horizon + 8);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            sky.bottom.withValues(alpha: .10 + night * .08),
            const Color(0xFF071117).withValues(alpha: .08 + night * .12),
          ],
          stops: const [0, .72, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.nowSec != nowSec ||
      old.times != times ||
      old.meccaDayImage != meccaDayImage ||
      old.meccaTwilightImage != meccaTwilightImage ||
      old.meccaNightImage != meccaNightImage ||
      old.natureImage != natureImage ||
      old.variant != variant ||
      old.introVal != introVal ||
      old.shootingStarVal != shootingStarVal;
}
