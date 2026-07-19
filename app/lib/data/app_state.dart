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
  bool notifWindow(String id) => getReminderConfig(id, lang).enabled;
  void setNotifWindow(String id, bool v) => saveReminderConfig(getReminderConfig(id, lang).copyWith(enabled: v));

  /// Оповещение о каждом намазе отдельно (fajr/dhuhr/asr/maghrib/isha).
  bool notifPrayer(String id) => getReminderConfig(id, lang).enabled;
  void setNotifPrayer(String id, bool v) => saveReminderConfig(getReminderConfig(id, lang).copyWith(enabled: v));

  /// Свои напоминания пользователя (конструктор).
  List<ReminderConfig> get customReminders {
    final raw = _prefs.getString('customReminders');
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .map((e) => ReminderConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void saveReminders(List<ReminderConfig> list) => _set(() =>
      _prefs.setString('customReminders', jsonEncode([for (final r in list) r.toJson()])));

  void addReminder(ReminderConfig r) => saveReminders([...customReminders, r]);
  void removeReminder(String id) =>
      saveReminders([for (final r in customReminders) if (r.id != id) r]);
  void toggleReminder(String id, bool v) => saveReminders([
        for (final r in customReminders)
          if (r.id == id) r.copyWith(enabled: v) else r
      ]);

  ReminderConfig getReminderConfig(String id, String lang) {
    final raw = _prefs.getString('rc:$id');
    if (raw != null) {
      try {
        return ReminderConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }

    final kz = lang == 'kz';
    return switch (id) {
      'morning' => ReminderConfig(
          id: id,
          title: kz ? 'Таңғы зікірлер' : 'Утренние зикры',
          enabled: _prefs.getBool('nw:morning') ?? true,
          prayer: 0,
          offsetMin: 0,
        ),
      'evening' => ReminderConfig(
          id: id,
          title: kz ? 'Кешкі зікірлер' : 'Вечерние зикры',
          enabled: _prefs.getBool('nw:evening') ?? true,
          prayer: 3,
          offsetMin: 0,
        ),
      'kahf' => ReminderConfig(
          id: id,
          title: kz ? '«әл-Кәһф» сүресі (жұма)' : 'Сура аль-Кахф (пятница)',
          enabled: _prefs.getBool('nw:kahf') ?? true,
          prayer: 2,
          offsetMin: -120,
          repeat: 'weekly',
        ),
      'dua' => ReminderConfig(
          id: id,
          title: kz ? 'Дұға сағаты (жұма)' : 'Час дуа (пятница)',
          enabled: _prefs.getBool('nw:dua') ?? true,
          prayer: 4,
          offsetMin: -60,
          repeat: 'weekly',
        ),
      'fajr' => ReminderConfig(
          id: id,
          title: kz ? 'Таң' : 'Фаджр',
          enabled: _prefs.getBool('np:fajr') ?? true,
          prayer: 0,
          offsetMin: 0,
        ),
      'sunrise' => ReminderConfig(
          id: id,
          title: kz ? 'Күн шығуы' : 'Восход',
          enabled: _prefs.getBool('np:sunrise') ?? true,
          prayer: 1,
          offsetMin: 0,
        ),
      'dhuhr' => ReminderConfig(
          id: id,
          title: kz ? 'Бесін' : 'Зухр',
          enabled: _prefs.getBool('np:dhuhr') ?? true,
          prayer: 2,
          offsetMin: 0,
        ),
      'asr' => ReminderConfig(
          id: id,
          title: kz ? 'Екінті' : 'Аср',
          enabled: _prefs.getBool('np:asr') ?? true,
          prayer: 3,
          offsetMin: 0,
        ),
      'maghrib' => ReminderConfig(
          id: id,
          title: kz ? 'Ақшам' : 'Магриб',
          enabled: _prefs.getBool('np:maghrib') ?? true,
          prayer: 4,
          offsetMin: 0,
        ),
      'isha' => ReminderConfig(
          id: id,
          title: kz ? 'Құптан' : 'Иша',
          enabled: _prefs.getBool('np:isha') ?? true,
          prayer: 5,
          offsetMin: 0,
        ),
      _ => ReminderConfig(
          id: id,
          title: 'Напоминание',
          enabled: true,
          prayer: 0,
          offsetMin: 0,
        ),
    };
  }

  void saveReminderConfig(ReminderConfig rc) {
    _set(() {
      _prefs.setString('rc:${rc.id}', jsonEncode(rc.toJson()));
      if (rc.id == 'morning' || rc.id == 'evening' || rc.id == 'kahf' || rc.id == 'dua') {
        _prefs.setBool('nw:${rc.id}', rc.enabled);
      } else if (rc.id == 'fajr' || rc.id == 'dhuhr' || rc.id == 'asr' || rc.id == 'maghrib' || rc.id == 'isha' || rc.id == 'sunrise') {
        _prefs.setBool('np:${rc.id}', rc.enabled);
      }
    });
  }

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

/// Описание настроек напоминания.
class ReminderConfig {
  final String id, title;
  final int prayer; // индекс Prayer (0 fajr … 5 isha)
  final int offsetMin; // отрицательное — до намаза, положительное — после
  final bool enabled;
  final String repeat; // 'daily' / 'weekly' / 'monthly'
  final int weekday; // день недели (1-7, default 5 = пятница)

  const ReminderConfig({
    required this.id,
    required this.title,
    required this.prayer,
    required this.offsetMin,
    this.enabled = true,
    this.repeat = 'daily',
    this.weekday = 5,
  });

  ReminderConfig copyWith({
    String? title,
    bool? enabled,
    int? prayer,
    int? offsetMin,
    String? repeat,
    int? weekday,
  }) => ReminderConfig(
    id: id,
    title: title ?? this.title,
    prayer: prayer ?? this.prayer,
    offsetMin: offsetMin ?? this.offsetMin,
    enabled: enabled ?? this.enabled,
    repeat: repeat ?? this.repeat,
    weekday: weekday ?? this.weekday,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    't': title,
    'p': prayer,
    'o': offsetMin,
    'e': enabled,
    'r': repeat,
    'w': weekday,
  };

  factory ReminderConfig.fromJson(Map<String, dynamic> j) => ReminderConfig(
    id: j['id'] as String,
    title: j['t'] as String,
    prayer: j['p'] as int,
    offsetMin: j['o'] as int,
    enabled: (j['e'] as bool?) ?? true,
    repeat: (j['r'] as String?) ?? 'daily',
    weekday: (j['w'] as int?) ?? 5,
  );
}
