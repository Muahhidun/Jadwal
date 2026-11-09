import 'package:flutter/material.dart';
import '../data/app_state.dart';
import '../theme/tokens.dart';

/// Transparent gesture demonstration. Only the small caption receives taps;
/// the real page receives the swipe. No dimmer or fake navigation controls.
class SwipeLesson extends StatefulWidget {
  const SwipeLesson({
    super.key,
    required this.message,
    required this.up,
    required this.onOpen,
  });
  final String message;
  final bool up;
  final VoidCallback onOpen;
  @override
  State<SwipeLesson> createState() => _SwipeLessonState();
}

class _SwipeLessonState extends State<SwipeLesson>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
      _motion.value = .5;
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), c = JColors.light;
    final kz = app.lang == 'kz';
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Align(
                alignment: const Alignment(0, .12),
                child: AnimatedBuilder(
                  animation: _motion,
                  builder: (context, _) {
                    final t = _motion.value;
                    final travel = Curves.easeInOut.transform(
                      (t / .78).clamp(0.0, 1.0),
                    );
                    final opacity = t < .15
                        ? t / .15
                        : t > .8
                        ? (1 - t) / .2
                        : 1.0;
                    return Transform.translate(
                      offset: Offset(
                        0,
                        (widget.up ? 1 : -1) * (64 - 128 * travel),
                      ),
                      child: Opacity(
                        key: const ValueKey('guide-swipe-hand'),
                        opacity: opacity.clamp(0.0, 1.0) * .55,
                        child: const Icon(
                          Icons.touch_app_outlined,
                          size: 92,
                          color: Color(0xFFFFF8E7),
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 6),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: MediaQuery.paddingOf(context).bottom + 20,
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Material(
              key: const ValueKey('guide-swipe-caption'),
              color: c.bg.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.message,
                      style: JType.ui(14, color: c.ink, h: 1.35),
                    ),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: c.ink,
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: widget.onOpen,
                          child: Text(
                            kz ? 'Батырмамен ашу' : 'Открыть кнопкой',
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: c.ink,
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: app.closeNavigationGuide,
                          child: Text(
                            kz ? 'Өткізу' : 'Пропустить',
                            semanticsLabel: kz
                                ? 'Үйретуді өткізу'
                                : 'Пропустить обучение',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
