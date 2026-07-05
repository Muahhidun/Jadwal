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
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
    );
    return CityRepository.nearest(pos.latitude, pos.longitude);
  }
}
