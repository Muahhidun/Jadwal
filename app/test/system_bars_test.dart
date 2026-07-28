import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/theme/system_bars.dart';

void main() {
  test('светлый фон использует тёмные системные индикаторы', () {
    final style = jSystemUiStyle(darkIcons: true);

    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.statusBarBrightness, Brightness.light);
  });

  test('тёмный фон использует светлые системные индикаторы', () {
    final style = jSystemUiStyle(darkIcons: false);

    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.statusBarBrightness, Brightness.dark);
  });
}
