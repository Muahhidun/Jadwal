import 'package:flutter/services.dart';
import '../data/adhkar.dart';

/// Сервис управления голосовым чтецом арабских текстов зикров (Siri / Hands-Free).
class ZikrSpeechService {
  static const MethodChannel _channel = MethodChannel('kz.dauam/speech');

  static void Function(int index, int total)? _onZikrStarted;
  static void Function()? _onReadingCompleted;

  static void init({
    void Function(int index, int total)? onZikrStarted,
    void Function()? onReadingCompleted,
  }) {
    _onZikrStarted = onZikrStarted;
    _onReadingCompleted = onReadingCompleted;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onZikrStarted':
          final args = call.arguments as Map?;
          if (args != null && _onZikrStarted != null) {
            _onZikrStarted?.call(args['index'] as int, args['total'] as int);
          }
          break;
        case 'onReadingCompleted':
          _onReadingCompleted?.call();
          break;
      }
    });
  }

  /// Запускает нативное чтение арабских зикров голосом с паузами.
  static Future<bool> speakCollection(
    ZikrCollection collection, {
    double pauseSeconds = 2.5,
  }) async {
    final arabicTexts = collection.items.map((e) => e.ar).toList();
    try {
      final res = await _channel.invokeMethod<bool>('speakZikrs', {
        'items': arabicTexts,
        'title': collection.titleRu,
        'pauseSeconds': pauseSeconds,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> pause() async {
    try {
      await _channel.invokeMethod('pause');
    } catch (_) {}
  }

  static Future<void> resume() async {
    try {
      await _channel.invokeMethod('resume');
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
