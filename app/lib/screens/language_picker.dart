import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import 'settings_shell.dart';

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});

  static Future<void> open(BuildContext context) =>
      DauamSettingsSheet.open<void>(
        context,
        heightFactor: .62,
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
                    Navigator.of(context, rootNavigator: true).pop();
                  },
                ),
                DauamChoiceRow(
                  title: 'Русский',
                  subtitle: 'Russian',
                  selected: app.lang == 'ru',
                  onTap: () {
                    app.lang = 'ru';
                    HapticFeedback.mediumImpact();
                    Navigator.of(context, rootNavigator: true).pop();
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
