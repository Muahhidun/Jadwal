import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../theme/home_scene.dart';
import '../theme/tokens.dart';
import 'settings_shell.dart';

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});

  static Future<void> open(BuildContext context) =>
      DauamSettingsSheet.open<void>(
        context,
        heightFactor: .50,
        builder: (_) => const LanguagePicker(),
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    return DauamSettingsPage(
      root: true,
      title: kz ? 'Тіл' : 'Язык',
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            DauamSection(
              footer: kz
                  ? 'Интерфейс тілі бірден өзгереді.'
                  : 'Язык интерфейса изменится сразу.',
              children: [
                DauamChoiceRow(
                  title: 'Қазақша',
                  subtitle: 'Kazakh',
                  selected: app.lang == 'kz',
                  onTap: () {
                    app.lang = 'kz';
                    HapticFeedback.mediumImpact();
                  },
                ),
                DauamChoiceRow(
                  title: 'Русский',
                  subtitle: 'Russian',
                  selected: app.lang == 'ru',
                  onTap: () {
                    app.lang = 'ru';
                    HapticFeedback.mediumImpact();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AppearancePicker extends StatelessWidget {
  const AppearancePicker({super.key});

  static Future<void> open(BuildContext context) =>
      DauamSettingsSheet.open<void>(
        context,
        heightFactor: .88,
        builder: (_) => const AppearancePicker(),
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    return DauamSettingsPage(
      root: true,
      title: kz ? 'Көрініс' : 'Оформление',
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            DauamSection(
              label: kz ? 'Басты экран' : 'Главный экран',
              footer: kz
                  ? 'Көрініс намаз уақыттары есептелетін қалаға әсер етпейді.'
                  : 'Оформление не влияет на город, по которому рассчитываются времена молитв.',
              children: [
                for (final scene in HomeScene.values)
                  _SceneChoiceRow(
                    scene: scene,
                    selected: app.homeScene == scene,
                    title: _sceneTitle(scene, kz),
                    subtitle: _sceneSubtitle(scene, kz),
                    onTap: () {
                      app.homeScene = scene;
                      HapticFeedback.mediumImpact();
                    },
                  ),
              ],
            ),
            DauamSection(
              label: kz ? 'Төменгі экран' : 'Нижний экран',
              footer: kz
                  ? '«Беттер» — сынақ нұсқасы: намаздар, істер және тұрақтылық жеке беттерде, төмен сырғытып ауысасыз.'
                  : '«Страницы» — пробный вариант: намазы, дела и постоянство на отдельных экранах, листаются свайпом вниз.',
              children: [
                DauamChoiceRow(
                  title: kz ? 'Классикалық' : 'Классический',
                  selected: app.dayLayout != 'pages',
                  onTap: () {
                    app.dayLayout = 'classic';
                    HapticFeedback.mediumImpact();
                  },
                ),
                DauamChoiceRow(
                  title: kz ? 'Беттер' : 'Страницы',
                  subtitle: kz ? 'Прототип' : 'Прототип',
                  selected: app.dayLayout == 'pages',
                  onTap: () {
                    app.dayLayout = 'pages';
                    HapticFeedback.mediumImpact();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _sceneTitle(HomeScene scene, bool kz) => switch (scene) {
  HomeScene.mecca => kz ? 'Мекке' : 'Мекка',
  HomeScene.nature => kz ? 'Табиғат' : 'Природа',
  HomeScene.minimal => kz ? 'Минимализм' : 'Минимализм',
  HomeScene.ornament => kz ? 'Өрнек' : 'Орнамент',
};

String _sceneSubtitle(HomeScene scene, bool kz) => switch (scene) {
  HomeScene.mecca =>
    kz ? 'Қағба және Харам мешіті' : 'Кааба и Заповедная мечеть',
  HomeScene.nature => kz ? 'Таулар мен дала' : 'Горы и степь',
  HomeScene.minimal => kz ? 'Тек аспан мен жарық' : 'Только небо и свет',
  HomeScene.ornament =>
      kz ? 'Жұлдызды өрнек пен аркалар' : 'Звёздный узор и аркада',
};

class _SceneChoiceRow extends StatelessWidget {
  const _SceneChoiceRow({
    required this.scene,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final HomeScene scene;
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = dauamSettingsPalette(context).colors;
    final accent = dauamSettingsAccent(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
            child: Row(
              children: [
                _ScenePreview(scene: scene, selected: selected),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: JType.ui(15.5, w: FontWeight.w700, color: c.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JType.ui(12.5, color: c.faint),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  selected
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.circle,
                  size: 21,
                  color: selected ? accent : c.faint.withValues(alpha: .55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScenePreview extends StatelessWidget {
  const _ScenePreview({required this.scene, required this.selected});

  final HomeScene scene;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accent = dauamSettingsAccent(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 70,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? accent : Colors.white.withValues(alpha: .22),
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: .18),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _ScenePreviewPainter(scene)),
          if (scene == HomeScene.nature)
            Image.asset(
              'assets/images/nature_landscape_v2.png',
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.medium,
            ),
        ],
      ),
    );
  }
}

class _ScenePreviewPainter extends CustomPainter {
  const _ScenePreviewPainter(this.scene);

  final HomeScene scene;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF243C70), Color(0xFFE09A62)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(size.width * .72, size.height * .28),
      size.height * .10,
      Paint()..color = const Color(0xFFFFE2A3),
    );

    switch (scene) {
      case HomeScene.mecca:
        canvas.drawRect(
          Rect.fromLTWH(
            size.width * .39,
            size.height * .54,
            size.width * .22,
            size.height * .30,
          ),
          Paint()..color = const Color(0xFF111216),
        );
        canvas.drawRect(
          Rect.fromLTWH(
            size.width * .39,
            size.height * .58,
            size.width * .22,
            2,
          ),
          Paint()..color = const Color(0xFFD2A74E),
        );
        canvas.drawOval(
          Rect.fromLTWH(-8, size.height * .76, size.width + 16, 20),
          Paint()..color = const Color(0xFF182328),
        );
      case HomeScene.nature:
      // Реальный пейзаж накладывается виджетом Image поверх этого неба.
      case HomeScene.minimal:
        canvas.drawRect(
          Rect.fromLTWH(0, size.height * .82, size.width, size.height * .18),
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0x33131F27)],
            ).createShader(rect),
        );
      case HomeScene.ornament:
        final line = const Color(0xFFD2A74E);
        // Аркада
        final wall = Path()
          ..moveTo(0, size.height)
          ..lineTo(0, size.height * .62);
        const arches = 3;
        final aw = size.width / arches;
        for (var i = 0; i < arches; i++) {
          final left = i * aw;
          wall.lineTo(left + aw * .12, size.height * .62);
          wall.lineTo(left + aw * .12, size.height * .70);
          wall.quadraticBezierTo(
            left + aw * .5,
            size.height * .48,
            left + aw * .88,
            size.height * .70,
          );
          wall.lineTo(left + aw * .88, size.height * .62);
          wall.lineTo(left + aw, size.height * .62);
        }
        wall
          ..lineTo(size.width, size.height)
          ..close();
        canvas.drawPath(wall, Paint()..color = const Color(0xFF0B1118));
        // Звезда-мотив над аркадой
        final star = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = line.withValues(alpha: .75);
        for (var i = 0; i < 3; i++) {
          final c = Offset(size.width * (.24 + i * .26), size.height * .46);
          final r = size.height * .07;
          for (final turn in [0.0, 0.7853981633974483]) {
            final path = Path();
            for (var k = 0; k < 4; k++) {
              final a = turn + k * 1.5707963267948966;
              final pt = Offset(c.dx + cos(a) * r, c.dy + sin(a) * r);
              k == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
            }
            path.close();
            canvas.drawPath(path, star);
          }
        }
    }
  }

  @override
  bool shouldRepaint(_ScenePreviewPainter oldDelegate) =>
      oldDelegate.scene != scene;
}
