// Store screenshots: real production screens, deterministic data.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jadwal/data/adhkar.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/main.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule_service.dart';
import 'package:jadwal/screens/home.dart';
import 'package:jadwal/screens/reader.dart';
import 'package:jadwal/screens/reminders.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 60; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> shot(WidgetTester t, String name) async {
  await settle(t);
  await expectLater(find.byType(JadwalApp), matchesGoldenFile('raw/$name.png'));
}

void main() {
  setUpAll(() async {
    for (final font in {
      'Manrope': 'assets/fonts/Manrope.ttf',
      'Inter': 'assets/fonts/Inter.ttf',
      'Literata': 'assets/fonts/Literata.ttf',
      'Amiri': 'assets/fonts/Amiri-Regular.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'packages/cupertino_icons/CupertinoIcons':
          'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final lang in ['ru', 'kz']) {
    testWidgets('store $lang', (t) async {
      t.view.physicalSize = const Size(1290, 2796);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final now = DateTime(2026, 11, 10, 11, 20);
      final prefs = <String, Object>{
        'onboardingDone': true,
        'pagesDiscoveryV1Seen': true,
        'featureTourPendingV1': true,
        'contextHint:v1:reader-palette': true,
        'contextHint:v1:appearance': true,
        'lang': lang,
        'dayLayout': 'pages',
        'done:${AppState.dayKey(now)}': ['morning'],
      };
      for (final d in [2, 3, 4, 5, 6, 7, 8, 9]) {
        prefs['done:${AppState.dayKey(DateTime(2026, 11, d))}'] =
            d == 6 ? ['morning'] : ['morning', 'evening'];
      }
      SharedPreferences.setMockInitialValues(prefs);
      final app = await AppState.load();
      app.addReminder(
        ReminderConfig(
          id: 'mosque',
          title: lang == 'kz' ? 'Мешітке бару' : 'Посетить мечеть',
          prayer: 0,
          offsetMin: 0,
          anchor: 'clock',
          fixedHour: 13,
          fixedMinute: 0,
        ),
      );
      final schedule = ScheduleService(
        await SharedPreferences.getInstance(),
        now: () => now,
      );
      final times = [390, 490, 735, 845, 965, 1060];
      schedule.preload(kDefaultCity, 2026, {
        for (var d = 1; d <= 30; d++)
          '2026-11-${d.toString().padLeft(2, '0')}': times,
      });
      await t.runAsync(AdhkarRepository.load);
      await t.pumpWidget(JadwalApp(state: app, schedule: schedule));
      await shot(t, '$lang-1-home');
      final home = t.state(find.byType(HomeScreen)) as dynamic;
      home.swipeProgress = 1.0;
      await shot(t, '$lang-2-today');
      home.swipeProgress = 2.0;
      await shot(t, '$lang-3-calendar');
      home.swipeProgress = 1.0;
      await settle(t);
      RemindersScreen.open(t.element(find.byType(HomeScreen)));
      await shot(t, '$lang-4-reminders');
      Navigator.of(t.element(find.byType(HomeScreen)), rootNavigator: true).pop();
      await settle(t);
      home.swipeProgress = 0.0;
      await settle(t);
      Navigator.of(t.element(find.byType(HomeScreen))).push(
        MaterialPageRoute<void>(
          builder: (_) => const ReaderScreen(collectionId: 'evening'),
        ),
      );
      await shot(t, '$lang-5-reader');
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
}
