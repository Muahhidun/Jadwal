import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// Ориентация экрана. Всё приложение на телефоне — только вертикально;
/// читалки зикров и суры аль-Кахф разрешают ещё и горизонтальную.
/// Планшеты и сложенные/раскрытые устройства не ограничиваются.
class AppOrientation {
  AppOrientation._();

  /// Телефон — меньшая сторона логического экрана < 600.
  static bool get isPhone {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) return true;
    final view = views.first;
    final dpr = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
    return view.physicalSize.shortestSide / dpr < 600;
  }

  /// Основной режим приложения.
  static Future<void> lockPortrait() {
    _forceSerial++; // отменяет отложенное «разрешить всё» после поворота
    return SystemChrome.setPreferredOrientations(
      isPhone ? const [DeviceOrientation.portraitUp] : DeviceOrientation.values,
    );
  }

  /// Читалка: поворот телефона сам переводит текст в горизонталь.
  static Future<void> allowReading() => SystemChrome.setPreferredOrientations(
    isPhone
        ? const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : DeviceOrientation.values,
  );

  static int _forceSerial = 0;

  /// Кнопка в углу читалки. Горизонталь держится, пока читалка открыта или
  /// пока её не вернут в вертикаль: так кнопка работает и при заблокированном
  /// автоповороте iPhone. Возврат в вертикаль снова разрешает автоповорот.
  static Future<void> force({required bool landscape}) async {
    final serial = ++_forceSerial;
    if (landscape) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      return;
    }
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (serial == _forceSerial) await allowReading();
  }
}
