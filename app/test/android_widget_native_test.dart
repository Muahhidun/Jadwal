import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android widget has compact and wide responsive layouts', () {
    final provider = File(
      'android/app/src/main/kotlin/kz/dauam/DauamPrayerWidgetProvider.kt',
    ).readAsStringSync();
    final compact = File(
      'android/app/src/main/res/layout/widget_prayer_small.xml',
    ).readAsStringSync();
    final wide = File(
      'android/app/src/main/res/layout/widget_prayer_wide.xml',
    ).readAsStringSync();

    expect(provider, contains('OPTION_APPWIDGET_MIN_WIDTH'));
    expect(provider, contains('setChronometerCountDown'));
    expect(provider, contains('scheduleRefresh'));
    expect(compact, contains('@+id/widget_countdown'));
    expect(wide, contains('@+id/widget_prayer_6_time'));
  });

  test('Flutter Android bridge persists and refreshes widget snapshot', () {
    final activity = File(
      'android/app/src/main/kotlin/kz/dauam/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('kz.dauam/widgets'));
    expect(activity, contains('DauamPrayerWidgetProvider.saveSnapshot'));
  });

  test('Android tasks widget shows progress and responsive task layouts', () {
    final provider = File(
      'android/app/src/main/kotlin/kz/dauam/DauamTasksWidgetProvider.kt',
    ).readAsStringSync();
    final compact = File(
      'android/app/src/main/res/layout/widget_tasks_small.xml',
    ).readAsStringSync();
    final wide = File(
      'android/app/src/main/res/layout/widget_tasks_wide.xml',
    ).readAsStringSync();

    expect(provider, contains('setProgressBar'));
    expect(provider, contains('OPTION_APPWIDGET_MIN_WIDTH'));
    expect(compact, contains('@+id/widget_task_3'));
    expect(wide, contains('@+id/widget_task_4'));
  });
}
