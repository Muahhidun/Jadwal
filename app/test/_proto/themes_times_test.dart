import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule.dart';
import 'package:jadwal/screens/scene_background.dart';
import 'package:jadwal/theme/home_scene.dart';

void main() {
  final times = DayTimes(
    date: DateTime(2026, 9, 30),
    times: const {
      Prayer.fajr: 5 * 60,
      Prayer.sunrise: 6 * 60 + 30,
      Prayer.dhuhr: 12 * 60 + 30,
      Prayer.asr: 16 * 60,
      Prayer.maghrib: 18 * 60 + 30,
      Prayer.isha: 20 * 60,
    },
  );
  testWidgets('фото-темы по времени суток', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final scene in [HomeScene.medina, HomeScene.astana, HomeScene.steppe]) {
      for (final (label, sec) in [
        ('sunrise', 6 * 3600 + 40 * 60),
        ('day', 13 * 3600),
        ('sunset', 18 * 3600 + 20 * 60),
        ('night', 22 * 3600),
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
                    nowSec: sec,
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
        await tester.pump(const Duration(milliseconds: 1700));
        await expectLater(
          find.byType(SceneBackground),
          matchesGoldenFile('theme_${scene.name}_$label.png'),
        );
      }
    }
  });
}
