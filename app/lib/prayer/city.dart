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

  /// Откуда берутся времена: '' — справочник и API ДУМК (по умолчанию),
  /// [sourceLocal] — место за пределами Казахстана, местный расчёт (Aladhan).
  final String source;

  const City(
    this.name,
    this.latStr,
    this.lngStr, {
    this.region = '',
    this.source = '',
  });

  static const sourceLocal = 'local';

  /// За пределами справочника ДУМК: времена — местный расчёт, не таблица ДУМК.
  bool get isLocalCalc => source == sourceLocal;

  double get lat => double.parse(latStr);
  double get lng => double.parse(lngStr);

  /// Название из ДУМК остаётся каноническим ключом для расписания, а в UI
  /// показываем привычную форму выбранного языка.
  String displayName(String lang) =>
      isLocalCalc ? name : (lang == 'kz' ? name : _russianCityName(name));

  String displayRegion(String lang) => isLocalCalc
      ? region
      : (lang == 'kz' ? region : _russianRegionName(region));

  factory City.fromJson(Map<String, dynamic> j) => City(
    j['t'] as String,
    j['lat'] as String,
    j['lng'] as String,
    region: (j['r'] as String?) ?? '',
  );
}

/// Город по умолчанию — Алматы (точные координаты ДУМК).
const kDefaultCity = City('Алматы', '43.238293', '76.945465', region: 'Алматы');

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
  static Future<City> nearest(double lat, double lng) async =>
      (await nearestWithDistance(lat, lng)).$1;

  /// Ближайший пункт справочника и расстояние до него в километрах. Если
  /// расстояние большое — человек за пределами Казахстана.
  static Future<(City, double)> nearestWithDistance(
    double lat,
    double lng,
  ) async {
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
    return (best, bestD);
  }

  /// Расстояние между точками в километрах.
  static double distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) => _haversine(lat1, lng1, lat2, lng2);

  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll('ә', 'а')
        .replaceAll('ғ', 'г')
        .replaceAll('қ', 'к')
        .replaceAll('ң', 'н')
        .replaceAll('ө', 'о')
        .replaceAll('ұ', 'у')
        .replaceAll('ү', 'у')
        .replaceAll('һ', 'х')
        .replaceAll('і', 'и')
        .replaceAll('э', 'е')
        .replaceAll('ё', 'е')
        .replaceAll('й', 'и')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'[^a-zа-я0-9\s]'), '');
  }

  /// Поиск по названию (регистронезависимо с нормализацией и русскими синонимами).
  static Future<List<City>> search(
    String query, {
    String lang = 'ru',
    int limit = 40,
  }) async {
    final all = await load();
    final rawQ = query.trim().toLowerCase();
    if (rawQ.isEmpty) return const [];

    final qNorm = _normalize(rawQ);
    final searchTerms = [qNorm];

    // Синонимы для русскоязычного поиска городов Казахстана
    const synonyms = {
      'уральск': 'орал',
      'петропавловск': 'петропавл',
      'устькаменогорск': 'оскемен',
      'усть каменогорск': 'оскемен',
      'капчагай': 'капшагаи',
      'кокчетав': 'кокшетау',
      'семипалатинск': 'семеи',
      'караганда': 'караганды',
      'кустанай': 'костанаи',
      'кустанаи': 'костанаи',
      'чимкент': 'шымкент',
      'джамбул': 'тараз',
      'талдыкурган': 'талдыкорган',
      'талды курган': 'талдыкорган',
      'чу': 'шу',
    };

    for (final entry in synonyms.entries) {
      if (qNorm.contains(entry.key) || entry.key.contains(qNorm)) {
        searchTerms.add(entry.value);
      }
    }

    final starts = <City>[];
    final contains = <City>[];

    for (final c in all) {
      final nameNorm = _normalize(c.name);
      final regionNorm = _normalize(c.region);
      final displayNameNorm = _normalize(c.displayName(lang));
      final displayRegionNorm = _normalize(c.displayRegion(lang));

      bool isStart = false;
      bool isContain = false;

      for (final term in searchTerms) {
        if (nameNorm.startsWith(term) || displayNameNorm.startsWith(term)) {
          isStart = true;
          break;
        } else if (nameNorm.contains(term) ||
            regionNorm.contains(term) ||
            displayNameNorm.contains(term) ||
            displayRegionNorm.contains(term)) {
          isContain = true;
        }
      }

      if (isStart) {
        starts.add(c);
      } else if (isContain) {
        contains.add(c);
      }
    }

    return [...starts, ...contains].take(limit).toList();
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;
}

const _russianCityNames = <String, String>{
  'Екібастұз': 'Экибастуз',
  'Қарағанды': 'Караганда',
  'Ақтөбе': 'Актобе',
  'Өскемен': 'Усть-Каменогорск',
  'Орал': 'Уральск',
  'Петропавл': 'Петропавловск',
  'Көкшетау': 'Кокшетау',
  'Қостанай': 'Костанай',
  'Талдықорған': 'Талдыкорган',
  'Түркістан': 'Туркестан',
  'Қызылорда': 'Кызылорда',
  'Жезқазған': 'Жезказган',
  'Қонаев': 'Конаев',
};

String _russianCityName(String value) {
  // ДУМК часть городов возвращает как «Өскемен қаласы». Суффикс
  // «город» не является частью названия и мешал точному русскому словарю.
  final canonical = value
      .replaceFirst(RegExp(r'\s+қаласы$', caseSensitive: false), '')
      .trim();
  return _russianCityNames[canonical] ?? _kazakhToRussianLetters(canonical);
}

String _russianRegionName(String value) {
  if (value.isEmpty) return value;
  const exact = <String, String>{
    'Абай облысы': 'Абайская область',
    'Ақмола облысы': 'Акмолинская область',
    'Ақтөбе облысы': 'Актюбинская область',
    'Алматы облысы': 'Алматинская область',
    'Атырау облысы': 'Атырауская область',
    'Батыс Қазақстан облысы': 'Западно-Казахстанская область',
    'Жамбыл облысы': 'Жамбылская область',
    'Жетісу облысы': 'область Жетысу',
    'Қарағанды облысы': 'Карагандинская область',
    'Қостанай облысы': 'Костанайская область',
    'Қызылорда облысы': 'Кызылординская область',
    'Маңғыстау облысы': 'Мангистауская область',
    'Павлодар облысы': 'Павлодарская область',
    'Солтүстік Қазақстан облысы': 'Северо-Казахстанская область',
    'Түркістан облысы': 'Туркестанская область',
    'Ұлытау облысы': 'область Улытау',
    'Шығыс Қазақстан облысы': 'Восточно-Казахстанская область',
  };
  return exact[value] ??
      _kazakhToRussianLetters(value).replaceAll(' облысы', ' область');
}

String _kazakhToRussianLetters(String value) => value
    .replaceAll('Ә', 'А')
    .replaceAll('ә', 'а')
    .replaceAll('Ғ', 'Г')
    .replaceAll('ғ', 'г')
    .replaceAll('Қ', 'К')
    .replaceAll('қ', 'к')
    .replaceAll('Ң', 'Н')
    .replaceAll('ң', 'н')
    .replaceAll('Ө', 'О')
    .replaceAll('ө', 'о')
    .replaceAll('Ұ', 'У')
    .replaceAll('ұ', 'у')
    .replaceAll('Ү', 'У')
    .replaceAll('ү', 'у')
    .replaceAll('Һ', 'Х')
    .replaceAll('һ', 'х')
    .replaceAll('І', 'И')
    .replaceAll('і', 'и');
