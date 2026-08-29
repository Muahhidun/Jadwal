import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum SwipeHintDirection { up, down }

/// Единая ненавязчивая подсказка вертикальной навигации для трёхэкранной
/// ленты. Направление анимации совпадает с направлением требуемого жеста.
class SwipeHint extends StatefulWidget {
  const SwipeHint({
    super.key,
    required this.label,
    required this.direction,
    required this.color,
    this.shadows = const [],
    this.onTap,
  });

  final String label;
  final SwipeHintDirection direction;
  final Color color;
  final List<Shadow> shadows;
  final VoidCallback? onTap;

  @override
  State<SwipeHint> createState() => _SwipeHintState();
}

class _SwipeHintState extends State<SwipeHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..repeat();

  late Animation<double> _offset = _makeOffset();

  Animation<double> _makeOffset() {
    final sign = widget.direction == SwipeHintDirection.up ? -1.0 : 1.0;
    return TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0), weight: 72),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 8.0 * sign,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 6,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 8.0 * sign,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 6,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 4.0 * sign,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 6,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 4.0 * sign,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 6,
      ),
      TweenSequenceItem(tween: ConstantTween(0), weight: 4),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant SwipeHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.direction != widget.direction) {
      _offset = _makeOffset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = AnimatedBuilder(
      animation: _offset,
      builder: (_, child) =>
          Transform.translate(offset: Offset(0, _offset.value), child: child),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.label,
            style: JType.ui(
              11,
              color: widget.color,
            ).copyWith(shadows: widget.shadows),
          ),
        ],
      ),
    );

    if (widget.onTap == null) return content;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}
