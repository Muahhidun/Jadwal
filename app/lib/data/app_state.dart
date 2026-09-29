import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../prayer/city.dart';
import '../theme/home_scene.dart';

/// Глобальное состояние: язык, тема, город, онбординг, дневные отметки.
/// Хранится локально (shared_preferences) — без сервера и аккаунтов.
class AppState extends ChangeNotifier {
  AppState._(this._prefs);

  static Future<AppState> load() async {
    final state = AppState._(await SharedPreferences.getInstance());
    state._migrateZikrReminderDelay();
    return state;
  }

  final SharedPreferences _prefs;

  /// Старые сборки создавали уведомления зикров одновременно с намазом.
  /// Один раз переносим только прежнее нулевое значение на новый мягкий
  /// дефолт +10 минут; последующий выбор пользователя не перезаписываем.
  void _migrateZikrReminderDelay() {
    const migrationKey = 'migration:zikr_reminder_delay_v1';
    if (_prefs.getBool(migrationKey) ?? false) return;
    for (final id in const ['morning', 'evening']) {
      final raw = _prefs.getString('rc:$id');
      if (raw == null) continue;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if ((json['o'] as int?) == 0) {
          json['o'] = 10;
          _prefs.setString('rc:$id', jsonEncode(json));
        }
      } catch (_) {
        // Повреждённая старая настройка ниже будет заменена дефолтом.
      }
    }
    _prefs.setBool(migrationKey, true);
  }

  String get lang => _prefs.getString('lang') ?? 'ru';
  String get theme => _prefs.getString('theme') ?? 'dark';

  /// Художественное оформление главного экрана. Оно не связано с городом,
  /// по которому рассчитываются времена молитв.
  HomeScene get homeScene =>
      HomeScene.fromStorage(_prefs.getString('homeScene'));
  bool get onboardingDone => _prefs.getBool('onboardingDone') ?? false;

  /// Контекстное знакомство с центром напоминаний показывается отдельно от
  /// короткого первого запуска приложения и только при первом входе в раздел.
  bool get remindersGuideSeen =>
      _prefs.getBool('remindersGuideSeenV2') ?? false;

  /// Показывать дату по григорианскому календарю вместо хиджры (тап по дате).
  bool get dateGregorian => _prefs.getBool('dateGregorian') ?? false;

  /// Цветовая палитра читалки зикров. Не влияет на тему остальных экранов.
  String get readerPalette => _prefs.getString('readerPalette') ?? 'paper';

  /// Цветные правила таджвида в читалке аль-Кахф.
  bool get kahfTajweed => _prefs.getBool('kahfTajweed') ?? true;

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
  void setNotifWindow(String id, bool v) =>
      saveReminderConfig(getReminderConfig(id, lang).copyWith(enabled: v));

  /// Оповещение о каждом намазе и восходе отдельно.
  bool notifPrayer(String id) => getReminderConfig(id, lang).enabled;
  void setNotifPrayer(String id, bool v) =>
      saveReminderConfig(getReminderConfig(id, lang).copyWith(enabled: v));

  /// Громкие системные будильники для пяти намазов и восхода.
  ///
  /// Старые ключи Фаджра читаются как fallback, чтобы обновление
  /// не сбрасывало уже выбранные пользователем настройки.
  bool alarmEnabled(String prayerId) =>
      _prefs.getBool('prayer_alarm:$prayerId:enabled') ??
      (prayerId == 'fajr'
          ? (_prefs.getBool('fajr_alarm_enabled') ?? false)
          : false);

  void setAlarmEnabled(String prayerId, bool value) => _set(() {
    _prefs.setBool('prayer_alarm:$prayerId:enabled', value);
    if (prayerId == 'fajr') _prefs.setBool('fajr_alarm_enabled', value);
  });

  int alarmOffsetMinutes(String prayerId) =>
      _prefs.getInt('prayer_alarm:$prayerId:offset') ??
      (prayerId == 'fajr' ? (_prefs.getInt('fajr_alarm_offset') ?? -15) : 0);

  void setAlarmOffsetMinutes(String prayerId, int value) => _set(() {
    _prefs.setInt('prayer_alarm:$prayerId:offset', value);
    if (prayerId == 'fajr') _prefs.setInt('fajr_alarm_offset', value);
  });

  /// Усиленный сценарий пробуждения для Фаджра: основной системный
  /// будильник и три независимых резервных сигнала.
  bool get heavySleeperEnabled =>
      _prefs.getBool('fajr_alarm:heavy_sleeper_enabled') ?? false;

  void setHeavySleeperEnabled(bool value) =>
      _set(() => _prefs.setBool('fajr_alarm:heavy_sleeper_enabled', value));

  /// Подсказка открывается автоматически при первом входе в настройки Фаджра.
  bool get heavySleeperGuideSeen =>
      _prefs.getBool('fajr_alarm:heavy_sleeper_guide_seen_v1') ?? false;

  void markHeavySleeperGuideSeen() => _set(
    () => _prefs.setBool('fajr_alarm:heavy_sleeper_guide_seen_v1', true),
  );

  // Совместимость с кодом предыдущих сборок.
  bool get fajrAlarmEnabled => alarmEnabled('fajr');
  set fajrAlarmEnabled(bool value) => setAlarmEnabled('fajr', value);
  int get fajrAlarmOffsetMinutes => alarmOffsetMinutes('fajr');
  set fajrAlarmOffsetMinutes(int value) => setAlarmOffsetMinutes('fajr', value);

  /// Свои напоминания пользователя (конструктор).
  List<ReminderConfig> get customReminders {
    final raw = _prefs.getString('customReminders');
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .map((e) => ReminderConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void saveReminders(List<ReminderConfig> list) => _set(
    () => _prefs.setString(
      'customReminders',
      jsonEncode([for (final r in list) r.toJson()]),
    ),
  );

  void addReminder(ReminderConfig r) => saveReminders([...customReminders, r]);
  void removeReminder(String id) => saveReminders([
    for (final r in customReminders)
      if (r.id != id) r,
  ]);
  void toggleReminder(String id, bool v) => saveReminders([
    for (final r in customReminders)
      if (r.id == id) r.copyWith(enabled: v) else r,
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
        offsetMin: 10,
      ),
      'evening' => ReminderConfig(
        id: id,
        title: kz ? 'Кешкі зікірлер' : 'Вечерние зикры',
        enabled: _prefs.getBool('nw:evening') ?? true,
        prayer: 3,
        offsetMin: 10,
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
      if (rc.id == 'morning' ||
          rc.id == 'evening' ||
          rc.id == 'kahf' ||
          rc.id == 'dua') {
        _prefs.setBool('nw:${rc.id}', rc.enabled);
      } else if (rc.id == 'fajr' ||
          rc.id == 'dhuhr' ||
          rc.id == 'asr' ||
          rc.id == 'maghrib' ||
          rc.id == 'isha' ||
          rc.id == 'sunrise') {
        _prefs.setBool('np:${rc.id}', rc.enabled);
      }
    });
  }

  /// Сворачиваемые блоки читалки (запоминаются глобально).
  bool get showTranslit => _prefs.getBool('showTranslit') ?? true;
  bool get showTranslation => _prefs.getBool('showTranslation') ?? true;
  bool get showFaz => _prefs.getBool('showFaz') ?? true;
  set showTranslit(bool v) => _set(() => _prefs.setBool('showTranslit', v));
  set showTranslation(bool v) =>
      _set(() => _prefs.setBool('showTranslation', v));
  set showFaz(bool v) => _set(() => _prefs.setBool('showFaz', v));

  set lang(String v) => _set(() => _prefs.setString('lang', v));
  set theme(String v) => _set(() => _prefs.setString('theme', v));
  set homeScene(HomeScene v) =>
      _set(() => _prefs.setString('homeScene', v.storageValue));
  set onboardingDone(bool v) => _set(() => _prefs.setBool('onboardingDone', v));
  set remindersGuideSeen(bool v) => _set(() {
    _prefs.setBool('remindersGuideSeen', v);
    _prefs.setBool('remindersGuideSeenV2', v);
  });
  set dateGregorian(bool v) => _set(() => _prefs.setBool('dateGregorian', v));
  set readerPalette(String v) =>
      _set(() => _prefs.setString('readerPalette', v));
  set kahfTajweed(bool v) => _set(() => _prefs.setBool('kahfTajweed', v));

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

  /// Показывается ли пользовательское дело в конкретный день.
  ///
  /// Правило совпадает с планировщиком уведомлений для всех частот.
  bool reminderOccursOn(ReminderConfig reminder, DateTime date) {
    return reminder.enabled && reminder.occursOn(date);
  }

  /// Реальный прогресс дня для кольца тетради: базовые дела плюс все
  /// пользовательские напоминания, которые приходятся на эту дату.
  (int, int) taskProgressOn(DateTime date) {
    final taskIds = <String>[
      'morning',
      'evening',
      if (date.weekday == DateTime.friday) ...['kahf', 'dua'],
      for (final reminder in customReminders)
        if (reminderOccursOn(reminder, date)) 'custom:${reminder.id}',
    ];
    final done = doneOn(date);
    return (taskIds.where(done.contains).length, taskIds.length);
  }

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
  final String anchor; // 'prayer' — от намаза, 'clock' — в фиксированное время
  final int fixedHour, fixedMinute;
  final bool enabled;
  final String repeat; // 'once' / 'daily' / 'weekly' / 'monthly' / 'yearly'
  final int weekday; // legacy: один день недели (1-7)
  final List<int> weekdays; // выбранные дни недели для weekly
  final int scheduleYear, scheduleMonth, scheduleDay;

  const ReminderConfig({
    required this.id,
    required this.title,
    required this.prayer,
    required this.offsetMin,
    this.anchor = 'prayer',
    this.fixedHour = 9,
    this.fixedMinute = 0,
    this.enabled = true,
    this.repeat = 'daily',
    this.weekday = 5,
    this.weekdays = const [],
    this.scheduleYear = 0,
    this.scheduleMonth = 1,
    this.scheduleDay = 1,
  });

  bool get isPrayerLinked => anchor != 'clock';
  List<int> get effectiveWeekdays => weekdays.isEmpty ? [weekday] : weekdays;

  bool matchesScheduleDate(DateTime date) =>
      scheduleYear > 0 &&
      date.year == scheduleYear &&
      date.month == scheduleMonth &&
      date.day == scheduleDay;

  bool occursOn(DateTime date) => switch (repeat) {
    'once' => matchesScheduleDate(date),
    'weekly' => effectiveWeekdays.contains(date.weekday),
    'monthly' => date.day == scheduleDay,
    'yearly' => date.month == scheduleMonth && date.day == scheduleDay,
    _ => true,
  };

  ReminderConfig copyWith({
    String? title,
    bool? enabled,
    int? prayer,
    int? offsetMin,
    String? anchor,
    int? fixedHour,
    int? fixedMinute,
    String? repeat,
    int? weekday,
    List<int>? weekdays,
    int? scheduleYear,
    int? scheduleMonth,
    int? scheduleDay,
  }) => ReminderConfig(
    id: id,
    title: title ?? this.title,
    prayer: prayer ?? this.prayer,
    offsetMin: offsetMin ?? this.offsetMin,
    anchor: anchor ?? this.anchor,
    fixedHour: fixedHour ?? this.fixedHour,
    fixedMinute: fixedMinute ?? this.fixedMinute,
    enabled: enabled ?? this.enabled,
    repeat: repeat ?? this.repeat,
    weekday: weekday ?? this.weekday,
    weekdays: weekdays ?? this.weekdays,
    scheduleYear: scheduleYear ?? this.scheduleYear,
    scheduleMonth: scheduleMonth ?? this.scheduleMonth,
    scheduleDay: scheduleDay ?? this.scheduleDay,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    't': title,
    'p': prayer,
    'o': offsetMin,
    'a': anchor,
    'h': fixedHour,
    'm': fixedMinute,
    'e': enabled,
    'r': repeat,
    'w': weekday,
    'ws': weekdays,
    'sy': scheduleYear,
    'sm': scheduleMonth,
    'sd': scheduleDay,
  };

  factory ReminderConfig.fromJson(Map<String, dynamic> j) => ReminderConfig(
    id: j['id'] as String,
    title: j['t'] as String,
    prayer: j['p'] as int,
    offsetMin: j['o'] as int,
    anchor: (j['a'] as String?) ?? 'prayer',
    fixedHour: (j['h'] as int?) ?? 9,
    fixedMinute: (j['m'] as int?) ?? 0,
    enabled: (j['e'] as bool?) ?? true,
    repeat: (j['r'] as String?) ?? 'daily',
    weekday: (j['w'] as int?) ?? 5,
    weekdays:
        (j['ws'] as List?)?.whereType<num>().map((e) => e.toInt()).toList() ??
        const [],
    scheduleYear: (j['sy'] as int?) ?? 0,
    scheduleMonth: (j['sm'] as int?) ?? 1,
    scheduleDay: (j['sd'] as int?) ?? 1,
  );
}
