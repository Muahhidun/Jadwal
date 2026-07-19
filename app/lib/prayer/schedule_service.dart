import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'city.dart';
import 'muftyat.dart';
import 'schedule.dart';

/// Источник времён молитв для UI.
///
/// Порядок: кеш на устройстве → API ДУМК (год за один запрос по координатам) →
/// астрономический расчёт (офлайн-запас). Какой источник в работе — в [source].
class ScheduleService extends ChangeNotifier {
  ScheduleService(this._prefs, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  Map<String, List<int>>? _year;
  String _loadedKey = '';
  int _loadedYear = -1;
  String source = '';
  bool _loading = false;

  /// Ключ кеша по точным координатам-строкам.
  static String cityKey(City city) => '${city.latStr},${city.lngStr}';
  static String _prefsKey(String ck, int year) => 'pt:$ck:$year';
  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime now() => _now();

  /// Времена на дату для города. Пока год не загружен — мгновенный
  /// астрономический расчёт, чтобы UI не ждал сеть; после ответа ДУМК уточнится.
  DayTimes? timesFor(City city, DateTime date) {
    final ck = cityKey(city);
    _ensure(city, date.year);
    final y = _year;
    if (y == null || _loadedKey != ck || _loadedYear != date.year) {
      return calculateDayTimes(city, date);
    }
    final t = y[_dateKey(date)];
    if (t == null) return calculateDayTimes(city, date);
    return DayTimes(date: DateTime(date.year, date.month, date.day), times: {
      for (final (i, p) in Prayer.values.indexed) p: t[i],
    });
  }

  /// Принудительно загрузить данные для города на указанный год.
  Future<void> ensureLoaded(City city, int year) async {
    final ck = cityKey(city);
    if (_loadedKey == ck && _loadedYear == year) return;
    await _ensure(city, year);
  }

  Future<void> _ensure(City city, int year) async {
    final ck = cityKey(city);
    if (_loading || (_loadedKey == ck && _loadedYear == year)) return;
    _loading = true;
    try {
      final cached = _prefs.getString(_prefsKey(ck, year));
      if (cached != null) {
        _apply(ck, year, cached, 'ДУМК (кеш)');
        return;
      }
      final data = await MuftyatApi.fetchYear(city.latStr, city.lngStr, year);
      final encoded = jsonEncode(data);
      await _prefs.setString(_prefsKey(ck, year), encoded);
      _apply(ck, year, encoded, 'ДУМК');
    } catch (_) {
      source = 'астрономический расчёт';
    } finally {
      _loading = false;
    }
  }

  void _apply(String ck, int year, String encoded, String src) {
    final raw = jsonDecode(encoded) as Map<String, dynamic>;
    _year = raw.map((k, v) => MapEntry(k, (v as List).cast<int>()));
    _loadedKey = ck;
    _loadedYear = year;
    source = src;
    notifyListeners();
  }

  /// Для тестов: подложить данные без сети.
  @visibleForTesting
  void preload(City city, int year, Map<String, List<int>> data, {String src = 'test'}) {
    _year = data;
    _loadedKey = cityKey(city);
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
