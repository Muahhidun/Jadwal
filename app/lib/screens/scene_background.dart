import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../prayer/schedule.dart';

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
  });

  final double progress; // 0 — главный (небо), 1 — «день» (город внизу)
  final double screenHeight;
  final DayTimes times;
  final int nowSec;

  @override
  State<SceneBackground> createState() => _SceneBackgroundState();
}

class _SceneBackgroundState extends State<SceneBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _startX = 0;
  double _startY = 0;
  double _len = 80;
  ui.Image? _meccaImage;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    if (widget.nowSec % 24 == 0) {
      _startShootingStar();
    }
    _loadMeccaImage();
  }

  Future<void> _loadMeccaImage() async {
    try {
      final data = await rootBundle.load('assets/images/mecca_silhouette.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _meccaImage = frame.image;
        });
      }
    } catch (e) {
      debugPrint("Error loading mecca image: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SceneBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.nowSec != oldWidget.nowSec && widget.nowSec % 24 == 0) {
      _startShootingStar();
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
    final dy = -widget.progress * widget.screenHeight;
    return Positioned(
      left: 0,
      right: 0,
      top: dy,
      height: widget.screenHeight * 2,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _ScenePainter(
                times: widget.times,
                nowSec: widget.nowSec,
                shootingStarVal: _controller.value,
                startX: _startX,
                startY: _startY,
                len: _len,
                meccaImage: _meccaImage,
              ),
              size: Size.infinite,
            );
          },
        ),
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
    _SkyKey((fajr + sun) ~/ 2, const Color(0xFF2A3560), const Color(0xFF9A6E7A), 0.18),
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

/// Днём — тёмный текст, ночью — светлый. Без бледных промежуточных цветов:
/// на пёстром небе (закат/рассвет) они нечитаемы. Вместо этого — жёсткий
/// выбор день/ночь + мягкая контрастная тень, сильнее всего в переходные фазы.
SkyFg skyForeground(DayTimes t, int nowSec) {
  final sky = _skyAt(t, nowSec ~/ 60);
  
  // Вычисляем примерный цвет неба позади текста (верхняя треть экрана)
  final textBgColor = Color.lerp(sky.top, sky.bottom, 0.25)!;
  final bgLuminance = textBgColor.computeLuminance();
  
  // Если фон светлый (яркость > 0.43), используем темный контрастный текст.
  // Иначе — светлый контрастный текст.
  final useDarkText = bgLuminance > 0.43;
  
  // Тени полностью убираем по запросу пользователя
  const shadows = <Shadow>[];
  
  return useDarkText
      ? SkyFg(const Color(0xFF1B2230), const Color(0xFF3A4657),
          const Color(0xFF8A5F10), shadows)
      : SkyFg(const Color(0xFFF2EFE6), const Color(0xFFC9CDC2),
          const Color(0xFFE2B85E), shadows);
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
    this.meccaImage,
  });
  final DayTimes times;
  final int nowSec;
  final double shootingStarVal;
  final double startX;
  final double startY;
  final double len;
  final ui.Image? meccaImage;

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width, H = size.height;
    final horizon = H * 0.5; // низ главного экрана / линия горизонта
    final nowMin = nowSec ~/ 60;
    final sky = _skyAt(times, nowMin);
    final night = (1 - sky.day * 2).clamp(0.0, 1.0); // 1 глубокая ночь … 0 день

    // Небо
    final skyRect = Rect.fromLTRB(0, 0, W, horizon);
    canvas.drawRect(
        skyRect,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [sky.top, sky.bottom])
              .createShader(skyRect));

    // Звёзды и падающая звезда — ночью
    if (night > 0.15) {
      _stars(canvas, W, horizon, night);
      _shootingStar(canvas, night);
    }

    // Вычисляем координаты солнца/луны для совместного использования в _celestial и _city
    final sun = times.times[Prayer.sunrise]!;
    final dhuhr = times.times[Prayer.dhuhr]!;
    final magh = times.times[Prayer.maghrib]!;
    final isDay = nowMin >= sun && nowMin <= magh;
    
    double fracX, alt; // alt: 0 у горизонта … 1 зенит
    if (isDay) {
      if (nowMin <= dhuhr) {
        final f = (nowMin - sun) / max(1, dhuhr - sun);
        fracX = 0.12 + f * 0.38;
        alt = f;
      } else {
        final f = (nowMin - dhuhr) / max(1, magh - dhuhr);
        fracX = 0.5 + f * 0.38;
        alt = 1.0 - f;
      }
    } else {
      final total = (1440 - magh) + sun;
      final nm = nowMin >= magh ? nowMin - magh : nowMin + (1440 - magh);
      final f = nm / max(1, total);
      fracX = 0.12 + f * 0.76;
      alt = sin(f * pi);
    }
    final cx = W * fracX;
    final cy = horizon * 0.92 - alt * horizon * 0.78;

    // Земля/город ниже горизонта
    final groundTop = Color.lerp(sky.bottom, const Color(0xFF0B0F1C), 0.55)!;
    final groundBot = Color.lerp(const Color(0xFF0B0F1C), const Color(0xFF05070E), 0.6)!;
    final groundRect = Rect.fromLTRB(0, horizon, W, H);
    canvas.drawRect(
        groundRect,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [groundTop, groundBot])
              .createShader(groundRect));

    // Затемнение к низу — читаемость карточек «дня» (рисуется под солнцем и городом, чтобы не резать солнце)
    final scrim = Rect.fromLTRB(0, horizon, W, H);
    canvas.drawRect(
        scrim,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0x000B1512),
                    const Color(0xCC0B1512),
                  ])
              .createShader(scrim));

    // Солнце / луна по дуге (рисуются поверх земли и затемнения, чтобы не срезаться прямой линией горизонта)
    _celestial(canvas, cx, cy, horizon, isDay);

    // Силуэт дюн на горизонте с динамической физикой освещения
    _city(canvas, W, horizon, H, sky, night, cx, cy, isDay, alt);
  }

  void _stars(Canvas canvas, double W, double horizon, double night) {
    final rnd = Random(7);
    final p = Paint()..color = Colors.white;
    for (var i = 0; i < 90; i++) {
      final x = rnd.nextDouble() * W;
      final y = rnd.nextDouble() * horizon * 0.85;
      final tw = 0.4 + 0.6 * (0.5 + 0.5 * sin((nowSec / 3 + i) * 0.7));
      p.color = Colors.white.withValues(alpha: (0.15 + rnd.nextDouble() * 0.5) * night * tw);
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
      ..shader = ui.Gradient.linear(
        head,
        tail,
        [
          Colors.white.withValues(alpha: a),
          Colors.white.withValues(alpha: 0.0),
        ],
      );

    canvas.drawLine(head, tail, paint);
  }

  void _celestial(Canvas canvas, double cx, double cy, double horizon, bool isDay) {
    if (isDay) {
      // солнце с мягким свечением
      final glow = Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFFFFF3C8).withValues(alpha: 0.85),
          const Color(0xFFFFE29A).withValues(alpha: 0.0)
        ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: horizon * 0.22));
      canvas.drawCircle(Offset(cx, cy), horizon * 0.22, glow);
      canvas.drawCircle(Offset(cx, cy), horizon * 0.06, Paint()..color = const Color(0xFFFFF0C0));
    } else {
      final glow = Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFFE9E2C2).withValues(alpha: 0.35),
          const Color(0xFFE9E2C2).withValues(alpha: 0.0)
        ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: horizon * 0.16));
      canvas.drawCircle(Offset(cx, cy), horizon * 0.16, glow);
      final r = horizon * 0.052;
      final path1 = Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      final path2 = Path()..addOval(Rect.fromCircle(center: Offset(cx + r * 0.55, cy - r * 0.25), radius: r));
      final crescent = Path.combine(PathOperation.difference, path1, path2);
      canvas.drawPath(crescent, Paint()..color = const Color(0xFFDCCB8E));
    }
  }

  void _city(Canvas canvas, double W, double horizon, double H, _Sky sky, double night, double celX, double celY, bool isDay, double alt) {
    // Гарантированный контраст силуэта с небом в ЛЮБОЙ фазе (жалоба владельца:
    // «иногда видна, иногда нет»): по яркости неба за ним выбираем тёмный
    // силуэт (светлое небо) или тёплый светлый (тёмное небо), с плавным
    // переходом в сумерках — дельта яркости сохраняется всегда.
    final bgLum = sky.bottom.computeLuminance();
    final tt = ((bgLum - 0.08) / 0.22).clamp(0.0, 1.0);
    final darkSil = Color.lerp(sky.bottom, const Color(0xFF06080F), 0.85)!;
    final lightSil = Color.lerp(sky.bottom, const Color(0xFF9A8262), 0.75)!;
    final sil = Color.lerp(lightSil, darkSil, tt)!;
    final base = horizon;
    final silOpacity = 1.0;

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
        ..shader = ui.Gradient.radial(
          Offset(celX, base - 10),
          W * 0.3,
          [
            const Color(0xFFB0BEC5).withValues(alpha: 0.12 * glowFactor),
            const Color(0x00000000),
          ],
        );
      canvas.drawRect(glowRect, glowPaint);
    }

    // 2. Мягкие фоновые дюны пустыни позади города для создания глубины горизонта (5-8% высоты)
    final d1Color = Color.lerp(sky.bottom, const Color(0xFF070B14), 0.45)!;
    final path1 = Path()
      ..moveTo(0, base)
      ..quadraticBezierTo(W * 0.35, base - 25, W * 0.7, base - 8)
      ..quadraticBezierTo(W * 0.85, base - 2, W, base - 4)
      ..lineTo(W, base + 20)
      ..lineTo(0, base + 20)
      ..close();
    canvas.drawPath(path1, Paint()..color = d1Color);

    final d2Color = Color.lerp(sky.bottom, const Color(0xFF070B14), 0.58)!;
    final path2 = Path()
      ..moveTo(0, base - 4)
      ..quadraticBezierTo(W * 0.2, base - 6, W * 0.45, base - 18)
      ..quadraticBezierTo(W * 0.75, base - 32, W, base - 10)
      ..lineTo(W, base + 30)
      ..lineTo(0, base + 30)
      ..close();
    canvas.drawPath(path2, Paint()..color = d2Color);

    // 3. Рисунок города Мекка из ассета с наложением динамического тонирования и светящимися часами
    if (meccaImage != null) {
      final dstWidth = W;
      final dstHeight = W * (meccaImage!.height / meccaImage!.width);
      final destRect = Rect.fromLTWH(0, base - dstHeight + 2, dstWidth, dstHeight);
      
      final silPaint = Paint()
        ..colorFilter = ColorFilter.mode(sil.withValues(alpha: silOpacity), BlendMode.srcIn);
      canvas.drawImageRect(
        meccaImage!,
        Rect.fromLTWH(0, 0, meccaImage!.width.toDouble(), meccaImage!.height.toDouble()),
        destRect,
        silPaint,
      );

      // Рисуем светящиеся зеленые (ночью) или золотые (днем) часы на башне по центру
      final clockX = W * 0.5;
      final clockY = (base - dstHeight) + (80 / 258) * dstHeight;
      final clockRadius = dstWidth * (4.5 / 580);
      
      final clockColor = isDay 
          ? const Color(0xFFFFF9C4) 
          : const Color(0xFF4CAF50).withValues(alpha: 0.2 + 0.8 * night);
      
      canvas.drawCircle(
        Offset(clockX, clockY),
        clockRadius,
        Paint()..color = clockColor..style = PaintingStyle.fill,
      );

      // Рисуем светящиеся золотистые окошки в зданиях ночью (эффект ночного живого города)
      if (night > 0.1) {
        final winPaint = Paint()
          ..color = const Color(0xFFFFEE58).withValues(
              alpha: (0.2 + 0.6 * (0.5 + 0.5 * sin(nowSec * 0.15))) * night);
        
        // Координаты окон подобраны под отельные крылья вокруг часовой башни
        final windowPositions = [
          // Левое крыло отеля
          Offset(W * 0.41, base - dstHeight * 0.18),
          Offset(W * 0.41, base - dstHeight * 0.26),
          Offset(W * 0.41, base - dstHeight * 0.34),
          Offset(W * 0.44, base - dstHeight * 0.20),
          Offset(W * 0.44, base - dstHeight * 0.28),
          Offset(W * 0.44, base - dstHeight * 0.36),
          Offset(W * 0.44, base - dstHeight * 0.44),
          
          // Правое крыло отеля
          Offset(W * 0.56, base - dstHeight * 0.20),
          Offset(W * 0.56, base - dstHeight * 0.28),
          Offset(W * 0.56, base - dstHeight * 0.36),
          Offset(W * 0.56, base - dstHeight * 0.44),
          Offset(W * 0.59, base - dstHeight * 0.18),
          Offset(W * 0.59, base - dstHeight * 0.26),
          Offset(W * 0.59, base - dstHeight * 0.34),
          
          // Мелкие огоньки в остальных зданиях Мекки
          Offset(W * 0.25, base - dstHeight * 0.15),
          Offset(W * 0.32, base - dstHeight * 0.12),
          Offset(W * 0.68, base - dstHeight * 0.14),
          Offset(W * 0.74, base - dstHeight * 0.11),
        ];

        for (final pos in windowPositions) {
          canvas.drawRect(
            Rect.fromCenter(center: pos, width: 2.2, height: 3.2),
            winPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.nowSec != nowSec || old.times != times || old.meccaImage != meccaImage;
}
