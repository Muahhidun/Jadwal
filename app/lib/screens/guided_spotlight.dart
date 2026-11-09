import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/app_state.dart';
import '../data/navigation_guide.dart';
import '../theme/tokens.dart';

/// A hole in the dimmer lets the real widget receive taps and drags.
/// Like WeDrink's training spotlight, no copied/fake controls are used.
class GuidedSpotlight extends StatefulWidget {
  const GuidedSpotlight({
    super.key,
    required this.title,
    required this.message,
    this.target,
    this.gesture = false,
    this.up = true,
    this.action,
    this.onAction,
    this.secondary,
    this.onSecondary,
    this.compact = false,
    this.allowBackgroundInteraction = false,
  });
  final String title, message;
  final GlobalKey? target;
  final bool gesture, up;
  final bool compact;

  /// Used by the map lesson: its real pan/pinch controls remain usable.
  final bool allowBackgroundInteraction;
  final String? action, secondary;
  final VoidCallback? onAction, onSecondary;
  @override
  State<GuidedSpotlight> createState() => _GuidedSpotlightState();
}

class _GuidedSpotlightState extends State<GuidedSpotlight> {
  Rect? _rect;
  Timer? _timer;
  int _missingTargetTicks = 0;
  final _focus = FocusScopeNode(debugLabel: 'Dauam learning');
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _measure(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(GuidedSpotlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _rect = null;
      _missingTargetTicks = 0;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final root = context.findRenderObject();
    final box = widget.target?.currentContext?.findRenderObject();
    Rect? rect;
    if (root is RenderBox && box is RenderBox && box.attached && box.hasSize) {
      rect =
          MatrixUtils.transformRect(
                box.getTransformTo(root),
                Offset.zero & box.size,
              )
              .inflate(5)
              // Leave room for the stroke itself: an edge-to-edge footer must
              // not cut the outline in half at the screen boundary.
              .intersect((Offset.zero & root.size).deflate(2));
      if (rect.isEmpty) rect = null;
    }
    if (widget.target != null && rect == null) {
      _missingTargetTicks++;
      if (_missingTargetTicks == 8) setState(() {});
    } else {
      _missingTargetTicks = 0;
    }
    if (rect != _rect) setState(() => _rect = rect);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), c = JColors.light;
    final kz = app.lang == 'kz';
    return LayoutBuilder(
      builder: (context, box) {
        final padding = MediaQuery.paddingOf(context);
        final safeTop = padding.top + 12;
        final safeBottom = box.maxHeight - padding.bottom - 12;
        final hole = _rect;
        final skipLabel = kz ? 'Үйретуді өткізу' : 'Пропустить обучение';
        if (widget.target != null && hole == null) {
          return BlockSemantics(
            child: Stack(
              children: [
                const Positioned.fill(
                  child: AbsorbPointer(child: SizedBox.expand()),
                ),
                if (_missingTargetTicks >= 8)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: padding.bottom + 12,
                    child: Material(
                      color: c.bg,
                      borderRadius: BorderRadius.circular(20),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: c.ink,
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: app.closeNavigationGuide,
                        child: Text(skipLabel),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        final stacked =
            box.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(14) > 18;
        final footerHeight =
            (stacked && widget.action != null ? 96.0 : 48.0) +
            (widget.secondary == null ? 0 : 48) +
            20;
        const gap = 12.0;
        final aboveSpace = hole == null ? 0.0 : hole.top - gap - safeTop;
        final belowSpace = hole == null ? 0.0 : safeBottom - hole.bottom - gap;
        final above = hole != null && aboveSpace > belowSpace;
        final room = above ? aboveSpace : belowSpace;
        // Accessibility sizes can turn a popover into a sheet. Keep the actions
        // pinned; never crop the Skip button inside the text viewport.
        final sheet = hole == null || room < footerHeight + 72;
        final maxHeight = sheet
            ? math.min(
                safeBottom - safeTop,
                math.max(280.0, box.maxHeight * .65),
              )
            : room;
        Widget skip() => TextButton(
          key: const ValueKey('guide-skip'),
          style: TextButton.styleFrom(
            foregroundColor: c.ink,
            minimumSize: const Size(48, 48),
          ),
          onPressed: app.closeNavigationGuide,
          child: Text(
            widget.compact ? (kz ? 'Өткізу' : 'Пропустить') : skipLabel,
            semanticsLabel: skipLabel,
          ),
        );
        Widget primary() => FilledButton(
          autofocus: true,
          style: FilledButton.styleFrom(
            backgroundColor: c.ink,
            foregroundColor: c.bg,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          onPressed: widget.onAction,
          child: Text(widget.action!, textAlign: TextAlign.center),
        );
        final actionRow = stacked
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [if (widget.action != null) primary(), skip()],
              )
            : Row(
                children: [
                  if (widget.action != null) Expanded(child: primary()),
                  Expanded(child: skip()),
                ],
              );

        return BlockSemantics(
          child: FocusScope(
            node: _focus,
            autofocus: true,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    excludeFromSemantics: true,
                    behavior: HitTestBehavior.deferToChild,
                    onTap: () {},
                    onVerticalDragStart: (_) {},
                    onVerticalDragUpdate: (_) {},
                    onVerticalDragEnd: (_) {},
                    onHorizontalDragUpdate: (_) {},
                    child: CustomPaint(
                      painter: _GuideMask(
                        hole,
                        widget.gesture || widget.allowBackgroundInteraction
                            ? Rect.fromLTRB(
                                24,
                                safeTop,
                                box.maxWidth - 24,
                                safeBottom,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  top: !sheet && !above ? hole.bottom + gap : null,
                  bottom: sheet
                      ? padding.bottom + 12
                      : above
                      ? box.maxHeight - hole.top + gap
                      : null,
                  child: Semantics(
                    container: true,
                    liveRegion: true,
                    child: Material(
                      key: const ValueKey('guide-bubble'),
                      color: c.bg,
                      borderRadius: BorderRadius.circular(24),
                      clipBehavior: Clip.antiAlias,
                      elevation: 8,
                      shadowColor: Colors.black.withValues(alpha: .2),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxHeight),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Flexible(
                              fit: FlexFit.loose,
                              child: SingleChildScrollView(
                                key: const ValueKey('guide-body'),
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  14,
                                  14,
                                  8,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.title,
                                      style: JType.ui(
                                        widget.compact ? 17 : 20,
                                        w: FontWeight.w700,
                                        color: c.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      widget.message,
                                      style: JType.ui(
                                        widget.compact ? 13 : 15,
                                        color: c.ink,
                                        h: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              key: const ValueKey('guide-footer'),
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (widget.secondary != null)
                                    TextButton(
                                      autofocus: widget.action == null,
                                      style: TextButton.styleFrom(
                                        foregroundColor: c.ink,
                                        minimumSize: const Size(48, 48),
                                      ),
                                      onPressed: widget.onSecondary,
                                      child: Text(
                                        widget.secondary!,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  actionRow,
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GuideMask extends CustomPainter {
  _GuideMask(this.hole, this.extra);
  final Rect? hole;
  final Rect? extra;
  RRect? get shape => hole == null
      ? null
      : RRect.fromRectAndRadius(hole!, const Radius.circular(26));
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (shape != null) path.addRRect(shape!);
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: .40));
    if (shape != null) {
      canvas.drawRRect(
        shape!,
        Paint()
          ..color = const Color(0xFFD8C18C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool hitTest(Offset position) =>
      !(shape?.contains(position) ?? false) &&
      !(extra?.contains(position) ?? false);
  @override
  bool shouldRepaint(_GuideMask oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.extra != extra;
}

/// Shared overlay for the real reminder settings pages, not a new route.
class ReminderLearningOverlay extends StatelessWidget {
  const ReminderLearningOverlay({
    super.key,
    required this.editor,
    required this.onClose,
    this.onTargetAction,
  });
  final bool editor;
  final VoidCallback onClose;
  final VoidCallback? onTargetAction;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context),
        guide = AppScope.of(context).navigationGuide;
    final kz = app.lang == 'kz';
    if (!editor && guide.step == GuideStep.remindersAdd) {
      return GuidedSpotlight(
        key: ValueKey(guide.step),
        target: guide.target('reminders-add'),
        title: kz ? 'Жеке іс' : 'Своё дело',
        message: kz
            ? 'Жаңа іс жасау үшін «Еске салу қосу» батырмасын басыңыз.'
            : 'Нажмите «Добавить напоминание», чтобы открыть создание своего дела.',
        action: kz ? 'Іс қоспай жалғастыру' : 'Продолжить без создания',
        onAction: onClose,
        secondary: kz ? 'Еске салу қосу' : 'Добавить напоминание',
        onSecondary: onTargetAction,
      );
    }
    if (!editor || !guide.inForm) return const SizedBox.shrink();
    final prayer = guide.step == GuideStep.prayer;
    final clock = guide.step == GuideStep.clock;
    return GuidedSpotlight(
      key: ValueKey(guide.step),
      compact: true,
      target: guide.target(
        prayer
            ? 'form-prayer'
            : clock
            ? 'form-clock'
            : 'form-schedule',
      ),
      title: prayer
          ? (kz ? 'Намазбен бірге' : 'Вместе с намазом')
          : clock
          ? (kz ? 'Нақты сағатта' : 'В определённое время')
          : (kz ? 'Өзіңіз баптаңыз' : 'Настройте под себя'),
      message: prayer
          ? (kz
                ? '«Намаз уақытынан» режимін басыңыз. Мысалы, екінтіден 15 минут кейін: еске салу намаз кестесімен бірге өзгереді.'
                : 'Нажмите «От времени намаза». Например, через 15 минут после Асра: напоминание будет меняться вместе с расписанием молитв.')
          : clock
          ? (kz
                ? 'Енді «Белгіленген уақытта» режимін басыңыз. Мысалы, күн сайын 20:00 — намазға байланысты емес.'
                : 'Теперь нажмите «В указанное время». Например, ежедневно в 20:00 — независимо от намаза.')
          : (kz
                ? 'Мұнда уақыт пен қайталану таңдалады. Іс тек атауын енгізіп, қосу батырмасын басқанда сақталады. Үйрету үшін ештеңе қосудың қажеті жоқ.'
                : 'Здесь выбираются время и повторение. Дело сохраняется только после ввода названия и нажатия «Добавить». Для обучения ничего создавать не нужно.'),
      action: guide.step == GuideStep.formDone
          ? (kz ? 'Істі баптауға өту' : 'Продолжить создание')
          : null,
      onAction: app.closeNavigationGuide,
      secondary: prayer
          ? (kz ? 'Намаз уақытын таңдау' : 'Выбрать время намаза')
          : clock
          ? (kz ? 'Нақты уақытты таңдау' : 'Выбрать точное время')
          : null,
      onSecondary: onTargetAction,
    );
  }
}
