import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Фирменный фон Дауам: тонкая сетка восьмиконечных звёзд и мягкое золотое
/// свечение. Общий для страниц ленты и листов настроек, чтобы всё выглядело
/// одним целым.
class OrnamentPainter extends CustomPainter {
  const OrnamentPainter({
    required this.line,
    required this.glow,
    this.shift = 0,
    this.glowCenter = const Offset(0.5, 0.26),
  });

  /// Цвет линий узора (очень прозрачный).
  final Color line;

  /// Цвет свечения; прозрачный — без свечения.
  final Color glow;

  /// Вертикальный сдвиг узора в пикселях — для параллакса при свайпе.
  final double shift;

  /// Центр свечения в долях размера.
  final Offset glowCenter;

  @override
  void paint(Canvas canvas, Size size) {
    if (glow.a > 0) {
      final center = Offset(
        size.width * glowCenter.dx,
        size.height * glowCenter.dy,
      );
      final r = size.width * 0.78;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [glow, glow.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    final step = size.width / 4;
    final radius = step * 0.28;
    final rowStep = step * 0.9;
    final offsetY = shift % rowStep;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = line;
    for (var row = -1; row * rowStep < size.height + step; row++) {
      final cy = row * rowStep + offsetY;
      final offsetX = row.isOdd ? step / 2 : 0.0;
      for (var i = -1; i <= 4; i++) {
        final center = Offset(i * step + offsetX, cy);
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
  bool shouldRepaint(OrnamentPainter o) =>
      o.line != line ||
      o.glow != glow ||
      o.shift != shift ||
      o.glowCenter != glowCenter;
}
