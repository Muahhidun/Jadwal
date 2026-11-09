import 'package:flutter/cupertino.dart';

import '../data/app_state.dart';
import '../theme/tokens.dart';
import 'language_picker.dart';
import 'settings_shell.dart';

/// Одноразовое знакомство существующих пользователей с пробным видом.
/// Ничего не переключает без явного выбора в «Оформлении».
Future<void> showPagesDiscovery(BuildContext homeContext) async {
  final app = AppScope.of(homeContext);
  if (!app.shouldShowPagesDiscovery) return;
  final openAppearance = await DauamSettingsSheet.open<bool>(
    homeContext,
    heightFactor: .54,
    builder: (_) => const _PagesDiscoveryContent(),
  );
  app.pagesDiscoverySeen = true;
  if (openAppearance == true && homeContext.mounted) {
    await AppearancePicker.open(homeContext);
  }
}

class _PagesDiscoveryContent extends StatelessWidget {
  const _PagesDiscoveryContent();

  @override
  Widget build(BuildContext context) {
    final kz = AppScope.of(context).lang == 'kz';
    final c = dauamSettingsPalette(context).colors;
    return DauamSettingsPage(
      root: true,
      title: kz ? 'Жаңа көрініс' : 'Новый вид',
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: DauamPrimaryButton(
              label: kz ? 'Көріністен қарау' : 'Посмотреть в оформлении',
              onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
            ),
          ),
          DauamTextAction(
            label: kz ? 'Кейінірек' : 'Позже',
            onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        children: [
          Icon(CupertinoIcons.square_on_square, size: 44, color: c.gold),
          const SizedBox(height: 18),
          Text(
            kz
                ? '«Беттер» көрінісін байқап көріңіз'
                : 'Попробуйте вид «Страницы»',
            textAlign: TextAlign.center,
            style: JType.ui(22, w: FontWeight.w700, color: c.ink),
          ),
          const SizedBox(height: 12),
          Text(
            kz
                ? 'Намаз уақыттары, бүгінгі істер және тұрақтылық күнтізбесі жеке беттерге бөлінген. Олардың арасында сырғытып ауыса аласыз.'
                : 'Времена молитв, дела сегодня и календарь постоянства разложены по отдельным экранам. Между ними можно переходить свайпом.',
            textAlign: TextAlign.center,
            style: JType.ui(14.5, color: c.sub, h: 1.45),
          ),
          const SizedBox(height: 12),
          Text(
            kz
                ? 'Классикалық көрініс өзгермейді. Қаласаңыз, кез келген уақытта оған қайта ораласыз.'
                : 'Классический вид пока остаётся у вас. Вернуться к нему можно в любой момент.',
            textAlign: TextAlign.center,
            style: JType.ui(13, color: c.faint, h: 1.4),
          ),
        ],
      ),
    );
  }
}
