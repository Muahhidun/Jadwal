import 'dart:math';
import 'package:flutter/material.dart';

/// Художественный фон высотой на два экрана: вверху — ночь (глубокий зелёный
/// с звёздами и полумесяцем), внизу — рассвет (тёплый золотой горизонт).
/// Сдвигается вместе с прокруткой (параллакс) → ощущение длинной страницы.
/// Позже фоны станут сменяемыми в настройках темы (фото/градиенты/цвета).
class SceneBackground extends StatelessWidget {
  const SceneBackground({super.key, required this.progress, required this.screenHeight});

  /// 0 — виден верх (главный), 1 — низ (день).
  final double progress;
  final double screenHeight;

  @override
  Widget build(BuildContext context) {
    // Фон едет чуть медленнее контента (параллакс, глубина).
    final dy = -progress * screenHeight * 0.7;
    return Positioned(
      left: 0,
      right: 0,
      top: dy,
      height: screenHeight * 2,
      child: RepaintBoundary(
        child: CustomPaint(painter: _ScenePainter(), size: Size.infinite),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    // Вертикальный градиент: ночь → предрассветная синь → золотой горизонт.
    final rect = Offset.zero & size;
    final grad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [
        Color(0xFF0B1512), // глубокая ночь
        Color(0xFF0F1B16),
        Color(0xFF14201B),
        Color(0xFF1A241D), // предрассвет
        Color(0xFF2A2A1C), // тёплый переход (приглушён)
        Color(0xFF3E351F), // сдержанный золотой горизонт
        Color(0xFF181409), // земля под горизонтом
      ],
      stops: const [0.0, 0.2, 0.38, 0.54, 0.7, 0.86, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = grad.createShader(rect));

    // Звёзды в верхней (ночной) половине.
    final rnd = Random(42);
    final star = Paint()..color = const Color(0xFFECE9DF);
    for (var i = 0; i < 60; i++) {
      final y = rnd.nextDouble() * h * 0.42;
      final x = rnd.nextDouble() * size.width;
      final r = rnd.nextDouble() * 1.1 + 0.3;
      star.color = const Color(0xFFECE9DF).withValues(alpha: rnd.nextDouble() * 0.6 + 0.15);
      canvas.drawCircle(Offset(x, y), r, star);
    }

    // Полумесяц вверху справа.
    final moonC = Offset(size.width * 0.78, h * 0.12);
    const moonR = 26.0;
    final moon = Paint()..color = const Color(0xFFD9C48A).withValues(alpha: 0.9);
    canvas.drawCircle(moonC, moonR, moon);
    // Вырезаем полумесяц наложением фонового цвета.
    canvas.drawCircle(Offset(moonC.dx + 11, moonC.dy - 6), moonR,
        Paint()..color = const Color(0xFF0F1B16));

    // Мягкое золотое свечение у горизонта (~0.86h), сдержанное.
    final glowRect = Rect.fromLTRB(0, h * 0.76, size.width, h * 0.94);
    final glow = RadialGradient(
      center: Alignment.center,
      radius: 0.9,
      colors: [
        const Color(0xFFE8BC6A).withValues(alpha: 0.18),
        const Color(0xFFE8BC6A).withValues(alpha: 0.0),
      ],
    );
    canvas.drawRect(glowRect, Paint()..shader = glow.createShader(glowRect));

    // Затемнение у самого верха — читаемость шапки (город/дата) на звёздах.
    final topRect = Rect.fromLTRB(0, 0, size.width, h * 0.09);
    final topScrim = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF000000).withValues(alpha: 0.35),
        const Color(0xFF000000).withValues(alpha: 0.0),
      ],
    );
    canvas.drawRect(topRect, Paint()..shader = topScrim.createShader(topRect));
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) => false;
}
