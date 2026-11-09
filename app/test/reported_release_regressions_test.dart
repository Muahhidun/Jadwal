import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/data/navigation_guide.dart';
import 'package:jadwal/screens/guided_spotlight.dart';
import 'package:jadwal/screens/home.dart';
import 'package:jadwal/screens/language_picker.dart';
import 'package:jadwal/screens/qibla_screen.dart';
import 'package:jadwal/screens/reminders.dart';
import 'navigation_guide_test.dart' as guide;

void main() {
  setUpAll(guide.loadGuideFonts);
  for (final lang in ['ru', 'kz']) {
    for (final seen in [false, true]) {
      testWidgets('$lang: reminder detour (seen=$seen) resumes main tour', (
        t,
      ) async {
        final app = await guide.start(t, lang: lang);
        if (seen) {
          app.beginReminderGuide();
          app.closeNavigationGuide();
          app.beginNavigationGuide(usePages: true);
          await guide.tick(t);
        }
        await guide.toAdd(t, lang);
        await t.tap(find.byKey(app.navigationGuide.target('page-add')));
        await guide.tick(t);
        expect(find.byType(ReminderEditorScreen), findsOneWidget);
        if (!seen) {
          await t.tap(find.byKey(const ValueKey('guide-skip')));
          await guide.tick(t);
        }
        Navigator.of(
          t.element(find.byType(ReminderEditorScreen)),
          rootNavigator: true,
        ).pop();
        await guide.tick(t);
        expect(app.navigationGuide.step, GuideStep.calendarSwipe);
        await guide.openSwipe(t, lang);
        expect(app.navigationGuide.step, GuideStep.calendar);
        expect(app.customReminders, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
    testWidgets('$lang: actual Settings target guides actual Appearance row', (
      t,
    ) async {
      final app = await guide.start(t, lang: lang);
      final scene = app.homeScene;
      await guide.toCalendar(t, lang);
      await guide.next(t, lang);
      await t.tap(find.byKey(app.navigationGuide.target('page-settings')));
      await guide.tick(t);
      final hint = t.widget<GuidedSpotlight>(find.byType(GuidedSpotlight));
      expect(
        hint.target,
        same(app.navigationGuide.target('settings-appearance')),
      );
      final row = find.byKey(app.navigationGuide.target('settings-appearance'));
      expect(row.hitTestable(), findsOneWidget);
      if (lang == 'ru') {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/learning_settings_row_ru.png'),
        );
      }
      await t.tap(row);
      await guide.tick(t);
      expect(find.byType(AppearancePicker), findsOneWidget);
      expect(app.homeScene, scene);
      Navigator.of(
        t.element(find.byType(AppearancePicker)),
        rootNavigator: true,
      ).pop();
      await guide.tick(t);
      expect(app.navigationGuide.step, GuideStep.returnDay);
      expect(app.homeScene, scene);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets('finishing editor lesson preserves main continuation and data', (
    t,
  ) async {
    final app = await guide.start(t);
    await guide.toAdd(t);
    await t.tap(find.byKey(app.navigationGuide.target('page-add')));
    await guide.tick(t);
    await t.tap(find.byKey(app.navigationGuide.target('form-prayer')));
    await guide.tick(t);
    await t.tap(find.byKey(app.navigationGuide.target('form-clock')));
    await guide.tick(t);
    await t.tap(find.text('Продолжить создание'));
    await guide.tick(t);
    expect(app.navigationGuide.inForm, isFalse);
    expect(find.byType(ReminderEditorScreen), findsOneWidget);
    Navigator.of(
      t.element(find.byType(ReminderEditorScreen)),
      rootNavigator: true,
    ).pop();
    await guide.tick(t);
    expect(app.navigationGuide.step, GuideStep.calendarSwipe);
    expect(app.customReminders, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'closing settings early permits retry; Skip does not revive guide',
    (t) async {
      final app = await guide.start(t);
      await guide.toCalendar(t);
      await guide.next(t);
      final settings = find.byKey(app.navigationGuide.target('page-settings'));
      await t.tap(settings);
      await guide.tick(t);
      Navigator.of(
        t.element(find.byType(HomeScreen)),
        rootNavigator: true,
      ).pop();
      await guide.tick(t);
      expect(app.navigationGuide.step, GuideStep.appearance);
      await t.tap(settings);
      await guide.tick(t);
      await t.tap(find.byKey(const ValueKey('guide-skip')));
      await guide.tick(t);
      Navigator.of(
        t.element(find.byType(HomeScreen)),
        rootNavigator: true,
      ).pop();
      await guide.tick(t);
      expect(app.navigationGuide.active, isFalse);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'small display: settings lesson actions stay accessible at 180% text',
    (t) async {
      final app = await guide.start(t);
      t.view.physicalSize = const Size(320, 568);
      t.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await guide.tick(t);
      await guide.toCalendar(t);
      await guide.next(t);
      await t.tap(find.byKey(app.navigationGuide.target('page-settings')));
      await guide.tick(t);
      final skip = find.byKey(const ValueKey('guide-skip'));
      expect(skip.hitTestable(), findsOneWidget);
      expect(find.text('Открыть').hitTestable(), findsOneWidget);
      expect(t.getRect(skip).bottom, lessThanOrEqualTo(568 - 34));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('map keeps final lesson until explicit return home', (t) async {
    final app = await guide.start(t);
    app.navigationGuide.go(GuideStep.finish);
    var returned = 0;
    await t.pumpWidget(
      AppScope(
        state: app,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'Manrope',
            fontFamilyFallback: const ['Inter'],
          ),
          home: ColoredBox(
            color: const Color(0xFF1E3045),
            child: QiblaView(embedded: true, onGuideDone: () => returned++),
          ),
        ),
      ),
    );
    await guide.tick(t);
    await t.tap(find.text('Открыть карту'));
    await guide.tick(t);
    expect(app.navigationGuide.step, GuideStep.qiblaMap);
    final back = find.byKey(const ValueKey('qibla-home-button'));
    expect(back.hitTestable(), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/learning_map_return_ru.png'),
    );
    await t.tap(back);
    await guide.tick(t);
    expect(returned, 1);
    expect(app.navigationGuide.active, isFalse);
    expect(t.takeException(), isNull);
    // Returning remains available after the lesson has finished, too.
    await t.tap(back);
    await guide.tick(t);
    expect(returned, 2);
    await t.pumpWidget(const SizedBox());
  });
}
