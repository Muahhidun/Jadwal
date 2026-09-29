import 'package:flutter/foundation.dart';
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

class AlarmCapabilities {
  const AlarmCapabilities({
    required this.canScheduleExact,
    required this.canUseFullScreen,
    required this.notificationsGranted,
    required this.ready,
  });

  final bool canScheduleExact;
  final bool canUseFullScreen;
  final bool notificationsGranted;
  final bool ready;

  factory AlarmCapabilities.fromMap(Map<Object?, Object?> map) =>
      AlarmCapabilities(
        canScheduleExact: map['canScheduleExact'] == true,
        canUseFullScreen: map['canUseFullScreen'] == true,
        notificationsGranted: map['notificationsGranted'] == true,
        ready: map['ready'] == true,
      );
}

/// Сервис управления нативными системными будильниками временных точек дня.
class AlarmService {
  static const MethodChannel _channel = MethodChannel('kz.dauam/alarm');
  static const androidLookaheadDays = 14;

  /// Резервные сигналы режима «Крепкий сон» после основного Фаджра.
  static const heavySleeperBackupMinutes = <int>[3, 6, 9];

  static const _prayers = <(String, Prayer)>[
    ('fajr', Prayer.fajr),
    ('sunrise', Prayer.sunrise),
    ('dhuhr', Prayer.dhuhr),
    ('asr', Prayer.asr),
    ('maghrib', Prayer.maghrib),
    ('isha', Prayer.isha),
  ];

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isSupportedPlatform => isAndroid || isIOS;

  /// Пересчитывает и регистрирует нативные системные будильники платформы.
  static Future<bool> sync(AppState app, ScheduleService schedule) async {
    if (!isSupportedPlatform) return false;
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
    if (isAndroid) {
      var occurrence = 0;
      for (var dayOffset = 0; dayOffset < androidLookaheadDays; dayOffset++) {
        final date = DateTime(now.year, now.month, now.day + dayOffset);
        final day = schedule.timesFor(app.city, date);
        if (day == null) continue;
        for (final item in _prayers) {
          final (id, prayer) = item;
          final requestCode = 20_000 + occurrence * 10;
          occurrence++;
          if (!app.alarmEnabled(id)) continue;
          final offset = app.alarmOffsetMinutes(id);
          final target = timestampFor(
            day,
            prayer,
          ).add(Duration(minutes: offset));
          if (!target.isAfter(now)) continue;
          alarms.add({
            'id': id,
            'family':
                '$id:${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
            'enabled': true,
            'requestCode': requestCode,
            'timestamp': target.millisecondsSinceEpoch / 1000.0,
            'offsetMinutes': offset,
            'title': (kz ? titlesKz : titlesRu)[id]!,
            'language': app.lang,
            if (id == 'fajr') ...{
              'heavySleeper': app.heavySleeperEnabled,
              'wakeButtonTitle': kz ? 'Ояндым' : 'Я проснулся',
              'backupMinutes': heavySleeperBackupMinutes,
            },
          });
        }
      }
    } else {
      for (final item in _prayers) {
        final (id, prayer) = item;
        final offset = app.alarmOffsetMinutes(id);
        var target = timestampFor(today, prayer).add(Duration(minutes: offset));
        if (!target.isAfter(now)) {
          target = timestampFor(
            tomorrow,
            prayer,
          ).add(Duration(minutes: offset));
        }
        alarms.add({
          'id': id,
          'enabled': app.alarmEnabled(id),
          'timestamp': target.millisecondsSinceEpoch / 1000.0,
          'offsetMinutes': offset,
          'title': (kz ? titlesKz : titlesRu)[id]!,
          if (id == 'fajr') ...{
            'heavySleeper': app.heavySleeperEnabled,
            'wakeButtonTitle': kz ? 'Ояндым' : 'Я проснулся',
            'repeatButtonTitle': kz
                ? '3 минуттан кейін қайталау'
                : 'Повторить через 3 минуты',
            'backupMinutes': heavySleeperBackupMinutes,
          },
        });
      }
    }

    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'syncPrayerAlarms',
        {'alarms': alarms},
      );
      final mode = response?['mode'];
      return response?['success'] == true &&
          (mode == 'alarmKit' || mode == 'alarmManager');
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
    String language = 'ru',
    bool heavySleeper = false,
  }) async {
    try {
      final response = await _channel
          .invokeMapMethod<String, dynamic>('testFajrAlarm', {
            'seconds': seconds.toDouble(),
            'title': title,
            'language': language,
            'heavySleeper': heavySleeper,
            'wakeButtonTitle': language == 'kz' ? 'Ояндым' : 'Я проснулся',
            'repeatButtonTitle': language == 'kz'
                ? '3 минуттан кейін қайталау'
                : 'Повторить через 3 минуты',
            'backupMinutes': heavySleeperBackupMinutes,
          });
      final mode = response?['mode'] as String?;
      final success =
          response?['success'] == true &&
          (mode == 'alarmKit' || mode == 'alarmManager');
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

  static Future<AlarmCapabilities?> getCapabilities() async {
    if (!isAndroid) return null;
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'getAlarmCapabilities',
      );
      return raw == null ? null : AlarmCapabilities.fromMap(raw);
    } catch (_) {
      return null;
    }
  }

  /// Opens Android's next missing alarm access screen, if any.
  static Future<AlarmCapabilities?> requestPermissions() async {
    if (!isAndroid) return null;
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'requestAlarmPermissions',
      );
      return raw == null ? null : AlarmCapabilities.fromMap(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> claimPendingAction() async {
    if (!isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getPendingAlarmAction');
    } catch (_) {
      return null;
    }
  }
}
