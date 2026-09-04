import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/screens/celebration.dart';
import 'package:jadwal/screens/kahf_reader.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('маршрут читалки прозрачен и показывает предыдущий экран', () {
    final route = kahfReaderRoute();

    expect(route.opaque, isFalse);
    expect(route.barrierColor, Colors.transparent);
  });

  testWidgets('завершение аль-Кахф показывает итог выполненной задачи', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'lang': 'ru'});
    final state = await AppState.load();

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: CelebrationScreen(collectionId: 'kahf')),
      ),
    );
    await tester.pump();

    expect(find.text('Сура аль-Кахф прочитана'), findsOneWidget);
    expect(find.text('ЗАДАЧА НА СЕГОДНЯ ВЫПОЛНЕНА'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
