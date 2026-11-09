import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/data/navigation_guide.dart';
import 'package:jadwal/main.dart';
import 'package:jadwal/notifications/notifications.dart';
import 'package:jadwal/screens/home.dart';
import 'widget_test.dart' as fixtures;

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<AppState> _start(
  WidgetTester tester, {
  String layout = 'classic',
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({'dayLayout': layout});
  final app = await AppState.load();
  await tester.pumpWidget(
    JadwalApp(state: app, schedule: await fixtures.demoSchedule()),
  );
  await tester.tap(find.text('Русский'));
  await _settle(tester);
  return app;
}

class _PermissionService extends NotificationService {
  _PermissionService(super.schedule);
  final answer = Completer<bool>();
  int requests = 0;

  @override
  Future<bool> requestPermission() {
    requests++;
    return answer.future;
  }
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async => call.method == 'isLocationServiceEnabled' ? false : 0,
        );
    gNotifier = null;
  });
  tearDown(() {
    gNotifier = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          null,
        );
  });

  for (final layout in ['classic', 'pages']) {
    testWidgets('$layout: complete first setup opens exactly one home', (
      tester,
    ) async {
      final app = await _start(tester, layout: layout);
      await tester.tap(find.text('Алматы').first);
      await _settle(tester);
      await tester.tap(find.text('Позже'));
      await _settle(tester);
      await tester.tap(find.text('Начать'));
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(app.onboardingDone, isTrue);
      expect(app.navigationGuide.step, GuideStep.welcome);
      expect(
        Navigator.of(tester.element(find.byType(HomeScreen))).canPop(),
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('guide-skip')));
      await _settle(tester);
      await tester.pumpWidget(const SizedBox());

      final restored = await AppState.load();
      await tester.pumpWidget(
        JadwalApp(state: restored, schedule: await fixtures.demoSchedule()),
      );
      await _settle(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Освоимся в Дауам'), findsNothing);
      expect(restored.city.name, 'Алматы');
      expect(restored.dayLayout, 'pages');
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'rapid city selection advances only to notification explanation',
    (tester) async {
      final app = await _start(tester);
      await tester.tap(find.text('Алматы').first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Астана').first);
      await _settle(tester);

      expect(find.text('Разрешить уведомления'), findsOneWidget);
      expect(find.text('Начать'), findsNothing);
      expect(app.city.name, 'Алматы');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a delayed city transition is safe after leaving the screen', (
    tester,
  ) async {
    await _start(tester);
    await tester.tap(find.text('Алматы').first);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'permission result cannot advance a step already left with Later',
    (tester) async {
      await _start(tester);
      await tester.tap(find.text('Алматы').first);
      await _settle(tester);
      final notifier = _PermissionService(await fixtures.demoSchedule());
      gNotifier = notifier;
      await tester.tap(find.text('Разрешить уведомления'));
      await tester.tap(find.text('Разрешить уведомления'));
      await tester.tap(find.text('Позже'));
      await _settle(tester);
      notifier.answer.complete(true);
      await _settle(tester);

      expect(notifier.requests, 1);
      expect(find.text('Начать'), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
