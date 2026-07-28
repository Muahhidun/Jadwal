import 'package:flutter/services.dart';

/// Сервис управления нативными Live Activities и Dynamic Island на iOS.
class LiveActivityService {
  static const MethodChannel _channel = MethodChannel('kz.dauam/live_activity');

  static void Function()? onNextZikr;
  static void Function()? onPrevZikr;
  static void Function()? onTickZikr;

  static void init({
    void Function()? nextZikrHandler,
    void Function()? prevZikrHandler,
    void Function()? tickZikrHandler,
  }) {
    onNextZikr = nextZikrHandler;
    onPrevZikr = prevZikrHandler;
    onTickZikr = tickZikrHandler;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onZikrNext':
          onNextZikr?.call();
          break;
        case 'onZikrPrev':
          onPrevZikr?.call();
          break;
        case 'onZikrTick':
          onTickZikr?.call();
          break;
      }
    });
  }

  static Future<bool> isSupported() async {
    try {
      final res = await _channel.invokeMethod<bool>('isSupported');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Сценарий A: Появление Dynamic Island за 15 минут до приближающегося намаза
  static Future<void> startPrayerProximity({
    required String prayerName,
    required String cityName,
    required DateTime targetTime,
  }) async {
    try {
      await _channel.invokeMethod('startActivity', {
        'mode': 'prayer',
        'title': 'До намаза $prayerName',
        'subtitle': cityName,
        'targetTimestamp': targetTime.millisecondsSinceEpoch / 1000.0,
      });
    } catch (_) {}
  }

  /// Удаляет только автоматический отсчёт до намаза, не прерывая открытую
  /// пользователем сессию чтения зикров.
  static Future<void> stopPrayerProximity() async {
    try {
      await _channel.invokeMethod('stopPrayerActivity');
    } catch (_) {}
  }

  /// Сценарий B: Включение интерактивного ридера зикров в Dynamic Island
  static Future<String> startZikrSession({
    required String title,
    required int counterCurrent,
    required int counterTotal,
    required String zikrArabic,
    required String zikrTranslation,
  }) async {
    try {
      final res = await _channel.invokeMethod('startActivity', {
        'mode': 'zikr',
        'title': title,
        'subtitle': 'Зикр $counterCurrent из $counterTotal',
        'counterCurrent': counterCurrent,
        'counterTotal': counterTotal,
        'zikrArabic': zikrArabic,
        'zikrTranslation': zikrTranslation,
      });
      return 'OK: $res';
    } catch (e) {
      return 'ERR: $e';
    }
  }

  /// Обновление текущего зикра в Dynamic Island при щелчке/переключении
  static Future<void> updateZikrSession({
    required String title,
    required int counterCurrent,
    required int counterTotal,
    required String zikrArabic,
    required String zikrTranslation,
  }) async {
    try {
      await _channel.invokeMethod('updateActivity', {
        'mode': 'zikr',
        'title': title,
        'subtitle': 'Зикр $counterCurrent из $counterTotal',
        'counterCurrent': counterCurrent,
        'counterTotal': counterTotal,
        'zikrArabic': zikrArabic,
        'zikrTranslation': zikrTranslation,
      });
    } catch (_) {}
  }

  /// Завершение сессии Live Activity и очистка острова
  static Future<void> stopActivity() async {
    try {
      await _channel.invokeMethod('stopActivity');
    } catch (_) {}
  }
}
