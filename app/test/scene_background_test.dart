import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/prayer/schedule.dart';
import 'package:jadwal/screens/scene_background.dart';

void main() {
  final times = DayTimes(
    date: DateTime(2026, 7, 22),
    times: const {
      Prayer.fajr: 120,
      Prayer.sunrise: 240,
      Prayer.dhuhr: 720,
      Prayer.asr: 1050,
      Prayer.maghrib: 1210,
      Prayer.isha: 1320,
    },
  );

  test('полуденное небо использует контрастную тёмную палитру', () {
    final foreground = skyForeground(times, 12 * 3600 + 30 * 60);

    expect(foreground.text, const Color(0xFF1B2230));
    expect(foreground.accent, const Color(0xFF7A540B));
  });

  test('нижний экран днём использует светлую атмосферную палитру', () {
    final palette = daySurfacePalette(times, 12 * 3600 + 30 * 60);

    expect(palette.isLight, isTrue);
    expect(palette.colors.ink.computeLuminance(), lessThan(0.08));
    expect(palette.surface.a, greaterThan(0.6));
  });

  test('нижний экран ночью использует тёмную атмосферную палитру', () {
    final palette = daySurfacePalette(times, 23 * 3600);

    expect(palette.isLight, isFalse);
    expect(palette.colors.ink.computeLuminance(), greaterThan(0.7));
    expect(palette.bottom.computeLuminance(), lessThan(0.03));
  });

  test('до Магриба нижний экран сохраняет чистую светлую поверхность', () {
    final palette = daySurfacePalette(
      times,
      (times.times[Prayer.maghrib]! - 25) * 60,
    );

    expect(palette.isLight, isTrue);
    expect(palette.surface.r, greaterThan(0.98));
    expect(palette.surface.g, greaterThan(0.98));
    expect(palette.surface.b, greaterThan(0.98));
    expect(palette.surface.a, closeTo(0xB8 / 255, 0.001));
  });

  test('нижний экран плавно проходит через границу Магриба', () {
    final before = daySurfacePalette(times, (1209 * 60));
    final after = daySurfacePalette(times, (1211 * 60));

    double distance(Color a, Color b) =>
        (a.r - b.r).abs() +
        (a.g - b.g).abs() +
        (a.b - b.b).abs() +
        (a.a - b.a).abs();

    // За две минуты палитра должна лишь немного сдвинуть оттенок, а не
    // перескочить из готовой дневной темы в готовую ночную.
    expect(distance(before.top, after.top), lessThan(0.08));
    expect(distance(before.bottom, after.bottom), lessThan(0.08));
    expect(distance(before.surface, after.surface), lessThan(0.08));
  });

  test('текст карточек остаётся читаемым вокруг Магриба', () {
    for (final offset in [-30, -25, -15, 0, 15]) {
      final palette = daySurfacePalette(
        times,
        (times.times[Prayer.maghrib]! + offset) * 60,
      );
      final backgrounds = [
        compositeOver(palette.surface, palette.top),
        compositeOver(palette.surface, palette.middle),
        compositeOver(palette.surface, palette.bottom),
      ];

      for (final textColor in [
        palette.colors.ink,
        palette.colors.sub,
        palette.colors.faint,
        palette.colors.gold,
      ]) {
        final minimumContrast = backgrounds
            .map((background) => colorContrastRatio(textColor, background))
            .reduce((a, b) => a < b ? a : b);
        expect(
          minimumContrast,
          greaterThanOrEqualTo(4.5),
          reason: 'Недостаточный контраст за $offset минут до/после Магриба',
        );
      }
    }
  });
}
