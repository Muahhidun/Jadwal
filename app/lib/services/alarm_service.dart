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

/// Сервис управления нативным системным будильником Фаджра.
class AlarmService {
  static const MethodChannel _channel = MethodChannel('kz.dauam/alarm');

  /// Пересчитывает и регистрирует настоящий системный будильник AlarmKit.
  static Future<bool> sync(AppState app, ScheduleService schedule) async {
    final now = DateTime.now();
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

    final fajrToday = timestampFor(today, Prayer.fajr);
    final fajrTomorrow = timestampFor(tomorrow, Prayer.fajr);
    final offset = app.fajrAlarmOffsetMinutes;

    DateTime target = fajrToday.add(Duration(minutes: offset));
    if (target.isBefore(now)) {
      target = fajrTomorrow.add(Duration(minutes: offset));
    }

    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'scheduleFajrAlarm',
        {
        'enabled': app.fajrAlarmEnabled,
        'timestamp': target.millisecondsSinceEpoch / 1000.0,
        'offsetMinutes': offset,
        'title': app.lang == 'kz' ? 'Таң намазы' : 'Фаджр',
        },
      );
      return response?['success'] == true &&
          response?['mode'] == 'alarmKit';
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
        {
          'seconds': seconds.toDouble(),
          'title': title,
        },
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
