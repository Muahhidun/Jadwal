import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule_service.dart';
import 'package:jadwal/screens/features_guide.dart';
import 'package:jadwal/screens/language_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _showGuide(WidgetTester tester) async {
  final state = await AppState.load();
  final prefs = await SharedPreferences.getInstance();
  final schedule = ScheduleService(prefs, now: () => DateTime(2026, 10, 1, 12));
  schedule.preload(kDefaultCity, 2026, {
    '2026-10-01': [300, 390, 720, 960, 1100, 1200],
  });
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: ScheduleScope(
        service: schedule,
        child: const MaterialApp(home: FeaturesGuideScreen(root: true)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('новой установке не показываем приглашение поверх онбординга', () async {
    SharedPreferences.setMockInitialValues({});
    final state = await AppState.load();
    state.onboardingDone = true;
    expect(state.shouldShowPagesDiscovery, isFalse);
  });

  test('старый вид переходит в Страницы без лишнего приглашения', () async {
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'firstUseDate': '2026-09-29',
    });
    final state = await AppState.load();
    expect(state.dayLayout, 'pages');
    expect(state.shouldShowPagesDiscovery, isFalse);
    state.pagesDiscoverySeen = true;
    expect((await AppState.load()).shouldShowPagesDiscovery, isFalse);
    expect((await AppState.load()).dayLayout, 'pages');
  });

  test(
    'выбранные ранее Страницы не сбрасываются и не получают приглашение',
    () async {
      SharedPreferences.setMockInitialValues({
        'onboardingDone': true,
        'firstUseDate': '2026-09-29',
        'dayLayout': 'pages',
      });
      final state = await AppState.load();
      expect(state.dayLayout, 'pages');
      expect(state.shouldShowPagesDiscovery, isFalse);
    },
  );

  testWidgets('в справке есть виджеты и напоминания', (tester) async {
    SharedPreferences.setMockInitialValues({'onboardingDone': true});
    await _showGuide(tester);
    expect(find.text('Возможности приложения'), findsOneWidget);
    expect(find.text('Знакомство с возможностями'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Напоминания о молитвах и поклонении'),
      260,
    );
    expect(find.text('Напоминания о молитвах и поклонении'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Виджеты на рабочем столе'), 260);
    expect(find.text('Виджеты на рабочем столе'), findsOneWidget);
  });

  testWidgets('казахская справка остаётся текстовой без кнопки слайдов', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'kz',
    });
    await _showGuide(tester);
    expect(find.text('Қосымша мүмкіндіктері'), findsOneWidget);
    expect(find.text('Мүмкіндіктермен танысу'), findsNothing);
    expect(find.text('Намаз уақыттары'), findsOneWidget);
  });

  testWidgets('справка показывает iPhone-функции только на iOS', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      SharedPreferences.setMockInitialValues({'onboardingDone': true});
      await _showGuide(tester);
      expect(find.text('Арабская озвучка зикров'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Виджеты экрана блокировки'),
        260,
      );
      expect(find.text('Виджеты экрана блокировки'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Dynamic Island'), 260);
      expect(find.text('Dynamic Island'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Siri и «Команды»'), 260);
      expect(find.text('Siri и «Команды»'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android не обещает виджеты экрана блокировки', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({'onboardingDone': true});
      await _showGuide(tester);
      expect(find.text('Виджеты экрана блокировки'), findsNothing);
      expect(find.text('Dynamic Island'), findsNothing);
      await tester.scrollUntilVisible(find.text('Будильник Android'), 260);
      expect(find.text('Будильник Android'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('оформление меняет сцены, а не способ навигации', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'firstUseDate': '2026-09-29',
    });
    final state = await AppState.load();
    final prefs = await SharedPreferences.getInstance();
    final schedule = ScheduleService(
      prefs,
      now: () => DateTime(2026, 10, 1, 12),
    );
    schedule.preload(kDefaultCity, 2026, {
      '2026-10-01': [300, 390, 720, 960, 1100, 1200],
    });
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: ScheduleScope(
          service: schedule,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => AppearancePicker.open(context),
                  child: const Text('Показать подсказку'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Показать подсказку'));
    await tester.pumpAndSettle();
    expect(find.text('Мекка'), findsOneWidget);
    expect(find.text('Классический'), findsNothing);
    expect(find.text('Нижний экран'), findsNothing);
    expect(state.dayLayout, 'pages');
    expect(state.shouldShowPagesDiscovery, isFalse);
  });
}
