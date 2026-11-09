import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/data/navigation_guide.dart';
import 'package:jadwal/main.dart';
import 'package:jadwal/prayer/schedule_service.dart';
import 'package:jadwal/screens/features_guide.dart';
import 'package:jadwal/screens/reminders.dart';
import 'package:jadwal/screens/swipe_lesson.dart';
import 'widget_test.dart' as fixtures;

Future<void> tick(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 2200));
  await t.pump(const Duration(milliseconds: 150));
}

Future<void> finishQibla(WidgetTester t, String lang) async {
  await t.tap(find.text(lang == 'ru' ? 'Готово' : 'Дайын'));
  await tick(t);
}

Future<AppState> start(
  WidgetTester t, {
  String layout = 'pages',
  String lang = 'ru',
}) async {
  t.view.physicalSize = const Size(393, 852);
  t.view.devicePixelRatio = 1;
  t.view.padding = const FakeViewPadding(top: 59, bottom: 34);
  t.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPadding);
  addTearDown(t.view.resetViewPadding);
  SharedPreferences.setMockInitialValues({
    'onboardingDone': true,
    'lang': lang,
    'dayLayout': layout,
    'pagesDiscoveryV1Seen': true,
  });
  final app = await AppState.load();
  await t.pumpWidget(
    JadwalApp(state: app, schedule: await fixtures.demoSchedule()),
  );
  await tick(t);
  app.navigationGuide.offer();
  await tick(t);
  await t.tap(find.text(lang == 'kz' ? 'Көрсетіңіз' : 'Показать'));
  await tick(t);
  return app;
}

Future<void> openSwipe(WidgetTester t, [String lang = 'ru']) async {
  await t.tap(find.text(lang == 'ru' ? 'Открыть кнопкой' : 'Батырмамен ашу'));
  await tick(t);
}

Future<void> next(WidgetTester t, [String lang = 'ru']) async {
  await t.tap(find.text(lang == 'ru' ? 'Дальше' : 'Әрі қарай'));
  await tick(t);
}

Future<void> toAdd(WidgetTester t, [String lang = 'ru']) async {
  await openSwipe(t, lang);
  await next(t, lang);
  await next(t, lang);
}

Future<void> toCalendar(WidgetTester t, [String lang = 'ru']) async {
  await toAdd(t, lang);
  await next(t, lang);
  await openSwipe(t, lang);
}

Future<void> loadGuideFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final entry in {
    'Manrope': 'assets/fonts/Manrope.ttf',
    'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    'Inter': 'assets/fonts/Inter.ttf',
    'Literata': 'assets/fonts/Literata.ttf',
    'packages/cupertino_icons/CupertinoIcons':
        'packages/cupertino_icons/assets/CupertinoIcons.ttf',
  }.entries) {
    await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value))).load();
  }
}

void main() {
  setUpAll(loadGuideFonts);
  test('route advances only at real destinations; editor is independent', () {
    final g = NavigationGuide()..begin(usePages: true);
    g.settled(0);
    expect(g.step, GuideStep.day);
    g.settled(1);
    expect(g.step, GuideStep.times);
    g.go(GuideStep.calendarSwipe);
    g.settled(1);
    expect(g.step, GuideStep.calendarSwipe);
    g.settled(2);
    expect(g.step, GuideStep.calendar);
    g.go(GuideStep.returnDay);
    g.settled(1);
    expect(g.step, GuideStep.returnHome);
    g.settled(0);
    expect(g.step, GuideStep.qibla);
    g.settled(-1);
    expect(g.step, GuideStep.finish);
    g.beginReminder();
    g.editorClosed();
    expect(g.step, GuideStep.idle);
    g.begin(usePages: true);
    g.settled(-1);
    expect(g.step, GuideStep.idle);
  });
  test(
    'dismissal persists and layout migration preserves completion history',
    () async {
      SharedPreferences.setMockInitialValues({
        'onboardingDone': true,
        'dayLayout': 'classic',
        'navigationGuidePendingV1': true,
        'cityName': 'Алматы',
        'done:2026-7-3': ['morning'],
      });
      final app = await AppState.load();
      app.navigationGuide.offer();
      app.closeNavigationGuide();
      final loaded = await AppState.load();
      expect(loaded.navigationGuidePending, isFalse);
      expect(loaded.navigationGuide.active, isFalse);
      expect(loaded.dayLayout, 'pages');
      expect(loaded.doneOn(DateTime(2026, 7, 3)), contains('morning'));
      expect(loaded.customReminders, isEmpty);
    },
  );
  testWidgets('new-user invitation remains optional, no repeat after start', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'navigationGuidePendingV1': true,
    });
    final app = await AppState.load();
    await t.pumpWidget(
      JadwalApp(state: app, schedule: await fixtures.demoSchedule()),
    );
    await tick(t);
    expect(app.navigationGuide.step, GuideStep.welcome);
    await t.tap(find.text('Показать'));
    await tick(t);
    expect(app.navigationGuide.step, GuideStep.day);
    expect((await AppState.load()).navigationGuidePending, isFalse);
    expect(app.customReminders, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
  for (final stored in ['pages', 'classic']) {
    for (final lang in ['ru', 'kz']) {
      testWidgets(
        '$stored/$lang: schedule, deeds, full calendar and three return swipes',
        (t) async {
          final app = await start(t, layout: stored, lang: lang);
          final g = app.navigationGuide;
          expect(find.byType(SwipeLesson), findsOneWidget);
          if (stored == 'pages' && lang == 'ru') {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('goldens/learning_home_ru.png'),
            );
          }
          await t.dragFrom(const Offset(180, 430), const Offset(0, -230));
          await tick(t);
          expect(g.step, GuideStep.times);
          expect(find.byKey(g.target('prayer-times')), findsOneWidget);
          if (stored == 'pages' && lang == 'ru') {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('goldens/learning_times_ru.png'),
            );
          }
          await next(t, lang);
          expect(g.step, GuideStep.deeds);
          if (stored == 'pages' && lang == 'ru') {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('goldens/learning_deeds_ru.png'),
            );
          }
          await next(t, lang);
          expect(g.step, GuideStep.add);
          if (stored == 'pages' && lang == 'ru') {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('goldens/learning_add_ru.png'),
            );
          }
          await next(t, lang);
          expect(g.step, GuideStep.calendarSwipe);
          await t.dragFrom(const Offset(180, 430), const Offset(0, -230));
          await tick(t);
          expect(g.step, GuideStep.calendar);
          if (stored == 'pages' && lang == 'kz') {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('goldens/learning_calendar_kz.png'),
            );
          }
          await next(t, lang);
          expect(g.step, GuideStep.appearance);
          if (stored == 'pages' && lang == 'ru') {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('goldens/learning_appearance_ru.png'),
            );
          }
          await next(t, lang);
          for (final step in [
            GuideStep.returnDay,
            GuideStep.returnHome,
            GuideStep.qibla,
          ]) {
            expect(g.step, step);
            await t.dragFrom(const Offset(180, 300), const Offset(0, 230));
            await tick(t);
          }
          expect(g.step, GuideStep.finish);
          expect(find.byType(ReminderEditorScreen), findsNothing);
          await finishQibla(t, lang);
          expect(g.active, isFalse);
          expect(app.dayLayout, 'pages');
          expect(app.customReminders, isEmpty);
          expect(app.reminderEditorGuideSeen, isFalse);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets('reference offers replay, not the removed slide tour', (t) async {
    SharedPreferences.setMockInitialValues({'onboardingDone': true});
    final app = await AppState.load();
    await t.pumpWidget(
      AppScope(
        state: app,
        child: ScheduleScope(
          service: await fixtures.demoSchedule(),
          child: const MaterialApp(home: FeaturesGuideScreen()),
        ),
      ),
    );
    await tick(t);
    expect(find.text('Жесты и кнопки'), findsOneWidget);
    expect(find.text('Знакомство с возможностями'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
