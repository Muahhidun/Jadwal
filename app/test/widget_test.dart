import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/main.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule_service.dart';

/// Фиксированный день из дизайн-прототипа: пятница 03.07.2026, 20:11, Алматы.
/// Времена — [fajr, sunrise, dhuhr, asr, maghrib, isha] в минутах.
Future<ScheduleService> demoSchedule() async {
  final prefs = await SharedPreferences.getInstance();
  final service =
      ScheduleService(prefs, now: () => DateTime(2026, 7, 3, 20, 11));
  service.preload(kDefaultCity, 2026, {
    '2026-07-03': [185, 298, 779, 1074, 1253, 1358],
    '2026-07-04': [186, 299, 779, 1074, 1253, 1357],
  });
  return service;
}

void main() {
  testWidgets('первый запуск открывает онбординг с выбором языка', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = await AppState.load();
    await tester.pumpWidget(JadwalApp(state: state, schedule: await demoSchedule()));
    await tester.pump();

    expect(find.text('Дауам'), findsOneWidget);
    expect(find.text('Қазақша'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
  });

  testWidgets('вечером в открытое окно главный зовёт к вечерним зикрам',
      (tester) async {
    SharedPreferences.setMockInitialValues({'onboardingDone': true, 'lang': 'ru'});
    final state = await AppState.load();
    await tester.pumpWidget(JadwalApp(state: state, schedule: await demoSchedule()));
    await tester.pump();

    // В заголовке — неразрывный пробел ( ), как в дизайн-прототипе.
    expect(find.text('Вечерние зикры'), findsWidgets);
    expect(find.text('Читать зикры'), findsOneWidget);
    expect(find.textContaining('42'), findsWidgets); // адаптивно: «42 мин»
  });

  testWidgets('после отметки вечерних появляется час дуа (пятница)',
      (tester) async {
    SharedPreferences.setMockInitialValues({'onboardingDone': true, 'lang': 'ru'});
    final state = await AppState.load();
    await tester.pumpWidget(JadwalApp(state: state, schedule: await demoSchedule()));
    await tester.pump();

    await tester.tap(find.text('Отметить без чтения ✓'));
    await tester.pump();

    expect(find.text('Час дуа'), findsWidgets);
  });
}
