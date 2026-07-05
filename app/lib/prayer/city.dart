import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;

/// Населённый пункт из справочника ДУМК (api.muftyat.kz/cities).
/// Полный список (5695 пунктов) лежит в assets/data/cities.json,
/// генерируется скриптом tools/fetch_cities.py.
class City {
  final String name;
  final double lat, lng;
  final String region;

  const City(this.name, this.lat, this.lng, {this.region = ''});

  factory City.fromJson(Map<String, dynamic> j) => City(
        j['t'] as String,
        (j['lat'] as num).toDouble(),
        (j['lng'] as num).toDouble(),
        region: (j['r'] as String?) ?? '',
      );
}

/// Город по умолчанию до выбора/определения — Алматы.
const kDefaultCity = City('Алматы', 43.238949, 76.889709, region: 'Алматы');

/// Крупные города — для быстрого выбора в онбординге до ввода поиска.
const kMajorCities = [
  City('Алматы', 43.238949, 76.889709, region: 'Алматы'),
  City('Астана', 51.169392, 71.449074, region: 'Астана'),
  City('Шымкент', 42.341686, 69.590101, region: 'Шымкент'),
  City('Караганда', 49.804684, 73.087749, region: 'Қарағанды облысы'),
  City('Актобе', 50.283937, 57.166978, region: 'Ақтөбе облысы'),
  City('Тараз', 42.899444, 71.392778, region: 'Жамбыл облысы'),
  City('Павлодар', 52.287363, 76.967283, region: 'Павлодар облысы'),
  City('Өскемен', 49.948759, 82.627935, region: 'Шығыс Қазақстан облысы'),
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

  /// Поиск по названию (регистронезависимо, латиница/кириллица как есть).
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
