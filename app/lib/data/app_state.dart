import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../prayer/city.dart';

/// Глобальное состояние: язык, тема, город, онбординг, дневные отметки.
/// Хранится локально (shared_preferences) — без сервера и аккаунтов.
class AppState extends ChangeNotifier {
  AppState._(this._prefs);

  static Future<AppState> load() async =>
      AppState._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  String get lang => _prefs.getString('lang') ?? 'ru';
  String get theme => _prefs.getString('theme') ?? 'dark';
  bool get onboardingDone => _prefs.getBool('onboardingDone') ?? false;

  /// Показывать дату по григорианскому календарю вместо хиджры (тап по дате).
  bool get dateGregorian => _prefs.getBool('dateGregorian') ?? false;

  /// Выбранный город (любой из справочника ДУМК). По умолчанию — Алматы.
  /// Координаты — точные строки ДУМК (см. City).
  City get city => City(
        _prefs.getString('cityName') ?? kDefaultCity.name,
        _prefs.getString('cityLatStr') ?? kDefaultCity.latStr,
        _prefs.getString('cityLngStr') ?? kDefaultCity.lngStr,
        region: _prefs.getString('cityRegion') ?? kDefaultCity.region,
      );

  set lang(String v) => _set(() => _prefs.setString('lang', v));
  set theme(String v) => _set(() => _prefs.setString('theme', v));
  set onboardingDone(bool v) => _set(() => _prefs.setBool('onboardingDone', v));
  set dateGregorian(bool v) => _set(() => _prefs.setBool('dateGregorian', v));

  void setCity(City c) => _set(() {
        _prefs.setString('cityName', c.name);
        _prefs.setString('cityLatStr', c.latStr);
        _prefs.setString('cityLngStr', c.lngStr);
        _prefs.setString('cityRegion', c.region);
      });

  /// Отметки за день: ключи morning / kahf / evening / dua.
  /// Хранятся с датой, чтобы в полночь начинался чистый день.
  String get _todayKey {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  bool isDone(String task) =>
      (_prefs.getStringList('done:$_todayKey') ?? const []).contains(task);

  void markDone(String task) => _set(() {
        final list = _prefs.getStringList('done:$_todayKey') ?? <String>[];
        if (!list.contains(task)) {
          list.add(task);
          _prefs.setStringList('done:$_todayKey', list);
        }
      });

  ThemeMode get themeMode => switch (theme) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };

  void _set(void Function() write) {
    write();
    notifyListeners();
  }
}

/// Доступ к AppState вниз по дереву без внешних пакетов.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
