import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'city.dart';
import 'muftyat.dart';
import 'schedule.dart';

/// Источник времён молитв для UI.
///
/// Порядок: кеш на устройстве → API ДУМК (год за один запрос) →
/// астрономический расчёт (офлайн-запас). Какой источник в работе,
/// видно в [source] — покажем в настройках для прозрачности.
class ScheduleService extends ChangeNotifier {
  ScheduleService(this._prefs, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  Map<String, List<int>>? _year;
  int _loadedCity = -1;
  int _loadedYear = -1;
  String source = '';
  bool _loading = false;

  static String _key(int city, int year) => 'pt:$city:$year';
  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime now() => _now();

  /// Времена на дату. null — данные ещё грузятся (подпишитесь на notify).
  DayTimes? timesFor(int cityIndex, DateTime date) {
    _ensure(cityIndex, date.year);
    final y = _year;
    if (y == null || _loadedCity != cityIndex || _loadedYear != date.year) {
      // Пока год не загружен — мгновенный астрономический расчёт,
      // чтобы UI не ждал сеть; после загрузки таблиц ДУМК уточнится.
      return calculateDayTimes(kCities[cityIndex], date);
    }
    final t = y[_dateKey(date)];
    if (t == null) return calculateDayTimes(kCities[cityIndex], date);
    return DayTimes(date: DateTime(date.year, date.month, date.day), times: {
      for (final (i, p) in Prayer.values.indexed) p: t[i],
    });
  }

  Future<void> _ensure(int cityIndex, int year) async {
    if (_loading || (_loadedCity == cityIndex && _loadedYear == year)) return;
    _loading = true;
    try {
      final cached = _prefs.getString(_key(cityIndex, year));
      if (cached != null) {
        _apply(cityIndex, year, cached, 'ДУМК (кеш)');
        return;
      }
      final city = kCities[cityIndex];
      final data = await MuftyatApi.fetchYear(city.lat, city.lng, year);
      final encoded = jsonEncode(data.map((k, v) => MapEntry(k, v)));
      await _prefs.setString(_key(cityIndex, year), encoded);
      _apply(cityIndex, year, encoded, 'ДУМК');
    } catch (_) {
      // Сети нет и кеша нет — остаёмся на расчёте; попробуем снова
      // при следующем обращении.
      source = 'астрономический расчёт';
    } finally {
      _loading = false;
    }
  }

  void _apply(int city, int year, String encoded, String src) {
    final raw = jsonDecode(encoded) as Map<String, dynamic>;
    _year = raw.map((k, v) => MapEntry(k, (v as List).cast<int>()));
    _loadedCity = city;
    _loadedYear = year;
    source = src;
    notifyListeners();
  }

  /// Для тестов: подложить данные без сети.
  @visibleForTesting
  void preload(int city, int year, Map<String, List<int>> data, {String src = 'test'}) {
    _year = data;
    _loadedCity = city;
    _loadedYear = year;
    source = src;
  }
}

class ScheduleScope extends InheritedNotifier<ScheduleService> {
  const ScheduleScope({super.key, required ScheduleService service, required super.child})
      : super(notifier: service);

  static ScheduleService of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScheduleScope>()!.notifier!;
}
