import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

({String collectionId, int index})? zikrTargetFromDeepLink(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'dauam' || uri.host != 'zikr') return null;
  final collection = uri.queryParameters['collection'];
  if (collection != 'morning' && collection != 'evening') return null;
  final parsedIndex = int.tryParse(uri.queryParameters['index'] ?? '') ?? 0;
  return (collectionId: collection!, index: parsedIndex < 0 ? 0 : parsedIndex);
}

/// Сервис управления нативными Live Activities и Dynamic Island на iOS.
class LiveActivityService {
  static const MethodChannel _channel = MethodChannel('kz.dauam/live_activity');

  static void Function()? onNextZikr;
  static void Function()? onPrevZikr;
  static void Function()? onTickZikr;
  static void Function(String collectionId, int index)? onOpenZikr;
  static String? activeCollection;
  static String? _lastDeliveredDeepLink;

  /// Live Activity / Dynamic Island exists only on iOS. Keeping this check in
  /// the service prevents every Android call site from reaching a channel
  /// that intentionally has no native implementation.
  static bool get _isAvailablePlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static void init({
    void Function()? nextZikrHandler,
    void Function()? prevZikrHandler,
    void Function()? tickZikrHandler,
    void Function(String collectionId, int index)? openZikrHandler,
  }) {
    onNextZikr = nextZikrHandler;
    onPrevZikr = prevZikrHandler;
    onTickZikr = tickZikrHandler;
    if (openZikrHandler != null) onOpenZikr = openZikrHandler;

    if (!_isAvailablePlatform) return;

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
        case 'onOpenDeepLink':
          _deliverDeepLink(call.arguments as String?);
          break;
      }
    });
  }

  static void _deliverDeepLink(String? raw) {
    if (raw == null || raw.isEmpty || raw == _lastDeliveredDeepLink) return;
    final target = zikrTargetFromDeepLink(raw);
    if (target == null) return;
    _lastDeliveredDeepLink = raw;
    if (activeCollection != target.collectionId) {
      onOpenZikr?.call(target.collectionId, target.index);
    }
  }

  /// Забирает ссылку, с которой приложение было запущено после полного
  /// закрытия. При обычном возврате из фона ссылка приходит через канал.
  static Future<void> claimPendingDeepLink() async {
    if (!_isAvailablePlatform) return;
    try {
      final raw = await _channel.invokeMethod<String>('getPendingDeepLink');
      _deliverDeepLink(raw);
    } catch (_) {}
  }

  static Future<bool> isSupported() async {
    if (!_isAvailablePlatform) return false;
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
    if (!_isAvailablePlatform) return;
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
    if (!_isAvailablePlatform) return;
    try {
      await _channel.invokeMethod('stopPrayerActivity');
    } catch (_) {}
  }

  /// Сценарий B: Включение интерактивного ридера зикров в Dynamic Island
  static Future<String> startZikrSession({
    required String collectionId,
    required int currentIndex,
    required String title,
    required int counterCurrent,
    required int counterTotal,
    required String zikrArabic,
    required String zikrTranslation,
  }) async {
    if (!_isAvailablePlatform) return 'UNSUPPORTED';
    try {
      final res = await _channel.invokeMethod('startActivity', {
        'mode': 'zikr',
        'collectionId': collectionId,
        'currentIndex': currentIndex,
        'title': title,
        'subtitle': 'Зикр $counterCurrent из $counterTotal',
        'counterCurrent': counterCurrent,
        'counterTotal': counterTotal,
        'zikrArabic': zikrArabic,
        'zikrTranslation': zikrTranslation,
      });
      return 'OK: $res';
    } catch (error) {
      debugPrint('Live Activity could not start: $error');
      return 'UNAVAILABLE';
    }
  }

  /// Обновление текущего зикра в Dynamic Island при щелчке/переключении
  static Future<void> updateZikrSession({
    required String collectionId,
    required int currentIndex,
    required String title,
    required int counterCurrent,
    required int counterTotal,
    required String zikrArabic,
    required String zikrTranslation,
  }) async {
    if (!_isAvailablePlatform) return;
    try {
      await _channel.invokeMethod('updateActivity', {
        'mode': 'zikr',
        'collectionId': collectionId,
        'currentIndex': currentIndex,
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
    if (!_isAvailablePlatform) return;
    try {
      await _channel.invokeMethod('stopActivity');
    } catch (_) {}
  }
}
