import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;

/// Населённый пункт из справочника ДУМК (api.muftyat.kz/cities).
///
/// ВАЖНО: координаты хранятся ТОЧНОЙ строкой как отдаёт ДУМК и передаются
/// в endpoint prayer-times дословно — он ищет город по точному совпадению
/// координат (округление → 404 → запасной расчёт, времена не совпадут с мечетью).
class City {
  final String name;
  final String latStr, lngStr;
  final String region;

  const City(this.name, this.latStr, this.lngStr, {this.region = ''});

  double get lat => double.parse(latStr);
  double get lng => double.parse(lngStr);

  factory City.fromJson(Map<String, dynamic> j) => City(
        j['t'] as String,
        j['lat'] as String,
        j['lng'] as String,
        region: (j['r'] as String?) ?? '',
      );
}

/// Город по умолчанию — Алматы (точные координаты ДУМК).
const kDefaultCity =
    City('Алматы', '43.238293', '76.945465', region: 'Алматы');

/// Крупные города для быстрого выбора в онбординге. Координаты — точные ДУМК.
const kMajorCities = [
  City('Алматы', '43.238293', '76.945465', region: 'Алматы'),
  City('Астана', '51.133333', '71.433333', region: 'Астана'),
  City('Шымкент', '42.368009', '69.612769', region: 'Шымкент'),
  City('Қарағанды', '49.806406', '73.085485', region: 'Қарағанды облысы'),
  City('Ақтөбе', '50.300377', '57.154555', region: 'Ақтөбе облысы'),
  City('Тараз', '42.883333', '71.366667', region: 'Жамбыл облысы'),
  City('Павлодар', '52.315556', '76.956389', region: 'Павлодар облысы'),
  City('Өскемен', '49.948325', '82.627848', region: 'Шығыс Қазақстан облысы'),
];

class CityRepository {
  static List<City>? _all;

  static Future<List<City>> load() async {
    if (_all != null) return _all!;
    final raw = await rootBundle.loadString('assets/data/cities.json');
    final list = jsonDecode(raw) as List;
    _all = list.map((e) => City.fromJson(e as Map<String, dynamic>)).toList();
    return _all!;
  }

  /// Ближайший к координатам пункт (гаверсинус). Для авто-определения по GPS.
  static Future<City> nearest(double lat, double lng) async {
    final all = await load();
    City best = all.first;
    double bestD = double.infinity;
    for (final c in all) {
      final d = _haversine(lat, lng, c.lat, c.lng);
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return best;
  }

  /// Поиск по названию (регистронезависимо).
  static Future<List<City>> search(String query, {int limit = 40}) async {
    final all = await load();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final starts = <City>[];
    final contains = <City>[];
    for (final c in all) {
      final name = c.name.toLowerCase();
      if (name.startsWith(q)) {
        starts.add(c);
      } else if (name.contains(q)) {
        contains.add(c);
      }
      if (starts.length >= limit) break;
    }
    return [...starts, ...contains].take(limit).toList();
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;
}
