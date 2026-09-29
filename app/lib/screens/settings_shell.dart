import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../prayer/schedule_service.dart';
import '../theme/ornament.dart';
import '../theme/tokens.dart';
import 'scene_background.dart';

DaySurfacePalette dauamSettingsPalette(BuildContext context) {
  final scoped = context
      .dependOnInheritedWidgetOfExactType<_DauamSettingsPaletteScope>();
  if (scoped != null) return scoped.palette;
  final app = AppScope.of(context);
  final schedule = ScheduleScope.of(context);
  final now = schedule.now();
  final times = schedule.timesFor(app.city, now)!;
  return daySurfacePalette(
    times,
    now.hour * 3600 + now.minute * 60 + now.second,
  );
}

/// Акцент листов — то же золото, что у страниц: галочки, переключатели,
/// главная кнопка.
Color dauamSettingsAccent(BuildContext context) =>
    dauamSettingsPalette(context).colors.gold;

class _DauamSettingsPaletteScope extends InheritedWidget {
  const _DauamSettingsPaletteScope({
    required this.palette,
    required super.child,
  });

  final DaySurfacePalette palette;

  @override
  bool updateShouldNotify(_DauamSettingsPaletteScope oldWidget) =>
      palette != oldWidget.palette;
}

class _DauamSettingsBackdrop extends StatelessWidget {
  const _DauamSettingsBackdrop({required this.palette, required this.child});

  final DaySurfacePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = palette.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(palette.top, c.bg, .16)!.withValues(alpha: .995),
            Color.lerp(palette.middle, c.bg, .38)!.withValues(alpha: .998),
            Color.lerp(palette.bottom, c.bg, .54)!,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Фирменный фон — как у страниц ленты: узор и золотое свечение.
          CustomPaint(
            painter: OrnamentPainter(
              line: c.ink.withValues(alpha: palette.isLight ? .04 : .045),
              glow: c.gold.withValues(alpha: palette.isLight ? .09 : .11),
              glowCenter: const Offset(.5, .02),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Единая модальная поверхность для всех настроек Dauam.
/// Внутри живёт отдельный Navigator: следующие экраны сдвигаются по-iOS,
/// но физически остаются в одной панели — без «карточки поверх карточки».
class DauamSettingsSheet extends StatefulWidget {
  const DauamSettingsSheet({
    super.key,
    required this.home,
    required this.palette,
  });

  final Widget home;
  final DaySurfacePalette palette;

  static Future<T?> open<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    double heightFactor = .93,
  }) {
    final palette = dauamSettingsPalette(context);
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .34),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: heightFactor,
        child: DauamSettingsSheet(
          palette: palette,
          home: Builder(builder: builder),
        ),
      ),
    );
  }

  @override
  State<DauamSettingsSheet> createState() => _DauamSettingsSheetState();
}

class _DauamSettingsSheetState extends State<DauamSettingsSheet> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final c = palette.colors;

    return _DauamSettingsPaletteScope(
      palette: palette,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: palette.isLight
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: _DauamSettingsBackdrop(
              palette: palette,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Navigator(
                      key: _navigatorKey,
                      onGenerateInitialRoutes: (_, _) => [
                        CupertinoPageRoute<void>(builder: (_) => widget.home),
                      ],
                      onGenerateRoute: (_) => null,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 38,
                          height: 5,
                          decoration: BoxDecoration(
                            color: c.faint.withValues(alpha: .44),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DauamSettingsPage extends StatelessWidget {
  const DauamSettingsPage({
    super.key,
    required this.title,
    required this.child,
    this.root = false,
    this.trailing,
    this.bottom,
  });

  final String title;
  final Widget child;
  final bool root;
  final Widget? trailing;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final palette = dauamSettingsPalette(context);
    final c = palette.colors;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return _DauamSettingsBackdrop(
      palette: palette,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                height: 88,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 25, 14, 7),
                  child: Row(
                    children: [
                      DauamRoundButton(
                        icon: root
                            ? CupertinoIcons.xmark
                            : CupertinoIcons.chevron_back,
                        semanticLabel: root ? 'Закрыть' : 'Назад',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          if (root) {
                            Navigator.of(context, rootNavigator: true).pop();
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: JType.ui(
                            23,
                            w: FontWeight.w700,
                            color: c.ink,
                            ls: -.35,
                          ),
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 10),
                        trailing!,
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _StaggerScope(counter: _StaggerCounter(), child: child),
              ),
              if (bottom != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    8,
                    18,
                    keyboard > 0 ? 8 : 12,
                  ),
                  child: bottom!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class DauamRoundButton extends StatelessWidget {
  const DauamRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = dauamSettingsPalette(context);
    final c = p.colors;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: p.surface.withValues(alpha: p.isLight ? .64 : .48),
        shape: CircleBorder(
          side: BorderSide(color: p.border.withValues(alpha: .52), width: .7),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 20, color: c.ink),
          ),
        ),
      ),
    );
  }
}

class DauamTextAction extends StatelessWidget {
  const DauamTextAction({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = dauamSettingsPalette(context);
    final c = p.colors;
    final accent = dauamSettingsAccent(context);
    return TextButton(
      onPressed: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap();
            }
          : null,
      style: TextButton.styleFrom(
        foregroundColor: accent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Text(
        label,
        style: JType.ui(
          14.5,
          w: FontWeight.w700,
          color: enabled ? accent : c.faint,
        ),
      ),
    );
  }
}

class DauamSection extends StatelessWidget {
  const DauamSection({
    super.key,
    required this.children,
    this.label,
    this.footer,
  });

  final String? label;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = dauamSettingsPalette(context);
    final c = p.colors;
    final order = _StaggerScope.next(context);
    return _StaggerIn(
      order: order,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Подпись раздела — золотая, в разрядку, как на страницах ленты.
            if (label != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 8, 9),
                child: Text(
                  label!.toUpperCase(),
                  style: JType.caption(c.gold, size: 11),
                ),
              ),
            // Карточка — та же поверхность, что у страниц, без тяжёлого blur.
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.border, width: .8),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      children[i],
                      if (i < children.length - 1)
                        Padding(
                          padding: const EdgeInsets.only(left: 58),
                          child: Divider(
                            height: 1,
                            thickness: .55,
                            color: c.hair.withValues(alpha: .7),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Text(footer!, style: JType.ui(12, color: c.sub, h: 1.4)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Счётчик порядка разделов на листе: каждый следующий раздел появляется
/// чуть позже предыдущего.
class _StaggerCounter {
  int value = 0;
}

class _StaggerScope extends InheritedWidget {
  const _StaggerScope({required this.counter, required super.child});

  final _StaggerCounter counter;

  static int next(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_StaggerScope>();
    if (scope == null) return 0;
    return scope.counter.value++;
  }

  @override
  bool updateShouldNotify(_StaggerScope oldWidget) => false;
}

/// Мягкое появление раздела при открытии листа: всплывает и проявляется,
/// каждый следующий — с небольшой задержкой. Проигрывается один раз.
class _StaggerIn extends StatelessWidget {
  const _StaggerIn({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Разделы ниже экрана при прокрутке не должны ждать долго.
    final delay = 70 * math.min(order, 5).toInt();
    final total = 420 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

class DauamSettingsRow extends StatelessWidget {
  const DauamSettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.value,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = dauamSettingsPalette(context);
    final c = p.colors;
    final accent = dauamSettingsAccent(context);
    final titleColor = destructive ? c.red : c.ink;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 62),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: (destructive ? c.red : accent).withValues(
                        alpha: .11,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      size: 17,
                      color: destructive ? c.red : accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JType.ui(
                          15.5,
                          w: FontWeight.w600,
                          color: titleColor,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: JType.ui(12.5, color: c.faint, h: 1.25),
                        ),
                      ],
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 10),
                  // Значение прижато вправо, к стрелке: у всех строк стрелки
                  // и значения стоят в одну линию.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: JType.ui(14, color: c.sub),
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  trailing!,
                ] else if (onTap != null) ...[
                  const SizedBox(width: 7),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 16,
                    color: c.faint,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DauamSwitchRow extends StatelessWidget {
  const DauamSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = dauamSettingsAccent(context);
    return DauamSettingsRow(
      title: title,
      subtitle: subtitle,
      icon: icon,
      trailing: CupertinoSwitch(
        value: value,
        activeTrackColor: accent,
        onChanged: (next) {
          HapticFeedback.selectionClick();
          onChanged(next);
        },
      ),
    );
  }
}

class DauamChoiceRow extends StatelessWidget {
  const DauamChoiceRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = dauamSettingsAccent(context);
    return DauamSettingsRow(
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: selected
          ? Icon(CupertinoIcons.check_mark, color: accent, size: 20)
          : const SizedBox(width: 20),
    );
  }
}

class DauamPrimaryButton extends StatelessWidget {
  const DauamPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = dauamSettingsPalette(context);
    final c = palette.colors;
    final accent = dauamSettingsAccent(context);
    // Текст на золоте — как у кнопки «Читать» на странице «Сегодня».
    final onAccent = palette.isLight ? Colors.white : c.bg;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        onPressed: enabled
            ? () {
                HapticFeedback.mediumImpact();
                onTap();
              }
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          disabledBackgroundColor: c.hair,
          foregroundColor: onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: JType.ui(
            15.5,
            w: FontWeight.w700,
            color: enabled ? onAccent : c.faint,
          ),
        ),
      ),
    );
  }
}

Route<T> dauamSettingsRoute<T>(Widget child) =>
    CupertinoPageRoute<T>(builder: (_) => child);
