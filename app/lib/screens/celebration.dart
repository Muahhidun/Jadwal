import 'dart:math';
import 'package:flutter/material.dart';
import '../data/app_state.dart';
import '../i18n/strings.dart';
import '../theme/tokens.dart';

/// Празднование (README §5): сдержанное — галочка, лёгкий салют,
/// случайный хадис с источником. Без очков и конфетти-вечеринки.
class CelebrationScreen extends StatefulWidget {
  const CelebrationScreen({super.key, required this.collectionId});
  final String collectionId;

  @override
  State<CelebrationScreen> createState() => _CelebrationScreenState();
}

class _CelebrationScreenState extends State<CelebrationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
        ..forward();
  final int quoteIdx = Random().nextInt(3);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = S.of(app.lang);
    final quote = s.quotes[quoteIdx];
    final title =
        widget.collectionId == 'morning' ? s.doneTitleMorning : s.doneTitleEvening;

    final pop = CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0, .25, curve: Curves.elasticOut));
    final fadeIn = CurvedAnimation(
        parent: _ctrl, curve: const Interval(.3, .6, curve: Curves.easeOut));

    return Scaffold(
      backgroundColor: JPaper.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _Confetti(ctrl: _ctrl),
                    ScaleTransition(
                      scale: pop,
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Color(0xFF4A5D50)),
                        child: const Icon(Icons.check, size: 44, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              FadeTransition(
                opacity: fadeIn,
                child: Column(
                  children: [
                    Text(title,
                        textAlign: TextAlign.center,
                        style: JType.ui(24, w: FontWeight.w800, color: JPaper.ink)),
                    const SizedBox(height: 24),
                    Text(quote.text,
                        textAlign: TextAlign.center,
                        style: JType.reading(16,
                            color: JPaper.ink, style: FontStyle.italic, h: 1.6)),
                    const SizedBox(height: 8),
                    Text(quote.src, style: JType.ui(12, color: JPaper.source)),
                    const SizedBox(height: 28),
                    Text(s.doneSub, style: JType.caption(JPaper.accent, size: 10)),
                  ],
                ),
              ),
              const Spacer(flex: 3),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                      color: JPaper.button, borderRadius: BorderRadius.circular(100)),
                  child: Center(
                    child: Text(s.back,
                        style: JType.ui(15, w: FontWeight.w700, color: JPaper.bg)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ~16 частиц 5–9px, разлёт радиально с вращением и затуханием (README).
class _Confetti extends StatelessWidget {
  const _Confetti({required this.ctrl});
  final AnimationController ctrl;

  static const _colors = [
    Color(0xFFC99A3F),
    Color(0xFF4A5D50),
    Color(0xFF8C7A4E),
    Color(0xFFB4544A),
    Color(0xFFE8BC6A),
  ];

  @override
  Widget build(BuildContext context) {
    final rnd = Random(7);
    final particles = [
      for (var i = 0; i < 16; i++)
        (
          angle: i / 16 * 2 * pi + rnd.nextDouble() * .3,
          dist: 90.0 + rnd.nextDouble() * 100,
          size: 5.0 + rnd.nextDouble() * 4,
          color: _colors[i % _colors.length],
          delay: .16 + rnd.nextDouble() * .1,
          span: .4 + rnd.nextDouble() * .23,
        ),
    ];
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, _) => CustomPaint(
        size: const Size(140, 140),
        painter: _ConfettiPainter(particles, ctrl.value),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.t);
  final List<({double angle, double dist, double size, Color color, double delay, double span})>
      particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 20);
    for (final p in particles) {
      final local = ((t - p.delay) / p.span).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final eased = Curves.easeOut.transform(local);
      final pos = center + Offset(cos(p.angle), sin(p.angle)) * (p.dist * eased);
      final paint = Paint()..color = p.color.withValues(alpha: 1 - local);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(local * 9.7);
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
