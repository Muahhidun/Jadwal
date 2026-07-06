import 'dart:convert';
import 'package:http/http.dart' as http;

/// Клиент API ДУМК (namaz.muftyat.kz). Без ключа и регистрации.
/// Один запрос отдаёт весь год ежедневных времён для координат —
/// кешируем на устройстве и живём офлайн до следующего года.
class MuftyatApi {
  static const _base = 'https://api.muftyat.kz';

  /// Год времён: карта 'YYYY-MM-DD' → [fajr, sunrise, dhuhr, asr, maghrib, isha]
  /// в минутах от полуночи. Бросает исключение при сетевой ошибке.
  ///
  /// [latStr]/[lngStr] — ТОЧНЫЕ строки координат из справочника ДУМК,
  /// передаются в URL дословно (endpoint ищет город по точному совпадению).
  static Future<Map<String, List<int>>> fetchYear(
      String latStr, String lngStr, int year) async {
    final url = Uri.parse('$_base/prayer-times/$year/$latStr/$lngStr');
    final resp = await http.get(url).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw Exception('muftyat.kz HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = <String, List<int>>{};
    for (final d in data['result'] as List) {
      final m = d as Map<String, dynamic>;
      result[m['Date'] as String] = [
        _mins(m['fajr'] as String),
        _mins(m['sunrise'] as String),
        _mins(m['dhuhr'] as String),
        _mins(m['asr'] as String),
        _mins(m['maghrib'] as String),
        _mins(m['isha'] as String),
      ];
    }
    if (result.isEmpty) throw Exception('muftyat.kz: пустой ответ');
    return result;
  }

  static int _mins(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }
}
