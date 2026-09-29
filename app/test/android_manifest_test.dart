import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release manifest declares Android runtime and network permissions', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    for (final permission in <String>[
      'android.permission.ACCESS_COARSE_LOCATION',
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.INTERNET',
      'android.permission.ACCESS_NETWORK_STATE',
      'android.permission.RECEIVE_BOOT_COMPLETED',
      'android.permission.WAKE_LOCK',
      'android.permission.SCHEDULE_EXACT_ALARM',
      'android.permission.USE_FULL_SCREEN_INTENT',
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
    ]) {
      expect(
        manifest,
        contains(permission),
        reason: '$permission must be present in the release manifest',
      );
    }
  });

  test('release manifest restores scheduled notifications after reboot', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('ScheduledNotificationReceiver'));
    expect(manifest, contains('ScheduledNotificationBootReceiver'));
    expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
    expect(manifest, contains('android.intent.action.MY_PACKAGE_REPLACED'));
    expect(manifest, contains('.AlarmRescheduleReceiver'));
  });

  test(
    'native Android alarm owns a lock-screen activity and ringing service',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('.AlarmActivity'));
      expect(manifest, contains('android:showWhenLocked="true"'));
      expect(manifest, contains('android:turnScreenOn="true"'));
      expect(manifest, contains('.AlarmRingingService'));
      expect(manifest, contains('android:foregroundServiceType="specialUse"'));
      expect(manifest, contains('.AlarmReceiver'));
      expect(manifest, contains('.AlarmActionReceiver'));
    },
  );

  test('location hardware remains optional for manual-city devices', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    for (final feature in <String>[
      'android.hardware.location',
      'android.hardware.location.gps',
      'android.hardware.location.network',
      'android.hardware.sensor.compass',
      'android.hardware.sensor.accelerometer',
    ]) {
      final declaration = RegExp(
        '<uses-feature\\s+android:name="$feature"\\s+'
        'android:required="false"\\s*/>',
      );
      expect(
        manifest,
        matches(declaration),
        reason: '$feature must not exclude devices without location hardware',
      );
    }
  });

  test('Android prayer widget provider is registered', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final provider = File(
      'android/app/src/main/res/xml/dauam_prayer_widget_info.xml',
    ).readAsStringSync();

    expect(manifest, contains('.DauamPrayerWidgetProvider'));
    expect(manifest, contains('android.appwidget.action.APPWIDGET_UPDATE'));
    expect(manifest, contains('@xml/dauam_prayer_widget_info'));
    expect(provider, contains('android:resizeMode="horizontal|vertical"'));
    expect(provider, contains('@layout/widget_prayer_small'));
    expect(provider, contains('@layout/widget_prayer_wide'));
  });

  test('Android daily tasks widget provider is registered', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final provider = File(
      'android/app/src/main/res/xml/dauam_tasks_widget_info.xml',
    ).readAsStringSync();

    expect(manifest, contains('.DauamTasksWidgetProvider'));
    expect(manifest, contains('@xml/dauam_tasks_widget_info'));
    expect(provider, contains('android:resizeMode="horizontal|vertical"'));
    expect(provider, contains('@layout/widget_tasks_small'));
    expect(provider, contains('@layout/widget_tasks_wide'));
  });
}
