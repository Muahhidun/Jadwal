import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/main.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule_service.dart';
import 'package:jadwal/screens/settings_shell.dart';

Future<ScheduleService> _schedule() async {
  final prefs = await SharedPreferences.getInstance();
  final service = ScheduleService(
    prefs,
    now: () => DateTime(2026, 7, 23, 12, 22),
  );
  service.preload(kDefaultCity, 2026, {
    '2026-07-23': [126, 242, 730, 1056, 1208, 1324],
    '2026-07-24': [127, 243, 730, 1055, 1207, 1323],
  });
  return service;
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 20]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  testWidgets('settings visual QA', (tester) async {
    final fonts = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await fonts.load();
    final cupertinoIcons = FontLoader('packages/cupertino_icons/CupertinoIcons')
      ..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      );
    await cupertinoIcons.load();
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'ru',
    });
    final app = await AppState.load();
    await tester.pumpWidget(JadwalApp(state: app, schedule: await _schedule()));
    await _pumpFrames(tester, 8);
    await expectLater(
      find.byType(JadwalApp),
      matchesGoldenFile('goldens/main_timer_393x852.png'),
    );

    await tester.flingFrom(const Offset(196, 790), const Offset(0, -720), 1800);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.flingFrom(const Offset(196, 650), const Offset(0, -260), 1800);
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(
      find.byType(JadwalApp),
      matchesGoldenFile('goldens/lower_screen_393x852.png'),
    );
    await tester.tap(find.text('Аср'));
    await _pumpFrames(tester);
    await expectLater(
      find.byType(DauamSettingsSheet),
      matchesGoldenFile('goldens/settings_compact_detail_393x852.png'),
    );
    await tester.tap(find.byIcon(CupertinoIcons.xmark).last);
    await _pumpFrames(tester);

    await tester.tap(find.text('Напоминания'));
    await _pumpFrames(tester);
    await expectLater(
      find.byType(DauamSettingsSheet),
      matchesGoldenFile('goldens/settings_hub_393x852.png'),
    );

    await tester.tap(find.text('Времена молитв'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Фаджр').last);
    await _pumpFrames(tester);
    expect(find.text('Событие'), findsNothing);
    expect(find.text('Повторение'), findsNothing);
    await expectLater(
      find.byType(DauamSettingsSheet),
      matchesGoldenFile('goldens/settings_fixed_detail_393x852.png'),
    );
    await tester.tap(find.byIcon(CupertinoIcons.minus));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('За 5 мин до'), findsOneWidget);
    await expectLater(
      find.byType(DauamSettingsSheet),
      matchesGoldenFile('goldens/settings_offset_393x852.png'),
    );
  });
}
