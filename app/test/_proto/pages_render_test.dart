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

Future<void> _render(
  WidgetTester tester,
  DateTime at,
  Map<double, String> shots, {
  Size physical = const Size(1179, 2556),
  double ratio = 3,
}) async {
  await _fonts();
  // В тестовой среде нет компаса: отдаём пустой поток.
  tester.binding.defaultBinaryMessenger.setMockStreamHandler(
    const EventChannel('hemanthraj/flutter_compass'),
    MockStreamHandler.inline(onListen: (_, _) {}),
  );
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final real = DateTime.now();
  final realKey = '${real.year}-${real.month}-${real.day}';
  SharedPreferences.setMockInitialValues({
    'onboardingDone': true,
    'lang': 'ru',
    'dayLayout': 'pages',
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
  for (final entry in shots.entries) {
    (tester.state(find.byType(HomeScreen)) as dynamic).swipeProgress =
        entry.key;
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byType(JadwalApp),
      matchesGoldenFile('${entry.value}.png'),
    );
  }
}

void main() {
  testWidgets('страницы — вечер четверга', (tester) async {
    await _render(tester, DateTime(2026, 7, 23, 18, 30), {
      0.0: 'p_00_main',
      0.25: 'p_01_main_leaving',
      0.45: 'p_02_main_leaving',
      0.75: 'p_03_today_entering',
      1.0: 'p_04_today',
      1.5: 'p_05_mid',
      1.65: 'p_05b_assemble',
      1.8: 'p_05c_assemble',
      2.0: 'p_06_consistency',
      -0.3: 'p_07a_to_qibla',
      -0.7: 'p_07b_to_qibla',
      -1.0: 'p_07_qibla',
    });
  });
  testWidgets('страницы — пятница утром', (tester) async {
    await _render(tester, DateTime(2026, 7, 24, 10, 15), {
      1.0: 'p_08_today_friday',
    });
  });
  testWidgets('страницы — поздний вечер', (tester) async {
    await _render(tester, DateTime(2026, 7, 23, 23, 10), {
      1.0: 'p_09_today_night',
    });
  });
  testWidgets('страницы — iPhone SE, пятница', (tester) async {
    await _render(
      tester,
      DateTime(2026, 7, 24, 10, 15),
      {1.0: 'p_10_today_se'},
      physical: const Size(750, 1334),
      ratio: 2,
    );
  });
}
