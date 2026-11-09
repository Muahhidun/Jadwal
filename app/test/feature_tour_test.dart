import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/screens/feature_tour.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('completed tour never automatically reopens', () async {
    SharedPreferences.setMockInitialValues({'onboardingDone': true});
    final state = await AppState.load();
    expect(state.shouldShowFeatureTour, false);
    state.startFeatureTour();
    expect((await AppState.load()).shouldShowFeatureTour, true);
    state.markFeatureTourSeen();
    expect((await AppState.load()).shouldShowFeatureTour, false);
  });
  Future<AppState> show(
    WidgetTester tester, {
    String lang = 'ru',
    double scale = 1,
    Size size = const Size(393, 852),
    bool reduce = false,
  }) async {
    SharedPreferences.setMockInitialValues({'lang': lang});
    final state = await AppState.load();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final schedule = ScheduleService(
      await SharedPreferences.getInstance(),
      now: () => DateTime(2026, 10, 1, 12),
    );
    schedule.preload(kDefaultCity, 2026, {
      '2026-10-01': [300, 390, 720, 960, 1100, 1200],
    });
    await tester.pumpWidget(
      ScheduleScope(
        service: schedule,
        child: AppScope(
          state: state,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => FeatureTourScreen.open(context),
                child: const Text('Open'),
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: reduce,
              ),
              child: child!,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('alarm setup offers every prayer without changing settings', (
    tester,
  ) async {
    final state = await show(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Дальше'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Настроить'));
    await tester.pumpAndSettle();
    for (final name in ['Фаджр', 'Зухр', 'Аср', 'Магриб', 'Иша']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(state.alarmEnabled('fajr'), false);
    expect(state.customReminders, isEmpty);
  });
  testWidgets('skip persists and guide can reopen', (tester) async {
    final state = await show(tester);
    expect(state.featureTourSeen, false);
    await tester.tap(find.text('Пропустить'));
    await tester.pumpAndSettle();
    expect((await AppState.load()).featureTourSeen, true);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 5'), findsOneWidget);
  });
  testWidgets('next back and completion preserve settings', (tester) async {
    final state = await show(tester);
    await tester.tap(find.text('Дальше'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 5'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Дальше'));
      await tester.pumpAndSettle();
    }
    expect(state.customReminders, isEmpty);
    expect(state.alarmEnabled('fajr'), false);
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect((await AppState.load()).featureTourSeen, true);
  });
  for (final lang in ['ru', 'kz']) {
    testWidgets('$lang small screen large text reduced motion', (tester) async {
      await show(
        tester,
        lang: lang,
        scale: 2,
        size: const Size(320, 568),
        reduce: true,
      );
      for (var i = 0; i < 5; i++) {
        expect(tester.takeException(), isNull);
        if (i < 4) {
          await tester.tap(find.text(lang == 'ru' ? 'Дальше' : 'Келесі'));
          await tester.pumpAndSettle();
        }
      }
    });
  }
  testWidgets('Android previews do not promise lock screen support', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await show(tester);
    expect(find.text('Экран блокировки'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
