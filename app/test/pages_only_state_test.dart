import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/screens/language_picker.dart';
import 'package:jadwal/prayer/schedule_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widget_test.dart' as fixtures;

void main() {
  for (final stored in [null, 'classic', 'pages', 'unknown']) {
    test(
      'pages is the only layout after loading $stored, data is preserved',
      () async {
        final initial = <String, Object>{
          'onboardingDone': true,
          'firstUseDate': '2026-07-01',
          'lang': 'kz',
          'theme': 'light',
          'homeScene': 'medina',
          'cityName': 'Астана',
          'done:2026-10-22': <String>['morning', 'custom:keep'],
          'customReminders': jsonEncode([
            const ReminderConfig(
              id: 'keep',
              title: 'Своё дело',
              prayer: 3,
              offsetMin: 15,
            ).toJson(),
          ]),
          'dayLayout': ?stored,
        };
        SharedPreferences.setMockInitialValues(initial);
        final app = await AppState.load();
        expect(app.dayLayout, 'pages');
        expect(app.shouldShowPagesDiscovery, isFalse);
        expect(app.customReminders.single.title, 'Своё дело');
        expect(app.customReminders.single.offsetMin, 15);
        expect(app.doneOn(DateTime(2026, 10, 22)), ['morning', 'custom:keep']);
        final prefs = await SharedPreferences.getInstance();
        for (final entry in initial.entries.where(
          (e) => e.key != 'dayLayout',
        )) {
          expect(prefs.get(entry.key), entry.value, reason: entry.key);
        }
      },
    );
  }

  testWidgets('appearance retains scenes but no classic/pages switch', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({'onboardingDone': true});
    final app = await AppState.load();
    await t.pumpWidget(
      AppScope(
        state: app,
        child: ScheduleScope(
          service: await fixtures.demoSchedule(),
          child: const MaterialApp(home: AppearancePicker()),
        ),
      ),
    );
    await t.pump();
    expect(find.text('Классический'), findsNothing);
    expect(find.text('Нижний экран'), findsNothing);
    expect(find.text('Мекка'), findsOneWidget);
    expect(find.text('Медина'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
