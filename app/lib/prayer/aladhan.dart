import 'dart:convert';
import 'package:http/http.dart' as http;

/// Времена намаза за пределами Казахстана — открытый API Aladhan
/// (api.aladhan.com), без ключа. Метод расчёта API выбирает сам по месту —
/// ведомство этой страны (например, Диянет в Турции, Умм аль-Кура в Саудовской
/// Аравии); Аср — ханафитский, как у ДУМК.
///
/// Только для мест вне справочника ДУМК: в Казахстане источник — ДУМК.
class AladhanApi {
  static const _base = 'https://api.aladhan.com/v1';

  /// Год времён: 'YYYY-MM-DD' → [fajr, sunrise, dhuhr, asr, maghrib, isha]
  /// в минутах от полуночи по местному времени этого места.
  static Future<Map<String, List<int>>> fetchYear(
    double lat,
    double lng,
    int year,
  ) async {
    final url = Uri.parse(
      '$_base/calendar/$year?latitude=$lat&longitude=$lng&school=1',
    );
    final resp = await http.get(url).timeout(const Duration(seconds: 25));
    if (resp.statusCode != 200) {
      throw Exception('aladhan.com HTTP ${resp.statusCode}');
    }
    final data =
        (jsonDecode(resp.body) as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    final result = <String, List<int>>{};
    for (final month in data.values) {
      for (final day in month as List) {
        final d = day as Map<String, dynamic>;
        final t = d['timings'] as Map<String, dynamic>;
        final g =
            (d['date'] as Map<String, dynamic>)['gregorian']['date']
                as String; // DD-MM-YYYY
        final parts = g.split('-');
        result['${parts[2]}-${parts[1]}-${parts[0]}'] = [
          _mins(t['Fajr'] as String),
          _mins(t['Sunrise'] as String),
          _mins(t['Dhuhr'] as String),
          _mins(t['Asr'] as String),
          _mins(t['Maghrib'] as String),
          _mins(t['Isha'] as String),
        ];
      }
    }
    if (result.isEmpty) throw Exception('aladhan.com: пустой ответ');
    return result;
  }

  /// '06:50 (+03)' → минуты от полуночи.
  static int _mins(String value) {
    final hhmm = value.split(' ').first.split(':');
    return int.parse(hhmm[0]) * 60 + int.parse(hhmm[1]);
  }
}

/// Название места по координатам — OpenStreetMap Nominatim. Нужно только,
/// чтобы за границей показать «Стамбул» вместо цифр координат.
class PlaceNameApi {
  static Future<({String city, String country})?> lookup(
    double lat,
    double lng,
    String lang,
  ) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lng&format=jsonv2&zoom=10'
        '&accept-language=${lang == 'kz' ? 'kk,ru' : 'ru'}',
      );
      final resp = await http
          .get(url, headers: {'User-Agent': 'Dauam/1.0 (muahhidun@gmail.com)'})
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final a = (j['address'] as Map<String, dynamic>?) ?? const {};
      final city =
          (a['city'] ??
                  a['town'] ??
                  a['village'] ??
                  a['municipality'] ??
                  a['county'] ??
                  a['state'] ??
                  j['name'])
              as String?;
      if (city == null || city.isEmpty) return null;
      return (city: city, country: (a['country'] as String?) ?? '');
    } catch (_) {
      return null;
    }
  }
}
