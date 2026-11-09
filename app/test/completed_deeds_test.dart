import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/adhkar.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/main.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule_service.dart';
import 'package:jadwal/screens/celebration.dart';
import 'package:jadwal/screens/feature_tour.dart';
import 'package:jadwal/screens/home.dart';
import 'package:jadwal/screens/language_picker.dart';
import 'package:jadwal/screens/reader.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> frames(WidgetTester tester, [int count = 20]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<(AppState, ScheduleService)> completedState(String layout) async {
  SharedPreferences.setMockInitialValues({
    'onboardingDone': true,
    'pagesDiscoveryV1Seen': true,
    'featureTourPendingV1': true,
    'contextHint:v1:reader-palette': true,
    'contextHint:v1:appearance': true,
    'lang': 'ru',
    'dayLayout': layout,
    'done:${AppState.dayKey(DateTime.now())}': ['morning', 'evening'],
  });
  final app = await AppState.load();
  final schedule = ScheduleService(
    await SharedPreferences.getInstance(),
    now: () => DateTime(2026, 10, 1, 12),
  );
  schedule.preload(kDefaultCity, 2026, {
    '2026-10-01': [300, 390, 720, 960, 1100, 1200],
    '2026-10-02': [300, 390, 720, 960, 1100, 1200],
  });
  return (app, schedule);
}

void main() {
  for (final layout in ['classic', 'pages']) {
    testWidgets('$layout: выполненные зикры открываются без сброса галочки', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (app, schedule) = await completedState(layout);
      await tester.runAsync(AdhkarRepository.load);
      await tester.pumpWidget(JadwalApp(state: app, schedule: schedule));
      await frames(tester);
      expect(find.byType(FeatureTourScreen), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-done-morning')));
      await frames(tester);
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(app.isDone('morning'), isTrue);
      Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
      await frames(tester);
      (tester.state(find.byType(HomeScreen)) as dynamic).swipeProgress = 1.0;
      await frames(tester);

      for (final id in ['morning', 'evening']) {
        final key = 'page-deed-$id';
        await tester.tap(find.byKey(ValueKey(key)));
        await frames(tester);
        expect(find.byType(ReaderScreen), findsOneWidget);
        expect(
          tester.widget<ReaderScreen>(find.byType(ReaderScreen)).collectionId,
          id,
        );
        expect(find.byKey(const ValueKey('reader-title')), findsOneWidget);
        expect(app.isDone(id), isTrue);
        Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
        await frames(tester);
        expect(app.isDone(id), isTrue);
      }
      expect(app.doneOn(DateTime.now()), ['morning', 'evening']);
      if (layout == 'pages') {
        (tester.state(find.byType(HomeScreen)) as dynamic).swipeProgress = 2.0;
        await frames(tester);
        await tester.tap(find.text('Настройки'));
        await frames(tester);
        await tester.scrollUntilVisible(
          find.text('Возможности приложения'),
          160,
        );
        expect(find.text('Возможности приложения'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$layout: галочку личного дела можно снять и поставить снова', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (app, schedule) = await completedState(layout);
      app.addReminder(
        const ReminderConfig(
          id: 'mosque',
          title: 'Посетить мечеть',
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
      final task = find.text('Посетить мечеть');
      for (final expected in [true, false, true]) {
        await tester.ensureVisible(task);
        await tester.tap(task);
        await frames(tester);
        expect(app.isDone('custom:mosque'), expected);
        expect(app.isDone('morning'), true);
        expect(app.isDone('evening'), true);
      }
      expect((await AppState.load()).isDone('custom:mosque'), true);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('снятие галочки сохраняется и не затрагивает другие дни/дела', () async {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    SharedPreferences.setMockInitialValues({
      'done:${AppState.dayKey(today)}': ['morning', 'custom:mosque'],
      'done:${AppState.dayKey(yesterday)}': ['evening', 'custom:mosque'],
    });
    final app = await AppState.load();
    app.toggleDone('custom:mosque');
    expect((await AppState.load()).doneOn(today), ['morning']);
    expect(app.doneOn(yesterday), ['evening', 'custom:mosque']);
    app.markDone('custom:mosque');
    app.markDone('custom:mosque');
    expect((await AppState.load()).doneOn(today), ['morning', 'custom:mosque']);
  });

  testWidgets('повторное завершение чтения не создаёт нового выполнения', (
    tester,
  ) async {
    final (app, schedule) = await completedState('classic');
    final collections = await tester.runAsync(AdhkarRepository.load);
    final last = collections!['morning']!.items.length - 1;
    await tester.pumpWidget(
      AppScope(
        state: app,
        child: ScheduleScope(
          service: schedule,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReaderScreen(
                      collectionId: 'morning',
                      initialIndex: last,
                    ),
                  ),
                ),
                child: const Text('Повторно читать'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Повторно читать'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-next-action')));
    await tester.pumpAndSettle();
    if (find.byType(ReaderScreen).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('reader-next-action')));
      await tester.pumpAndSettle();
    }
    expect(find.byType(ReaderScreen), findsNothing);
    expect(find.byType(CelebrationScreen), findsNothing);
    expect(app.doneOn(DateTime.now()), ['morning', 'evening']);
  });

  for (final lang in ['ru', 'kz']) {
    testWidgets('$lang: в оформлении нет дубликата возможностей', (
      tester,
    ) async {
      final (app, schedule) = await completedState('classic');
      app.lang = lang;
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: ScheduleScope(
            service: schedule,
            child: const MaterialApp(home: AppearancePicker()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('Возможности приложения'), findsNothing);
      expect(find.text('Қосымша мүмкіндіктері'), findsNothing);
      expect(find.text(lang == 'ru' ? 'Страницы' : 'Беттер'), findsNothing);
    });
  }
}
