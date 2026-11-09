import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule.dart';
import 'package:jadwal/screens/scene_background.dart';
import 'package:jadwal/theme/home_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final times = DayTimes(
    date: DateTime(2026, 9, 25),
    times: const {
      Prayer.fajr: 300,
      Prayer.sunrise: 390,
      Prayer.dhuhr: 720,
      Prayer.asr: 960,
      Prayer.maghrib: 1110,
      Prayer.isha: 1200,
    },
  );

  test('тема главного экрана сохраняется отдельно от города', () async {
    SharedPreferences.setMockInitialValues({
      'cityName': 'Екібастұз қаласы',
      'cityLatStr': '51.72',
      'cityLngStr': '75.32',
    });
    final state = await AppState.load();

    expect(state.homeScene, HomeScene.mecca);
    state.homeScene = HomeScene.medina;

    final restored = await AppState.load();
    expect(restored.homeScene, HomeScene.medina);
    expect(restored.city.name, 'Екібастұз қаласы');
  });

  test('убранные оформления переводятся на доступную тему', () {
    expect(HomeScene.fromStorage('nature'), HomeScene.steppe);
    expect(HomeScene.fromStorage('ornament'), HomeScene.mecca);
    expect(HomeScene.fromStorage('minimal'), HomeScene.mecca);
    expect(HomeScene.fromStorage('astana'), HomeScene.astana);
  });

  test('темы используют согласованные кадры и масштаб', () {
    for (final scene in [
      HomeScene.mecca,
      HomeScene.medina,
      HomeScene.astana,
      HomeScene.steppe,
    ]) {
      expect(scene.photoSlots, ['sunrise', 'day', 'sunset', 'night']);
    }
    for (final scene in [HomeScene.mecca, HomeScene.medina]) {
      expect(scene.photoZoom, 1.0);
    }
  });

  test('кадры смешиваются без постоянной ночной подложки', () {
    expect(photoPhaseWeights(0), (day: 0.0, warm: 0.0, night: 1.0));
    expect(photoPhaseWeights(1), (day: 1.0, warm: 0.0, night: 0.0));
    for (var i = 0; i <= 100; i++) {
      final light = i / 100;
      final weights = photoPhaseWeights(light);
      expect(weights.day + weights.warm + weights.night, closeTo(1, 1e-12));
      if (light >= 0.28) expect(weights.night, 0);
      if (i > 0) {
        final previous = photoPhaseWeights((i - 1) / 100);
        expect((weights.day - previous.day).abs(), lessThan(0.07));
        expect((weights.warm - previous.warm).abs(), lessThan(0.07));
        expect((weights.night - previous.night).abs(), lessThan(0.07));
      }
    }
  });

  testWidgets('все оформления главного экрана рисуются', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final scene in HomeScene.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SceneBackground(
                  progress: 0,
                  screenHeight: 852,
                  times: times,
                  nowSec: 12 * 3600,
                  city: kDefaultCity,
                  variant: scene,
                ),
              ],
            ),
          ),
        ),
      );
      // Scene artwork is decoded by dart:ui outside the fake test clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 900)),
      );
      if (scene == HomeScene.steppe) {
        // В начале появления солнце проходит через середину неба. Этот кадр
        // защищает от возврата прямоугольного шва вокруг его свечения.
        await tester.pump(const Duration(milliseconds: 350));
        await expectLater(
          find.byType(SceneBackground),
          matchesGoldenFile('goldens/home_scene_steppe_intro_393x852.png'),
        );
        await tester.pump(const Duration(milliseconds: 1250));
      } else {
        await tester.pump(const Duration(milliseconds: 1600));
      }
      expect(tester.takeException(), isNull, reason: scene.name);
      await expectLater(
        find.byType(SceneBackground),
        matchesGoldenFile('goldens/home_scene_${scene.name}_393x852.png'),
      );
    }
  });

  testWidgets('Мекка утром и вечером без ночной кромки', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final (label, seconds) in [
      ('morning', 8 * 3600 + 39 * 60),
      ('evening', 18 * 3600),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SceneBackground(
                  progress: 0,
                  screenHeight: 852,
                  times: times,
                  nowSec: seconds,
                  city: kDefaultCity,
                  variant: HomeScene.mecca,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 900)),
      );
      await tester.pump(const Duration(milliseconds: 1600));
      await expectLater(
        find.byType(SceneBackground),
        matchesGoldenFile('goldens/home_scene_mecca_$label.png'),
      );
    }
  });

  testWidgets('Мекка не обрывается на начале медленного свайпа', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final (name, progress) in [('tiny', 0.01), ('partial', 0.10)]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SceneBackground(
                  progress: progress,
                  screenHeight: 852,
                  times: times,
                  nowSec: 23 * 3600,
                  city: kDefaultCity,
                  variant: HomeScene.mecca,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 900)),
      );
      await tester.pump(const Duration(milliseconds: 1600));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(SceneBackground),
        matchesGoldenFile('goldens/home_scene_mecca_swipe_$name.png'),
      );
    }
  });

  testWidgets('остальные фото-темы не обрываются при медленном свайпе', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final scene in [
      HomeScene.medina,
      HomeScene.astana,
      HomeScene.steppe,
    ]) {
      for (final (name, progress) in [('tiny', 0.01), ('partial', 0.10)]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  SceneBackground(
                    progress: progress,
                    screenHeight: 852,
                    times: times,
                    nowSec: 12 * 3600,
                    city: kDefaultCity,
                    variant: scene,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 900)),
        );
        await tester.pump(const Duration(milliseconds: 1600));
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(SceneBackground),
          matchesGoldenFile('goldens/home_scene_${scene.name}_swipe_$name.png'),
        );
      }
    }
  });
}
