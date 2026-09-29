import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/main.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule_service.dart';
import 'package:jadwal/screens/home.dart';

Future<void> _fonts() async {
  for (final (family, asset) in [
    ('Manrope', 'assets/fonts/Manrope.ttf'),
    ('Literata', 'assets/fonts/Literata.ttf'),
    ('Amiri', 'assets/fonts/Amiri-Regular.ttf'),
    ('packages/cupertino_icons/CupertinoIcons',
        'packages/cupertino_icons/assets/CupertinoIcons.ttf'),
  ]) {
    await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
  }
}

Future<void> _render(WidgetTester tester, DateTime at, String name) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final real = DateTime.now();
  final realKey = '${real.year}-${real.month}-${real.day}';
  SharedPreferences.setMockInitialValues({
    'onboardingDone': true,
    'lang': 'ru',
    'dayLayout': 'timeline',
    'firstUseDate': '2026-7-20',
    'done:$realKey': ['morning'],
    'done:2026-7-20': ['morning', 'evening'],
    'done:2026-7-21': ['morning'],
    'done:2026-7-22': ['morning', 'evening'],
  });
  final prefs = await SharedPreferences.getInstance();
  final schedule = ScheduleService(prefs, now: () => at);
  schedule.preload(kDefaultCity, 2026, {
    '2026-07-23': [126, 242, 730, 1056, 1208, 1324],
    '2026-07-24': [127, 243, 730, 1055, 1207, 1323],
  });
  final app = await AppState.load();
  await tester.pumpWidget(JadwalApp(state: app, schedule: schedule));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  (tester.state(find.byType(HomeScreen)) as dynamic).swipeProgress = 1.0;
  await tester.pump(const Duration(milliseconds: 100));
  await expectLater(find.byType(JadwalApp), matchesGoldenFile('$name.png'));
}

void main() {
  testWidgets('лента дня — вечер четверга', (tester) async {
    await _fonts();
    await _render(tester, DateTime(2026, 7, 23, 18, 30), 'timeline_thursday_evening');
  });
  testWidgets('лента дня — пятница утром', (tester) async {
    await _fonts();
    await _render(tester, DateTime(2026, 7, 24, 10, 15), 'timeline_friday_morning');
  });
}
