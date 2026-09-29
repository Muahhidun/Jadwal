import 'package:geolocator/geolocator.dart';
import 'city.dart';

/// Авто-определение города по GPS: спрашивает разрешение, берёт координаты,
/// находит ближайший населённый пункт из справочника ДУМК.
class Geo {
  /// Возвращает ближайший город или null (нет разрешения / выключена геолокация).
  static Future<City?> detectCity() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      // Indoors and on budget Android devices a fresh GPS fix can take too
      // long. A cached fix is still better than failing the city step.
      pos = await Geolocator.getLastKnownPosition();
    }
    if (pos == null) return null;
    return CityRepository.nearest(pos.latitude, pos.longitude);
  }
}
