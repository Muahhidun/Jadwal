import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/main.dart';

void main() {
  testWidgets('первый запуск открывает онбординг с выбором языка', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = await AppState.load();
    await tester.pumpWidget(JadwalApp(state: state));
    await tester.pump();

    expect(find.text('Jadwal'), findsOneWidget);
    expect(find.text('Қазақша'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
  });

  testWidgets('после онбординга открывается главный экран', (tester) async {
    SharedPreferences.setMockInitialValues({'onboardingDone': true, 'lang': 'ru'});
    final state = await AppState.load();
    await tester.pumpWidget(JadwalApp(state: state));
    await tester.pump();

    // В заголовке — неразрывный пробел ( ), как в дизайн-прототипе.
    expect(find.text('Вечерние зикры'), findsOneWidget);
    expect(find.text('Читать зикры'), findsOneWidget);
  });
}
