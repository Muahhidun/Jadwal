import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../prayer/city.dart';

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
    return showModalBottomSheet<City>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF161C26),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 20, spreadRadius: 5),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFC88D51).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  color: Color(0xFFC88D51),
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Вы сменили локацию?',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Manrope',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Обнаружен новый город: ${detectedCity.name}.\nОбновить расписание молитв и виджеты для нового места?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(ctx).pop();
                      },
                      child: Text(
                        'Оставить ${currentCity.name}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontFamily: 'Manrope',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC88D51),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.of(ctx).pop(detectedCity);
                      },
                      child: Text(
                        'Да, ${detectedCity.name}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Manrope',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
