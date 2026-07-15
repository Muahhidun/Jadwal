import 'dart:convert';
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

  // ── Настройки уведомлений ──────────────────────────────────────────────
  /// Окна поклонения (по умолчанию все включены — решение владельца).
  bool notifWindow(String id) => _prefs.getBool('nw:$id') ?? true;
  void setNotifWindow(String id, bool v) => _set(() => _prefs.setBool('nw:$id', v));

  /// Оповещение о каждом намазе отдельно (fajr/dhuhr/asr/maghrib/isha).
  bool notifPrayer(String id) => _prefs.getBool('np:$id') ?? true;
  void setNotifPrayer(String id, bool v) => _set(() => _prefs.setBool('np:$id', v));

  /// Свои напоминания пользователя (конструктор).
  List<CustomReminder> get customReminders {
    final raw = _prefs.getString('customReminders');
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .map((e) => CustomReminder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _saveReminders(List<CustomReminder> list) => _set(() =>
      _prefs.setString('customReminders', jsonEncode([for (final r in list) r.toJson()])));

  void addReminder(CustomReminder r) => _saveReminders([...customReminders, r]);
  void removeReminder(String id) =>
      _saveReminders([for (final r in customReminders) if (r.id != id) r]);
  void toggleReminder(String id, bool v) => _saveReminders([
        for (final r in customReminders)
          if (r.id == id) r.copyWith(enabled: v) else r
      ]);

  /// Сворачиваемые блоки читалки (запоминаются глобально).
  bool get showTranslit => _prefs.getBool('showTranslit') ?? true;
  bool get showTranslation => _prefs.getBool('showTranslation') ?? true;
  bool get showFaz => _prefs.getBool('showFaz') ?? true;
  set showTranslit(bool v) => _set(() => _prefs.setBool('showTranslit', v));
  set showTranslation(bool v) => _set(() => _prefs.setBool('showTranslation', v));
  set showFaz(bool v) => _set(() => _prefs.setBool('showFaz', v));

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
  static String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
  String get _todayKey => dayKey(DateTime.now());

  bool isDone(String task) =>
      (_prefs.getStringList('done:$_todayKey') ?? const []).contains(task);

  List<String> doneOn(DateTime date) =>
      _prefs.getStringList('done:${dayKey(date)}') ?? const [];

  /// «Тетрадь постоянства»: день засчитан (зелёный), если выполнены
  /// оба ежедневных зикра — утренний и вечерний. Иначе — пропущен (красный).
  bool dayCompleted(DateTime date) {
    final d = doneOn(date);
    return d.contains('morning') && d.contains('evening');
  }

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

/// Своё напоминание: «за N мин до / через N мин после намаза».
class CustomReminder {
  final String id, title;
  final int prayer; // индекс Prayer (0 fajr … 5 isha)
  final int offsetMin; // отрицательное — до намаза, положительное — после
  final bool enabled;
  const CustomReminder(
      {required this.id,
      required this.title,
      required this.prayer,
      required this.offsetMin,
      this.enabled = true});

  CustomReminder copyWith({bool? enabled}) => CustomReminder(
      id: id, title: title, prayer: prayer, offsetMin: offsetMin,
      enabled: enabled ?? this.enabled);

  Map<String, dynamic> toJson() =>
      {'id': id, 't': title, 'p': prayer, 'o': offsetMin, 'e': enabled};
  factory CustomReminder.fromJson(Map<String, dynamic> j) => CustomReminder(
      id: j['id'] as String,
      title: j['t'] as String,
      prayer: j['p'] as int,
      offsetMin: j['o'] as int,
      enabled: (j['e'] as bool?) ?? true);
}
