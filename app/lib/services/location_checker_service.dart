import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../data/app_state.dart';
import '../prayer/aladhan.dart';
import '../prayer/city.dart';
import '../screens/location_change_prompt.dart';
import '../screens/settings_shell.dart';

/// Сервис авто-определения смены города и вежливого предложения обновить расписание
class LocationCheckerService {
  static bool _hasPromptedThisSession = false;
  static bool _checkInFlight = false;

  /// Дальше этого от любого пункта справочника ДУМК — человек за пределами
  /// Казахстана (у границы, например в Ташкенте или Бишкеке, ближайшее село
  /// справочника рядом, и его времена практически те же).
  static const _abroadKm = 120.0;

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

      final (nearest, km) = await CityRepository.nearestWithDistance(
        pos.latitude,
        pos.longitude,
      );

      City detectedCity = nearest;
      if (km > _abroadKm) {
        // За границей: справочник ДУМК не подходит, нужен местный расчёт.
        // Уже стоим на этом месте — ничего не предлагаем.
        if (currentCity.isLocalCalc &&
            CityRepository.distanceKm(
                  pos.latitude,
                  pos.longitude,
                  currentCity.lat,
                  currentCity.lng,
                ) <
                50) {
          return;
        }
        if (!context.mounted) return;
        final lang = AppScope.of(context).lang;
        final place = await PlaceNameApi.lookup(
          pos.latitude,
          pos.longitude,
          lang,
        );
        // Координаты места за границей округляем до ~1 км: для времён намаза
        // точнее не нужно, а отправлять точную позицию незачем. (Координаты
        // ДУМК внутри Казахстана НЕ округляются никогда — это другой путь.)
        detectedCity = City(
          place?.city ?? (lang == 'kz' ? 'Қазіргі орын' : 'Текущее место'),
          pos.latitude.toStringAsFixed(2),
          pos.longitude.toStringAsFixed(2),
          region: place?.country ?? '',
          source: City.sourceLocal,
        );
      }

      if (!context.mounted) return;
      final changed =
          detectedCity.name != currentCity.name ||
          detectedCity.source != currentCity.source;
      if (changed && canPresentPrompt(context)) {
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
          abroad: detectedCity.isLocalCalc,
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
