import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/notifications/notifications.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule.dart';
import 'package:jadwal/prayer/schedule_service.dart';
import 'package:jadwal/services/alarm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('еженедельное напоминание работает в несколько выбранных дней', () {
    const reminder = ReminderConfig(
      id: 'weekdays',
      title: 'Понедельник, среда, пятница',
      prayer: 0,
      offsetMin: 0,
      repeat: 'weekly',
      weekdays: [DateTime.monday, DateTime.wednesday, DateTime.friday],
    );

    expect(reminder.occursOn(DateTime(2026, 9, 7)), isTrue);
    expect(reminder.occursOn(DateTime(2026, 9, 8)), isFalse);
    expect(reminder.occursOn(DateTime(2026, 9, 9)), isTrue);
    expect(reminder.occursOn(DateTime(2026, 9, 11)), isTrue);
  });

  test('одноразовая дата и ежегодный повтор не теряются после JSON', () {
    const reminder = ReminderConfig(
      id: 'yearly',
      title: 'Ежегодное дело',
      prayer: 0,
      offsetMin: 0,
      repeat: 'yearly',
      weekday: DateTime.monday,
      weekdays: [DateTime.monday, DateTime.wednesday],
      scheduleYear: 2026,
      scheduleMonth: 9,
      scheduleDay: 5,
    );

    final restored = ReminderConfig.fromJson(reminder.toJson());
    expect(restored.repeat, 'yearly');
    expect(restored.weekdays, [DateTime.monday, DateTime.wednesday]);
    expect(restored.scheduleYear, 2026);
    expect(restored.occursOn(DateTime(2030, 9, 5)), isTrue);
    expect(restored.occursOn(DateTime(2030, 9, 6)), isFalse);
  });

  test('напоминание без повтора срабатывает только в свою дату', () {
    const reminder = ReminderConfig(
      id: 'once',
      title: 'Один раз',
      prayer: 0,
      offsetMin: 0,
      repeat: 'once',
      scheduleYear: 2026,
      scheduleMonth: 9,
      scheduleDay: 5,
    );

    expect(reminder.occursOn(DateTime(2026, 9, 5)), isTrue);
    expect(reminder.occursOn(DateTime(2027, 9, 5)), isFalse);
  });

  test(
    'режим крепкого сна хранится локально и использует три повтора',
    () async {
      SharedPreferences.setMockInitialValues({});
      final app = await AppState.load();

      expect(app.heavySleeperEnabled, isFalse);
      expect(app.heavySleeperGuideSeen, isFalse);
      expect(AlarmService.heavySleeperBackupMinutes, [3, 6, 9]);

      app.setHeavySleeperEnabled(true);
      app.markHeavySleeperGuideSeen();
      final restored = await AppState.load();

      expect(restored.heavySleeperEnabled, isTrue);
      expect(restored.heavySleeperGuideSeen, isTrue);
    },
  );

  test('Android получает точное расписание Фаджра на 14 дней', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final app = await AppState.load();
    app.setCity(kDefaultCity);
    app.setAlarmEnabled('fajr', true);
    app.setHeavySleeperEnabled(true);
    final schedule = ScheduleService(
      prefs,
      now: () => DateTime(2026, 9, 12, 0, 1),
    );
    const channel = MethodChannel('kz.dauam/alarm');
    Map<Object?, Object?>? payload;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'syncPrayerAlarms');
          payload = call.arguments as Map<Object?, Object?>;
          return <String, Object?>{'success': true, 'mode': 'alarmManager'};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(await AlarmService.sync(app, schedule), isTrue);
    final alarms = (payload!['alarms'] as List).cast<Map<Object?, Object?>>();
    expect(alarms, hasLength(AlarmService.androidLookaheadDays));
    expect(alarms.every((alarm) => alarm['id'] == 'fajr'), isTrue);
    expect(alarms.map((alarm) => alarm['family']).toSet(), hasLength(14));
    expect(alarms.every((alarm) => alarm['heavySleeper'] == true), isTrue);
    expect(
      alarms.every(
        (alarm) =>
            (alarm['backupMinutes'] as List).join(',') == '3,6,9' &&
            alarm['language'] == 'ru' &&
            alarm['requestCode'] is int,
      ),
      isTrue,
    );
  });
}
