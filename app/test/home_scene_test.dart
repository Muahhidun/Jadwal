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

  test('убранная «Природа» превращается в «Степь», «Орнамент» — в Мекку', () {
    expect(HomeScene.fromStorage('nature'), HomeScene.steppe);
    expect(HomeScene.fromStorage('ornament'), HomeScene.mecca);
    expect(HomeScene.fromStorage('astana'), HomeScene.astana);
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
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
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
      if (scene != HomeScene.mecca) {
        await expectLater(
          find.byType(SceneBackground),
          matchesGoldenFile('goldens/home_scene_${scene.name}_393x852.png'),
        );
      }
    }
  });
}
