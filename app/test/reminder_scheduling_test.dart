import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/notifications/notifications.dart';
import 'package:jadwal/prayer/schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('восход не называется намазом в уведомлении', () {
    final copy = prayerNotificationCopy('ru', Prayer.sunrise);

    expect(copy.title, 'Восход солнца');
    expect(copy.body, 'Наступил восход солнца.');
    expect(copy.body, isNot(contains('намаз')));
  });

  test('старое напоминание остаётся привязанным к намазу', () {
    final reminder = ReminderConfig.fromJson({
      'id': 'legacy',
      't': 'Старое',
      'p': Prayer.maghrib.index,
      'o': -15,
      'e': true,
    });

    expect(reminder.isPrayerLinked, isTrue);
    expect(reminder.fixedHour, 9);
    expect(reminder.fixedMinute, 0);
  });

  test('обычное напоминание сохраняет фиксированное время', () {
    const reminder = ReminderConfig(
      id: 'clock',
      title: 'Личное дело',
      prayer: 0,
      offsetMin: 0,
      anchor: 'clock',
      fixedHour: 21,
      fixedMinute: 35,
    );

    final restored = ReminderConfig.fromJson(reminder.toJson());
    expect(restored.isPrayerLinked, isFalse);
    expect(restored.fixedHour, 21);
    expect(restored.fixedMinute, 35);
    expect(
      reminderScheduledTime(restored, DateTime(2026, 8, 27), null),
      DateTime(2026, 8, 27, 21, 35),
    );
  });

  test('привязка к намазу учитывает смещение', () {
    const reminder = ReminderConfig(
      id: 'dua',
      title: 'Дуа',
      prayer: 4,
      offsetMin: -20,
    );
    final date = DateTime(2026, 8, 27);
    final times = DayTimes(
      date: date,
      times: const {Prayer.maghrib: 19 * 60 + 10},
    );

    expect(
      reminderScheduledTime(reminder, date, times),
      DateTime(2026, 8, 27, 18, 50),
    );
  });

  test(
    'новые уведомления зикров по умолчанию приходят через 10 минут',
    () async {
      SharedPreferences.setMockInitialValues({});
      final app = await AppState.load();

      expect(app.getReminderConfig('morning', 'ru').offsetMin, 10);
      expect(app.getReminderConfig('evening', 'ru').offsetMin, 10);
    },
  );

  test('старый нулевой дефолт один раз переносится на +10 минут', () async {
    const old = ReminderConfig(
      id: 'morning',
      title: 'Утренние зикры',
      prayer: 0,
      offsetMin: 0,
    );
    SharedPreferences.setMockInitialValues({
      'rc:morning': jsonEncode(old.toJson()),
    });
    final app = await AppState.load();

    expect(app.getReminderConfig('morning', 'ru').offsetMin, 10);
  });

  test('уведомление аль-Кахф открывает встроенную читалку', () {
    expect(notificationTargetFor('kahf'), 'kahf');
    expect(notificationTargetFor('morning'), 'morning');
    expect(notificationTargetFor('dua'), isEmpty);
  });
}
