import 'dart:io';

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

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 50; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
  for (var i = 0; i < 40; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> shot(WidgetTester t, String name) async {
  await settle(t);
  await expectLater(find.byType(JadwalApp), matchesGoldenFile('$dir/$name.png'));
}

final lang = Platform.environment['STORE_LANG'] ?? 'ru';
final dir = lang == 'ru' ? 'raw2' : 'raw2$lang';

const times = [390, 490, 735, 845, 965, 1060];

Future<dynamic> open(WidgetTester t, DateTime now, String scene) async {
  t.view.physicalSize = const Size(1290, 2796);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final prefs = <String, Object>{
    'onboardingDone': true,
    'pagesDiscoveryV1Seen': true,
    'featureTourPendingV1': true,
    'contextHint:v1:reader-palette': true,
    'contextHint:v1:appearance': true,
    'lang': lang,
    'dayLayout': 'pages',
    'homeScene': scene,
    'done:${AppState.dayKey(now)}': now.hour >= 12 ? ['morning'] : <String>[],
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
      title: lang == 'kz' ? 'Мешітте жұма намазы' : 'Пятничный намаз в мечети',
      prayer: 2,
      offsetMin: -30,
      anchor: 'prayer',
    ),
  );
  app.addReminder(
    ReminderConfig(
      id: 'quran',
      title: lang == 'kz' ? 'Құран оқу, 10 минут' : 'Читать Коран 10 минут',
      prayer: 0,
      offsetMin: 0,
      anchor: 'clock',
      fixedHour: 21,
      fixedMinute: 0,
    ),
  );
  final schedule = ScheduleService(
    await SharedPreferences.getInstance(),
    now: () => now,
  );
  schedule.preload(kDefaultCity, 2026, {
    for (var d = 1; d <= 30; d++) '2026-11-${d.toString().padLeft(2, '0')}': times,
  });
  await t.runAsync(AdhkarRepository.load);
  await t.pumpWidget(JadwalApp(state: app, schedule: schedule));
  return t.state(find.byType(HomeScreen));
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

  final homes = <String, (DateTime, String)>{
    'home-mecca-day': (DateTime(2026, 11, 13, 11, 20), 'mecca'),
    'home-mecca-sunset': (DateTime(2026, 11, 13, 15, 52), 'mecca'),
    'home-mecca-night': (DateTime(2026, 11, 13, 17, 25), 'mecca'),
    'home-mecca-sunrise': (DateTime(2026, 11, 13, 7, 50), 'mecca'),
    'home-medina-night': (DateTime(2026, 11, 13, 17, 25), 'medina'),
    'home-medina-sunset': (DateTime(2026, 11, 13, 15, 52), 'medina'),
    'home-astana-sunset': (DateTime(2026, 11, 13, 15, 52), 'astana'),
    'home-astana-night': (DateTime(2026, 11, 13, 17, 25), 'astana'),
  };
  for (final e in homes.entries) {
    testWidgets(e.key, (t) async {
      await open(t, e.value.$1, e.value.$2);
      await shot(t, e.key);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final (name, now) in [
    ('today-day', DateTime(2026, 11, 13, 12, 5)),
    ('today-night', DateTime(2026, 11, 13, 19, 40)),
    ('calendar-day', DateTime(2026, 11, 13, 12, 5)),
  ]) {
    testWidgets(name, (t) async {
      final home = await open(t, now, 'mecca');
      home.swipeProgress = name.startsWith('calendar') ? 2.0 : 1.0;
      await shot(t, name);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final (name, palette) in [
    ('reader-paper', 'paper'),
    ('reader-dark', 'softDark'),
  ]) {
    testWidgets(name, (t) async {
      await open(t, DateTime(2026, 11, 13, 7, 30), 'mecca');
      final app = AppScope.of(t.element(find.byType(HomeScreen)));
      app.readerPalette = palette;
      Navigator.of(t.element(find.byType(HomeScreen))).push(
        MaterialPageRoute<void>(
          builder: (_) => const ReaderScreen(collectionId: 'morning', initialIndex: 0),
        ),
      );
      await shot(t, name);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
}
