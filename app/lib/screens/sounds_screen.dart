import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../notifications/notifications.dart';
import '../prayer/schedule_service.dart';
import 'settings_shell.dart';

/// Звуки уведомлений: отдельно для времени намаза и для напоминаний о делах.
/// При выборе приходит пробное уведомление — слышно ровно то, что прозвучит.
class SoundsScreen extends StatelessWidget {
  const SoundsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';

    void choose(String soundId, {required bool prayer}) {
      if (prayer) {
        app.prayerSound = soundId;
      } else {
        app.taskSound = soundId;
      }
      syncNotifications(app, ScheduleScope.of(context));
      gNotifier?.preview(soundId, lang: app.lang);
    }

    return DauamSettingsPage(
      title: kz ? 'Дыбыстар' : 'Звуки',
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            DauamSection(
              label: kz ? 'Намаз уақыты' : 'Время намаза',
              footer: kz
                  ? 'Азан — әл-Харам мешітіндегі ақшам азанының басы (30 секунд: iPhone хабарламаның дыбысын осымен шектейді).'
                  : 'Азан — начало азана магриба в Масджид аль-Харам (30 секунд: iPhone ограничивает так звук уведомления).',
              children: [
                for (final sound in kNotifSounds)
                  DauamChoiceRow(
                    title: sound.title(app.lang),
                    selected: app.prayerSound == sound.id,
                    onTap: () => choose(sound.id, prayer: true),
                  ),
              ],
            ),
            DauamSection(
              label: kz ? 'Істер туралы еске салу' : 'Напоминания о делах',
              footer: kz
                  ? 'Таңдағанда осы дыбыспен сынақ хабарлама келеді. Телефон дыбыссыз режимде болса, дыбыс естілмейді.'
                  : 'При выборе придёт пробное уведомление с этим звуком. Если телефон в беззвучном режиме, звука не будет.',
              children: [
                for (final sound in kNotifSounds.where((s) => !s.prayerOnly))
                  DauamChoiceRow(
                    title: sound.title(app.lang),
                    selected: app.taskSound == sound.id,
                    onTap: () => choose(sound.id, prayer: false),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
