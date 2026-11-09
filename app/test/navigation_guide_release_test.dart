import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/data/navigation_guide.dart';
import 'package:jadwal/screens/features_guide.dart';
import 'package:jadwal/screens/guided_spotlight.dart';
import 'package:jadwal/screens/home.dart';
import 'package:jadwal/screens/language_picker.dart';
import 'package:jadwal/screens/reminders.dart';
import 'package:jadwal/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'navigation_guide_test.dart' as guide;

void main() {
  setUpAll(() async {
    await guide.loadGuideFonts();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);
  for (final lang in ['ru', 'kz']) {
    testWidgets(
      'small screen $lang: pinned actions are visible without scrolling',
      (t) async {
        final app = await guide.start(t, lang: lang);
        t.view.physicalSize = const Size(320, 568);
        final kz = lang == 'kz';
        var activated = 0;
        final primary = kz ? 'Жалғастыру' : 'Продолжить';
        final secondary = kz ? 'Еске салу қосу' : 'Добавить напоминание';
        await t.pumpWidget(
          AppScope(
            state: app,
            child: MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 568),
                  textScaler: TextScaler.linear(1.8),
                  padding: EdgeInsets.only(top: 24, bottom: 34),
                ),
                child: Scaffold(
                  body: GuidedSpotlight(
                    compact: true,
                    title: kz ? 'Сіздің тұрақтылығыңыз' : 'Ваше постоянство',
                    message: List.filled(
                      8,
                      kz
                          ? 'Күнді басып, мәліметін қараңыз.'
                          : 'Нажмите на день для подробностей.',
                    ).join(' '),
                    action: primary,
                    onAction: () => activated++,
                    secondary: secondary,
                    onSecondary: () => activated++,
                  ),
                ),
              ),
            ),
          ),
        );
        await guide.tick(t);
        final panel = t.getRect(find.byKey(const ValueKey('guide-bubble')));
        for (final label in [
          primary,
          secondary,
          kz ? 'Өткізу' : 'Пропустить',
        ]) {
          final text = find.text(label);
          expect(text.hitTestable(), findsOneWidget);
          final rect = t.getRect(text);
          expect(panel.contains(rect.topLeft), isTrue);
          expect(panel.contains(rect.bottomRight), isTrue);
          final button = find.ancestor(
            of: text,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          );
          expect(t.getSize(button).height, greaterThanOrEqualTo(48));
        }
        await t.tap(find.text(primary));
        await t.tap(find.text(secondary));
        expect(activated, 2);
        await t.tap(find.byKey(const ValueKey('guide-skip')));
        expect(app.navigationGuide.active, isFalse);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$lang: settings, reference and replay available after old-layout migration',
      (t) async {
        final app = await guide.start(t, layout: 'classic', lang: lang);
        app.closeNavigationGuide();
        (t.state(find.byType(HomeScreen)) as dynamic).swipeProgress = 2.0;
        await guide.tick(t);
        await t.tap(find.byKey(app.navigationGuide.target('page-settings')));
        await guide.tick(t);
        final reference = find.text(
          lang == 'ru' ? 'Возможности приложения' : 'Қосымша мүмкіндіктері',
        );
        await t.ensureVisible(reference);
        await t.tap(reference);
        await guide.tick(t);
        expect(find.byType(FeaturesGuideScreen), findsOneWidget);
        await t.tap(
          find.text(
            lang == 'ru' ? 'Жесты и кнопки' : 'Қимылдар мен батырмалар',
          ),
        );
        await guide.tick(t);
        expect(app.navigationGuide.step, GuideStep.welcome);
        expect(app.dayLayout, 'pages');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$lang: independent editor tutorial starts once and never creates a task',
      (t) async {
        final app = await guide.start(t, lang: lang);
        app.closeNavigationGuide();
        (t.state(find.byType(HomeScreen)) as dynamic).swipeProgress = 1.0;
        await guide.tick(t);
        final add = find.byKey(app.navigationGuide.target('page-add'));
        await t.tap(add);
        await guide.tick(t);
        final g = app.navigationGuide;
        expect(g.step, GuideStep.prayer);
        expect(find.byType(ReminderEditorScreen), findsOneWidget);
        expect(t.testTextInput.isVisible, isFalse);
        await t.tap(find.byKey(g.target('form-prayer')));
        await guide.tick(t);
        expect(g.step, GuideStep.clock);
        await t.tap(find.byKey(g.target('form-clock')));
        await guide.tick(t);
        expect(g.step, GuideStep.formDone);
        if (lang == 'ru') {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/learning_schedule_ru.png'),
          );
        }
        await t.tap(
          find.text(lang == 'ru' ? 'Продолжить создание' : 'Істі баптауға өту'),
        );
        await guide.tick(t);
        expect(g.active, isFalse);
        expect(find.byType(ReminderEditorScreen), findsOneWidget);
        expect(app.customReminders, isEmpty);
        Navigator.of(
          t.element(find.byType(ReminderEditorScreen)),
          rootNavigator: true,
        ).pop();
        await guide.tick(t);
        await t.tap(add);
        await guide.tick(t);
        expect(g.active, isFalse);
        expect((await AppState.load()).reminderEditorGuideSeen, isTrue);
        await t.tap(find.byIcon(CupertinoIcons.question));
        await guide.tick(t);
        expect(g.step, GuideStep.prayer);
        expect(t.testTextInput.isVisible, isFalse);
        Navigator.of(
          t.element(find.byType(ReminderEditorScreen)),
          rootNavigator: true,
        ).pop();
        await guide.tick(t);
        expect(g.active, isFalse);
        expect(app.customReminders, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'first editor opened deliberately during main tour resumes at calendar',
    (t) async {
      final app = await guide.start(t);
      await guide.toAdd(t);
      await t.tap(find.byKey(app.navigationGuide.target('page-add')));
      await guide.tick(t);
      expect(app.navigationGuide.step, GuideStep.prayer);
      Navigator.of(
        t.element(find.byType(ReminderEditorScreen)),
        rootNavigator: true,
      ).pop();
      await guide.tick(t);
      expect(app.navigationGuide.step, GuideStep.calendarSwipe);
      expect(app.customReminders, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'information spotlight hides background controls from accessibility',
    (t) async {
      final handle = t.ensureSemantics();
      try {
        SharedPreferences.setMockInitialValues({});
        final app = await AppState.load();
        await t.pumpWidget(
          AppScope(
            state: app,
            child: MaterialApp(
              home: Scaffold(
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    TextButton(
                      onPressed: () {},
                      child: const Text('Скрытое действие'),
                    ),
                    const Positioned.fill(
                      child: GuidedSpotlight(
                        title: 'Объяснение',
                        message: 'Текст',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await guide.tick(t);
        expect(find.semantics.byLabel('Скрытое действие'), findsNothing);
        expect(find.semantics.byLabel('Пропустить обучение'), findsOne);
        await t.pumpWidget(const SizedBox());
      } finally {
        handle.dispose();
      }
    },
  );
  testWidgets('tutorial body and skip meet text contrast on paper', (t) async {
    final app = await guide.start(t);
    await guide.openSwipe(t);
    final text = t.widget<Text>(
      find.text(
        'Пять намазов и восход. Нажмите на время, чтобы настроить уведомление.',
      ),
    );
    final ratio =
        (JColors.light.bg.computeLuminance() + .05) /
        (text.style!.color!.computeLuminance() + .05);
    expect(ratio, greaterThanOrEqualTo(4.5));
    expect(
      t
          .widget<TextButton>(find.byKey(const ValueKey('guide-skip')))
          .style!
          .foregroundColor!
          .resolve({}),
      JColors.light.ink,
    );
    app.closeNavigationGuide();
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('accessible actions operate independent form without saving', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    try {
      final app = await guide.start(t);
      app.closeNavigationGuide();
      (t.state(find.byType(HomeScreen)) as dynamic).swipeProgress = 1.0;
      await guide.tick(t);
      await t.tap(find.byKey(app.navigationGuide.target('page-add')));
      await guide.tick(t);
      for (final label in [
        'Выбрать время намаза',
        'Выбрать точное время',
        'Продолжить создание',
      ]) {
        t.semantics.tap(find.semantics.byLabel(label));
        await guide.tick(t);
      }
      expect(app.navigationGuide.active, isFalse);
      expect(find.byType(ReminderEditorScreen), findsOneWidget);
      expect(app.customReminders, isEmpty);
      await t.pumpWidget(const SizedBox());
    } finally {
      handle.dispose();
    }
  });
  testWidgets(
    'Reduce Motion keeps hand still; alternative buttons navigate real pages',
    (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final app = await guide.start(t);
      final hand = find.byKey(const ValueKey('guide-swipe-hand'));
      final before = t.getTopLeft(hand);
      await t.pump(const Duration(milliseconds: 500));
      expect(t.getTopLeft(hand), before);
      await t.tap(find.text('Открыть кнопкой'));
      await t.pump();
      expect(app.navigationGuide.step, GuideStep.times);
      expect((t.state(find.byType(HomeScreen)) as dynamic).swipeProgress, 1);
      expect(app.navigationGuide.moving, isFalse);
      await guide.tick(t);
      await guide.next(t);
      await guide.next(t);
      await guide.next(t);
      await t.tap(find.text('Открыть кнопкой'));
      await t.pump();
      expect(app.navigationGuide.step, GuideStep.calendar);
      expect((t.state(find.byType(HomeScreen)) as dynamic).swipeProgress, 2);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'appearance lesson opens actual themes without changing selection',
    (t) async {
      final app = await guide.start(t);
      final scene = app.homeScene;
      await guide.toCalendar(t);
      await guide.next(t);
      await t.tap(find.text('Посмотреть темы'));
      await guide.tick(t);
      expect(find.byType(AppearancePicker), findsOneWidget);
      expect(app.homeScene, scene);
      expect(app.navigationGuide.step, GuideStep.appearancePicker);
      Navigator.of(
        t.element(find.byType(AppearancePicker)),
        rootNavigator: true,
      ).pop();
      await guide.tick(t);
      expect(app.navigationGuide.step, GuideStep.returnDay);
      expect(app.homeScene, scene);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'accessible calendar action opens real day details then resumes',
    (t) async {
      final handle = t.ensureSemantics();
      try {
        final app = await guide.start(t);
        await guide.toCalendar(t);
        t.semantics.tap(find.semantics.byLabel('Посмотреть дела сегодня'));
        await guide.tick(t);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(app.navigationGuide.step, GuideStep.calendar);
        Navigator.of(
          t.element(find.byType(HomeScreen)),
          rootNavigator: true,
        ).pop();
        await guide.tick(t);
        await guide.next(t);
        expect(app.navigationGuide.step, GuideStep.appearance);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      } finally {
        handle.dispose();
      }
    },
  );
  for (final lang in ['ru', 'kz']) {
    testWidgets(
      'small phone $lang: actual calendar Skip stays visible with large text',
      (t) async {
        final app = await guide.start(t, lang: lang);
        t.view.physicalSize = const Size(320, 568);
        t.platformDispatcher.textScaleFactorTestValue = 1.8;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await guide.tick(t);
        await guide.toCalendar(t, lang);
        expect(app.navigationGuide.step, GuideStep.calendar);
        final skip = find.byKey(const ValueKey('guide-skip'));
        expect(skip.hitTestable(), findsOneWidget);
        expect(t.getRect(skip).bottom, lessThanOrEqualTo(568 - 34));
        expect(t.takeException(), isNull);
        await t.tap(skip);
        expect(app.navigationGuide.active, isFalse);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
