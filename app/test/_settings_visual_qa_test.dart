import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/main.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule_service.dart';
import 'package:jadwal/screens/home.dart';

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
  testWidgets('settings visual QA', (WidgetTester tester) async {
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

    (tester.state(find.byType(HomeScreen)) as dynamic).swipeProgress = 1.0;
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byType(JadwalApp),
      matchesGoldenFile('goldens/lower_screen_393x852.png'),
    );

    expect(find.text('Напоминания'), findsOneWidget);
    expect(find.text('Вид'), findsOneWidget);
    expect(find.text('Язык'), findsOneWidget);
    await tester.tap(find.text('Вид'));
    // Let the raster scene preview finish decoding outside the fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await _pumpFrames(tester, 10);
    expect(find.text('Мекка'), findsOneWidget);
    expect(find.text('Природа'), findsOneWidget);
    expect(find.text('Минимализм'), findsOneWidget);
    expect(find.text('Русский'), findsNothing);
    await expectLater(
      find.byType(JadwalApp),
      matchesGoldenFile('goldens/appearance_picker_393x852.png'),
    );

    await tester.tap(find.byIcon(CupertinoIcons.xmark));
    await _pumpFrames(tester, 8);
    await tester.tap(find.text('Язык'));
    await _pumpFrames(tester, 8);
    expect(find.text('Русский'), findsOneWidget);
    expect(find.text('Қазақша'), findsOneWidget);
    expect(find.text('Мекка'), findsNothing);
  });
}
