import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/adhkar.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/main.dart';
import 'package:jadwal/prayer/schedule_service.dart';
import 'package:jadwal/screens/home.dart';
import 'package:jadwal/screens/reader.dart';
import 'package:jadwal/screens/reader_palette.dart';
import 'package:jadwal/screens/reminders.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'completed_deeds_test.dart' show completedState, frames;

void main() {
  testWidgets('личное дело на «Сегодня» открывается на правку и удаляется', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (app, schedule) = await completedState('pages');
    app.addReminder(
      const ReminderConfig(
        id: 'quran',
        title: 'Учить Коран',
        prayer: 0,
        offsetMin: 0,
        anchor: 'clock',
        fixedHour: 12,
        fixedMinute: 10,
      ),
    );
    await tester.pumpWidget(JadwalApp(state: app, schedule: schedule));
    await frames(tester);
    (tester.state(find.byType(HomeScreen)) as dynamic).swipeProgress = 1.0;
    await frames(tester);

    // Заметная кнопка-карандаш есть только у личного дела.
    final edit = find.byKey(const ValueKey('deed-edit-custom:quran'));
    expect(edit, findsOneWidget);
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await frames(tester, 30);
    expect(find.byType(ReminderDetailScreen), findsOneWidget);

    final del = find.descendant(
      of: find.byType(ReminderDetailScreen),
      matching: find.text('Удалить напоминание'),
    );
    await tester.scrollUntilVisible(
      del,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ReminderDetailScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(del);
    await frames(tester, 30);
    expect(app.customReminders, isEmpty);
    expect((await AppState.load()).customReminders, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in const [Size(844, 390), Size(667, 375)]) {
    testWidgets('читалка зикров в горизонтали $size без переполнения', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'onboardingDone': true,
        'lang': 'ru',
        'readerPalette': 'auto',
      });
      final (app, schedule) = await completedState('pages');
      await tester.runAsync(AdhkarRepository.load);
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: ScheduleScope(
            service: schedule,
            child: const MaterialApp(
              home: ReaderScreen(collectionId: 'morning'),
            ),
          ),
        ),
      );
      await frames(tester);
      expect(
        find.byKey(const ValueKey('reader-rotate-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('режим «авто» днём даёт светлую бумагу, ночью — тёмную', (
    tester,
  ) async {
    final (app, schedule) = await completedState('pages');
    app.readerPalette = 'auto';
    late ReaderPalette seen;
    await tester.pumpWidget(
      AppScope(
        state: app,
        child: ScheduleScope(
          service: schedule,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                seen = ReaderPalette.current(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    // В фикстуре 12:00 — между восходом (390) и магрибом (1100).
    expect(seen, ReaderPalette.paper);
  });
}
