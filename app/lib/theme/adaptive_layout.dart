import 'package:flutter/widgets.dart';

/// Foldable/tablet layout is selected from the current logical viewport, not
/// from a device model. This keeps the UI correct when a Fold is opened,
/// closed, rotated, or used in multi-window mode.
// 620 keeps ordinary 600-dp landscape phones in the compact composition,
// while unfolded Galaxy Fold screens (typically ~670 dp+) use the expanded
// composition.
const double expandedLayoutBreakpoint = 620;

bool isExpandedLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= expandedLayoutBreakpoint;

double adaptiveValue(
  BuildContext context, {
  required double compact,
  required double expanded,
}) => isExpandedLayout(context) ? expanded : compact;

/// Centers primary controls and reading content on very wide displays while
/// allowing backgrounds and gesture surfaces to continue filling the screen.
class AdaptiveContentPane extends StatelessWidget {
  const AdaptiveContentPane({
    super.key,
    required this.child,
    this.expandedMaxWidth = 760,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double expandedMaxWidth;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (!isExpandedLayout(context)) return child;
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: expandedMaxWidth),
        child: child,
      ),
    );
  }
}
