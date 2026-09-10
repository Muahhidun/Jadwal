import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../data/app_state.dart';
import '../prayer/city.dart';
import '../screens/location_change_prompt.dart';
import '../screens/settings_shell.dart';

/// Сервис авто-определения смены города и вежливого предложения обновить расписание
class LocationCheckerService {
  static bool _hasPromptedThisSession = false;
  static bool _checkInFlight = false;

  /// Фоновая проверка GPS может завершиться уже после того, как
  /// пользователь открыл настройки или читалку. Новый modal route в этот
  /// момент оставлял над приложением недоступный затемняющий слой.
  /// Поэтому автоподсказку разрешено показывать только с текущего route.
  @visibleForTesting
  static bool canPresentPrompt(BuildContext context) {
    if (!context.mounted) return false;
    final route = ModalRoute.of(context);
    return route != null && route.isCurrent;
  }

  /// Проверяет текущее GPS-положение. Если ближайший город отличается от currentCity,
  /// показывает эстетичный диалог с предложением сменить город.
  static Future<void> checkLocationChange({
    required BuildContext context,
    required City currentCity,
    required Function(City newCity) onCitySelected,
  }) async {
    if (_hasPromptedThisSession || _checkInFlight) return;
    _checkInFlight = true;

    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );

      final detectedCity = await CityRepository.nearest(
        pos.latitude,
        pos.longitude,
      );

      if (!context.mounted) return;
      if (detectedCity.name != currentCity.name && canPresentPrompt(context)) {
        _hasPromptedThisSession = true;
        final selectedCity = await _showLocationPrompt(
          context: context,
          currentCity: currentCity,
          detectedCity: detectedCity,
        );
        if (selectedCity != null && context.mounted) {
          onCitySelected(selectedCity);
        }
      }
    } catch (_) {
      // Игнорируем фоновые ошибки геолокации
    } finally {
      _checkInFlight = false;
    }
  }

  static Future<City?> _showLocationPrompt({
    required BuildContext context,
    required City currentCity,
    required City detectedCity,
  }) {
    final lang = AppScope.of(context).lang;
    final palette = dauamSettingsPalette(context);
    final accent = dauamSettingsAccent(context);

    return showModalBottomSheet<City>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      barrierColor: Colors.black.withValues(alpha: .34),
      builder: (ctx) {
        return LocationChangePrompt(
          currentCity: currentCity,
          detectedCity: detectedCity,
          lang: lang,
          palette: palette,
          accent: accent,
          onKeepCurrent: () {
            HapticFeedback.selectionClick();
            Navigator.of(ctx).pop();
          },
          onUpdate: () {
            HapticFeedback.mediumImpact();
            Navigator.of(ctx).pop(detectedCity);
          },
        );
      },
    );
  }
}
