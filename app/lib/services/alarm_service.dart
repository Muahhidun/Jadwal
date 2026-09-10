import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../prayer/schedule.dart';
import '../prayer/schedule_service.dart';

class AlarmOperationResult {
  const AlarmOperationResult({
    required this.success,
    this.mode,
    this.errorCode,
    this.message,
  });

  final bool success;
  final String? mode;
  final String? errorCode;
  final String? message;
}

/// Сервис управления нативными системными будильниками временных точек дня.
class AlarmService {
  static const MethodChannel _channel = MethodChannel('kz.dauam/alarm');

  static const _prayers = <(String, Prayer)>[
    ('fajr', Prayer.fajr),
    ('sunrise', Prayer.sunrise),
    ('dhuhr', Prayer.dhuhr),
    ('asr', Prayer.asr),
    ('maghrib', Prayer.maghrib),
    ('isha', Prayer.isha),
  ];

  /// Пересчитывает и регистрирует настоящий системный будильник AlarmKit.
  static Future<bool> sync(AppState app, ScheduleService schedule) async {
    final now = schedule.now();
    final today = schedule.timesFor(app.city, now);
    final tomorrowDate = DateTime(now.year, now.month, now.day + 1);
    final tomorrow = schedule.timesFor(app.city, tomorrowDate);

    if (today == null || tomorrow == null) return false;

    DateTime timestampFor(DayTimes day, Prayer prayer) {
      final minutes = day.times[prayer]!;
      return DateTime(
        day.date.year,
        day.date.month,
        day.date.day,
        minutes ~/ 60,
        minutes % 60,
      );
    }

    final kz = app.lang == 'kz';
    const titlesRu = <String, String>{
      'fajr': 'Фаджр',
      'sunrise': 'Восход',
      'dhuhr': 'Зухр',
      'asr': 'Аср',
      'maghrib': 'Магриб',
      'isha': 'Иша',
    };
    const titlesKz = <String, String>{
      'fajr': 'Таң намазы',
      'sunrise': 'Күн шығуы',
      'dhuhr': 'Бесін намазы',
      'asr': 'Екінті намазы',
      'maghrib': 'Ақшам намазы',
      'isha': 'Құптан намазы',
    };

    final alarms = <Map<String, dynamic>>[];
    for (final item in _prayers) {
      final (id, prayer) = item;
      final offset = app.alarmOffsetMinutes(id);
      var target = timestampFor(today, prayer).add(Duration(minutes: offset));
      if (!target.isAfter(now)) {
        target = timestampFor(tomorrow, prayer).add(Duration(minutes: offset));
      }
      alarms.add({
        'id': id,
        'enabled': app.alarmEnabled(id),
        'timestamp': target.millisecondsSinceEpoch / 1000.0,
        'offsetMinutes': offset,
        'title': (kz ? titlesKz : titlesRu)[id]!,
      });
    }

    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'syncPrayerAlarms',
        {'alarms': alarms},
      );
      return response?['success'] == true && response?['mode'] == 'alarmKit';
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Запустить тестовый будильник через [seconds] секунд для проверки.
  static Future<AlarmOperationResult> testAlarm({
    int seconds = 10,
    String title = 'Фаджр (Тест)',
  }) async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'testFajrAlarm',
        {'seconds': seconds.toDouble(), 'title': title},
      );
      final mode = response?['mode'] as String?;
      final success = response?['success'] == true && mode == 'alarmKit';
      return AlarmOperationResult(success: success, mode: mode);
    } on MissingPluginException catch (error) {
      return AlarmOperationResult(
        success: false,
        errorCode: 'MISSING_PLUGIN',
        message: error.message,
      );
    } on PlatformException catch (error) {
      return AlarmOperationResult(
        success: false,
        errorCode: error.code,
        message: error.message,
      );
    } catch (error) {
      return AlarmOperationResult(
        success: false,
        errorCode: 'UNKNOWN',
        message: error.toString(),
      );
    }
  }

  /// Получить информацию о запланированных срабатываниях будильника.
  static Future<List<Map<String, dynamic>>> getPendingAlarms() async {
    try {
      final res = await _channel.invokeMethod('getPendingAlarms');
      if (res is List) {
        return res
            .cast<Map<Object?, Object?>>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}
