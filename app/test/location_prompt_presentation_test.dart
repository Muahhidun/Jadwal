import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/services/location_checker_service.dart';

void main() {
  testWidgets('фоновая GPS-подсказка не открывается под другим route', (
    tester,
  ) async {
    late BuildContext homeContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            homeContext = context;
            return const Scaffold(body: Text('Главный'));
          },
        ),
      ),
    );

    expect(LocationCheckerService.canPresentPrompt(homeContext), isTrue);

    Navigator.of(homeContext).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Настройки')),
      ),
    );
    await tester.pumpAndSettle();

    expect(LocationCheckerService.canPresentPrompt(homeContext), isFalse);

    Navigator.of(homeContext).pop();
    await tester.pumpAndSettle();

    expect(LocationCheckerService.canPresentPrompt(homeContext), isTrue);
  });
}
