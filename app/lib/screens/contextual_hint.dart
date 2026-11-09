import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../theme/tokens.dart';

/// Одноразовая подсказка к реальному элементу. Не появляется поверх другого
/// окна или первого онбординга, не меняет настройки и не запускает действие.
class ContextualHint extends StatefulWidget {
  const ContextualHint({
    super.key,
    required this.id,
    required this.title,
    required this.message,
    required this.child,
    this.enabled = true,
  });

  final String id, title, message;
  final Widget child;
  final bool enabled;

  @override
  State<ContextualHint> createState() => _ContextualHintState();
}

class _ContextualHintState extends State<ContextualHint> {
  static bool _hintOpen = false;
  final _target = GlobalKey();
  Timer? _timer;
  Animation<double>? _routeAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = ModalRoute.of(context)?.animation;
    _routeAnimation?.addStatusListener(_onRouteStatus);
    _schedule();
  }

  @override
  void didUpdateWidget(ContextualHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final app = AppScope.of(context);
    if (!widget.enabled ||
        app.navigationGuide.active ||
        !app.onboardingDone ||
        app.contextHintSeen(widget.id)) {
      return;
    }
    _timer = Timer(const Duration(milliseconds: 350), _show);
  }

  Future<void> _show() async {
    if (!mounted || _hintOpen || !widget.enabled) return;
    final app = AppScope.of(context);
    if (!app.onboardingDone ||
        app.navigationGuide.active ||
        app.contextHintSeen(widget.id)) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route?.isCurrent != true ||
        (route?.animation != null &&
            route!.animation!.status != AnimationStatus.completed)) {
      return;
    }
    final box = _target.currentContext?.findRenderObject();
    final navigator = Navigator.of(context, rootNavigator: true);
    final overlayBox = navigator.overlay?.context.findRenderObject();
    if (box is! RenderBox || overlayBox is! RenderBox || !box.hasSize) return;
    final target =
        box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
    final media = MediaQuery.of(context);
    final viewport = Offset.zero & media.size;
    if (!viewport.contains(target.topLeft) ||
        !viewport.contains(target.bottomRight - const Offset(1, 1))) {
      return;
    }
    final kz = app.lang == 'kz';
    _hintOpen = true;
    try {
      await showGeneralDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: true,
        barrierLabel: kz ? 'Нұсқауды жабу' : 'Закрыть подсказку',
        barrierColor: const Color(0x66000000),
        transitionDuration: media.disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 180),
        transitionBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (dialogContext, _, _) => Stack(
          children: [
            Positioned.fromRect(
              rect: target.inflate(4),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFFFDF91),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            CustomSingleChildLayout(
              delegate: _HintPosition(target, media.padding, media.viewInsets),
              child: _HintBubble(
                title: widget.title,
                message: widget.message,
                target: target,
                kz: kz,
                onClose: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        ),
      );
      app.markContextHintSeen(widget.id);
    } finally {
      _hintOpen = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(key: _target, child: widget.child);
}

class _HintPosition extends SingleChildLayoutDelegate {
  const _HintPosition(this.target, this.padding, this.insets);
  final Rect target;
  final EdgeInsets padding, insets;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.min(340, math.max(0, constraints.maxWidth - 32)),
        maxHeight: math.max(
          0,
          constraints.maxHeight - padding.vertical - insets.bottom - 32,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final top = padding.top + 16;
    final bottom = size.height - padding.bottom - insets.bottom - 16;
    final below = target.bottom + 16;
    final y = below + childSize.height <= bottom
        ? below
        : target.top - childSize.height - 16;
    return Offset(
      (target.center.dx - childSize.width / 2)
          .clamp(16, math.max(16, size.width - childSize.width - 16))
          .toDouble(),
      y.clamp(top, math.max(top, bottom - childSize.height)).toDouble(),
    );
  }

  @override
  bool shouldRelayout(_HintPosition oldDelegate) =>
      target != oldDelegate.target ||
      padding != oldDelegate.padding ||
      insets != oldDelegate.insets;
}

class _HintBubble extends StatelessWidget {
  const _HintBubble({
    required this.title,
    required this.message,
    required this.target,
    required this.kz,
    required this.onClose,
  });
  final String title, message;
  final Rect target;
  final bool kz;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('contextual-hint-bubble'),
    color: const Color(0xFFFFFBF2),
    elevation: 8,
    borderRadius: BorderRadius.circular(20),
    child: CustomPaint(
      foregroundPainter: _HintArrow(target, () {
        final box = context.findRenderObject();
        return box is RenderBox ? box.localToGlobal(Offset.zero) : Offset.zero;
      }),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: JType.ui(
                  18,
                  w: FontWeight.w700,
                  color: const Color(0xFF28323A),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: JType.ui(14.5, h: 1.45, color: const Color(0xFF47545E)),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onClose,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF8F650F),
                ),
                child: Text(
                  kz ? 'Түсінікті' : 'Понятно',
                  style: JType.ui(14.5, w: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _HintArrow extends CustomPainter {
  const _HintArrow(this.target, this.origin);
  final Rect target;
  final Offset Function() origin;

  @override
  void paint(Canvas canvas, Size size) {
    // Позиция пузыря определяется по реальному размеру текста, поэтому
    // направление стрелки вычисляем после раскладки, без фиксированных высот.
    final offset = origin();
    final below = offset.dy >= target.bottom;
    final x = (target.center.dx - offset.dx)
        .clamp(18.0, size.width - 18)
        .toDouble();
    final y = below ? 0.0 : size.height;
    final path = Path()
      ..moveTo(x - 9, y)
      ..lineTo(x, y + (below ? -9 : 9))
      ..lineTo(x + 9, y)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFFBF2));
  }

  @override
  bool shouldRepaint(_HintArrow oldDelegate) => target != oldDelegate.target;
}
