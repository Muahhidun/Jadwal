import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'city.dart';
import 'aladhan.dart';
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

  final _years = <String, Map<String, List<int>>>{};
  final _loads = <String, Future<void>>{};
  String source = '';
  int _revision = 0;

  /// Меняется после получения расписания: главный экран перепланирует
  /// уведомления, даже если город и настройки пользователя остались прежними.
  int get revision => _revision;

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
    final y = _years[_prefsKey(ck, date.year)];
    if (y == null) return calculateDayTimes(city, date);
    final t = y[_dateKey(date)];
    if (t == null) return calculateDayTimes(city, date);
    return DayTimes(
      date: DateTime(date.year, date.month, date.day),
      times: {for (final (i, p) in Prayer.values.indexed) p: t[i]},
    );
  }

  /// Принудительно загрузить данные для города на указанный год.
  Future<void> ensureLoaded(City city, int year) => _ensure(city, year);

  Future<void> _ensure(City city, int year) {
    final ck = cityKey(city);
    final key = _prefsKey(ck, year);
    if (_years.containsKey(key)) return Future<void>.value();
    // UI, обычные уведомления и будильники ждут один запрос. Другой город
    // или год имеют собственный запрос и не теряются за общим флагом loading.
    return _loads.putIfAbsent(
      key,
      () => _load(city, year).whenComplete(() {
        _loads.remove(key);
      }),
    );
  }

  Future<void> _load(City city, int year) async {
    // timesFor вызывается при построении UI. Даже ответ из кеша публикуем
    // после этого синхронного кадра, когда запрос уже занесён в _loads.
    await Future<void>.value();
    final ck = cityKey(city);
    try {
      final local = city.isLocalCalc;
      final cached = _prefs.getString(_prefsKey(ck, year));
      if (cached != null) {
        _apply(ck, year, cached, local ? 'Aladhan (кеш)' : 'ДУМК (кеш)');
        return;
      }
      // За пределами Казахстана — Aladhan по координатам места; в Казахстане
      // — только ДУМК по точным координатам справочника.
      final data = local
          ? await AladhanApi.fetchYear(city.lat, city.lng, year)
          : await MuftyatApi.fetchYear(city.latStr, city.lngStr, year);
      final encoded = jsonEncode(data);
      await _prefs.setString(_prefsKey(ck, year), encoded);
      _apply(ck, year, encoded, local ? 'Aladhan' : 'ДУМК');
    } catch (_) {
      source = 'астрономический расчёт';
    }
  }

  void _apply(String ck, int year, String encoded, String src) {
    final raw = jsonDecode(encoded) as Map<String, dynamic>;
    _years[_prefsKey(ck, year)] = raw.map(
      (k, v) => MapEntry(k, (v as List).cast<int>()),
    );
    source = src;
    _revision++;
    notifyListeners();
  }

  /// Для тестов: подложить данные без сети.
  @visibleForTesting
  void preload(
    City city,
    int year,
    Map<String, List<int>> data, {
    String src = 'test',
  }) {
    _years[_prefsKey(cityKey(city), year)] = data;
    source = src;
    _revision++;
  }
}

class ScheduleScope extends InheritedNotifier<ScheduleService> {
  const ScheduleScope({
    super.key,
    required ScheduleService service,
    required super.child,
  }) : super(notifier: service);

  static ScheduleService of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScheduleScope>()!.notifier!;
}
