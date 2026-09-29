import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/app_state.dart';
import '../prayer/city.dart';
import '../prayer/schedule.dart';
import '../prayer/schedule_service.dart';
import '../prayer/windows.dart';
import '../services/alarm_service.dart';

/// Глобальный сервис уведомлений (создаётся в main; null в тестах).
NotificationService? gNotifier;

/// Чистый расчёт времени пользовательского напоминания.
/// Вынесен отдельно, чтобы проверять оба режима без нативного API.
DateTime reminderScheduledTime(
  ReminderConfig reminder,
  DateTime date,
  DayTimes? dayTimes,
) {
  if (!reminder.isPrayerLinked) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      reminder.fixedHour,
      reminder.fixedMinute,
    );
  }
  if (dayTimes == null) {
    throw StateError('Prayer-linked reminder requires prayer times.');
  }
  final prayer = Prayer.values[reminder.prayer];
  final baseTime = dayTimes.times[prayer];
  if (baseTime == null) {
    throw StateError('Prayer time is unavailable for ${reminder.id}.');
  }
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).add(Duration(minutes: baseTime + reminder.offsetMin));
}

/// Контент, который должен открыться по тапу на локальное уведомление.
String notificationTargetFor(String reminderId) => switch (reminderId) {
  'morning' || 'evening' || 'kahf' => reminderId,
  _ => '',
};

// ── Кнопки в уведомлениях ────────────────────────────────────────────────────
// У напоминаний о делах (зикры, аль-Кахф, час дуа, свои напоминания) внизу две
// кнопки: «Выполнено» отмечает дело прямо из уведомления, «Через 10 мин»
// присылает то же напоминание повторно. Уведомления о времени намаза — без
// кнопок: это справка, а не дело.

const kTaskCategory = 'dauam_task';
const kActionDone = 'done';
const kActionSnooze = 'snooze';
const kSnoozeMinutes = 10;
const _snoozeKey = 'notif:snoozes';
const _builtInPrayerIds = {
  'fajr',
  'sunrise',
  'dhuhr',
  'asr',
  'maghrib',
  'isha',
};

/// Ключ отметки дела для напоминания: как в AppState.markDone.
String notificationTaskFor(String reminderId) {
  if (_builtInPrayerIds.contains(reminderId)) return '';
  if (const {'morning', 'evening', 'kahf', 'dua'}.contains(reminderId)) {
    return reminderId;
  }
  return 'custom:$reminderId';
}

/// Что лежит в уведомлении: что открыть по тапу, какое дело и за какой день
/// отметить, и текст — чтобы повторить его при «отложить».
@immutable
class NotificationPayload {
  const NotificationPayload({
    this.open = '',
    this.task = '',
    this.date = '',
    this.title = '',
    this.body = '',
  });

  final String open, task, date, title, body;

  String encode() =>
      jsonEncode({'o': open, 't': task, 'd': date, 'ti': title, 'b': body});

  /// Старые уведомления (до кнопок) несли только id сборника.
  static NotificationPayload parse(String? raw) {
    if (raw == null || raw.isEmpty) return const NotificationPayload();
    if (!raw.startsWith('{')) return NotificationPayload(open: raw);
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return NotificationPayload(
        open: m['o'] as String? ?? '',
        task: m['t'] as String? ?? '',
        date: m['d'] as String? ?? '',
        title: m['ti'] as String? ?? '',
        body: m['b'] as String? ?? '',
      );
    } catch (_) {
      return const NotificationPayload();
    }
  }
}

String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// Кнопка нажата, когда приложение выгружено: система поднимает отдельный
/// фоновый движок и вызывает эту функцию. Интерфейс при этом не открывается.
@pragma('vm:entry-point')
Future<void> notificationActionBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  await applyNotificationAction(response, FlutterLocalNotificationsPlugin());
}

/// Общая обработка кнопок — и в фоне, и при открытом приложении.
Future<void> applyNotificationAction(
  NotificationResponse response,
  FlutterLocalNotificationsPlugin plugin,
) async {
  final action = response.actionId;
  if (action != kActionDone && action != kActionSnooze) return;
  final payload = NotificationPayload.parse(response.payload);
  if (payload.task.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();

  if (action == kActionDone) {
    final day = payload.date.isNotEmpty
        ? payload.date
        : _dayKey(DateTime.now());
    final key = 'done:$day';
    final list = prefs.getStringList(key) ?? <String>[];
    if (!list.contains(payload.task)) {
      list.add(payload.task);
      await prefs.setStringList(key, list);
    }
    // Дело сделано — повторное «до конца окна 30 минут» за этот день и
    // отложенные копии больше не нужны.
    try {
      for (final pending in await plugin.pendingNotificationRequests()) {
        final other = NotificationPayload.parse(pending.payload);
        if (other.task == payload.task && other.date == payload.date) {
          await plugin.cancel(id: pending.id);
        }
      }
    } catch (_) {}
    await _dropSnoozes(prefs, (s) => s.payload.task == payload.task);
    return;
  }

  // Отложить: то же напоминание через 10 минут. Время ставим в UTC — для
  // разового уведомления часовой пояс устройства не нужен.
  tzdata.initializeTimeZones();
  final at = DateTime.now().add(const Duration(minutes: kSnoozeMinutes));
  final id = 950000 + (at.millisecondsSinceEpoch ~/ 1000) % 40000;
  await _scheduleSnooze(
    plugin,
    id,
    at,
    payload,
    soundId: prefs.getString('sound:task') ?? 'default',
    lang: prefs.getString('lang') ?? 'ru',
  );
  final snoozes = _readSnoozes(prefs)
    ..removeWhere((s) => !s.at.isAfter(DateTime.now()))
    ..add(_Snooze(id, at, payload));
  await prefs.setString(
    _snoozeKey,
    jsonEncode([for (final s in snoozes) s.toJson()]),
  );
}

@immutable
class _Snooze {
  const _Snooze(this.id, this.at, this.payload);
  final int id;
  final DateTime at;
  final NotificationPayload payload;

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.millisecondsSinceEpoch,
    'p': payload.encode(),
  };
}

List<_Snooze> _readSnoozes(SharedPreferences prefs) {
  try {
    final raw = prefs.getString(_snoozeKey);
    if (raw == null) return [];
    return [
      for (final m in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        _Snooze(
          m['id'] as int,
          DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
          NotificationPayload.parse(m['p'] as String?),
        ),
    ];
  } catch (_) {
    return [];
  }
}

Future<void> _dropSnoozes(
  SharedPreferences prefs,
  bool Function(_Snooze) where,
) async {
  final left = _readSnoozes(prefs)..removeWhere(where);
  await prefs.setString(
    _snoozeKey,
    jsonEncode([for (final s in left) s.toJson()]),
  );
}

Future<void> _scheduleSnooze(
  FlutterLocalNotificationsPlugin plugin,
  int id,
  DateTime at,
  NotificationPayload payload, {
  String soundId = 'default',
  String lang = 'ru',
}) async {
  await plugin.zonedSchedule(
    id: id,
    scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
    notificationDetails: notificationDetailsFor(
      soundId: soundId,
      task: true,
      lang: lang,
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    title: payload.title,
    body: payload.body,
    payload: payload.encode(),
  );
}

// ── Звуки уведомлений ────────────────────────────────────────────────────────
// iPhone не даёт приложениям брать встроенные мелодии телефона, поэтому свой
// набор: системный звук и три спокойных сигнала (синтезированы для Дауам).
// На Android у каждого звука свой канал — так требует система.

class NotifSound {
  const NotifSound(this.id, this.ru, this.kz, {this.file = ''});

  final String id, ru, kz;

  /// Имя файла без расширения (ios/Runner/*.wav, res/raw/*.wav);
  /// пусто — системный звук.
  final String file;

  String title(String lang) => lang == 'kz' ? kz : ru;
}

const kNotifSounds = [
  NotifSound('default', 'Стандартный', 'Стандартты'),
  NotifSound('bell', 'Колокольчик', 'Қоңырау', file: 'dauam_bell'),
  NotifSound('chime', 'Перезвон', 'Сыңғыр', file: 'dauam_chime'),
  NotifSound('drop', 'Капля', 'Тамшы', file: 'dauam_drop'),
];

NotifSound notifSound(String id) => kNotifSounds.firstWhere(
  (sound) => sound.id == id,
  orElse: () => kNotifSounds.first,
);

/// Оформление уведомления: звук и, для дел, кнопки «Выполнено» / «Через 10 мин».
NotificationDetails notificationDetailsFor({
  required String soundId,
  required bool task,
  String lang = 'ru',
}) {
  final sound = notifSound(soundId);
  final custom = sound.file.isNotEmpty;
  return NotificationDetails(
    android: AndroidNotificationDetails(
      custom ? 'jadwal_worship_${sound.id}' : 'jadwal_worship',
      custom ? 'Поклонение · ${sound.ru}' : 'Поклонение',
      channelDescription: 'Напоминания об окнах зикра и намазах',
      importance: Importance.high,
      priority: Priority.high,
      sound: custom ? RawResourceAndroidNotificationSound(sound.file) : null,
      actions: task
          ? [
              AndroidNotificationAction(
                kActionDone,
                lang == 'kz' ? 'Орындалды' : 'Выполнено',
              ),
              AndroidNotificationAction(
                kActionSnooze,
                lang == 'kz' ? '10 минуттан кейін' : 'Через 10 мин',
              ),
            ]
          : null,
    ),
    iOS: DarwinNotificationDetails(
      categoryIdentifier: task ? kTaskCategory : null,
      sound: custom ? '${sound.file}.wav' : null,
    ),
  );
}

/// Перепланировать очередь из текущего состояния приложения.
Future<void> syncNotifications(AppState app, ScheduleService schedule) async {
  final now = schedule.now();
  // Асинхронно ожидаем загрузку данных ДУМК из кэша/сети, чтобы время не расходилось с Sajda.kz!
  await schedule.ensureLoaded(app.city, now.year);
  if (now.month == 12 && now.day >= 18) {
    await schedule.ensureLoaded(app.city, now.year + 1);
  }

  final ids = [
    'morning',
    'evening',
    'kahf',
    'dua',
    'fajr',
    'sunrise',
    'dhuhr',
    'asr',
    'maghrib',
    'isha',
  ];
  final configs = [
    for (final id in ids) app.getReminderConfig(id, app.lang),
    ...app.customReminders,
  ];

  await gNotifier?.reschedule(
    lang: app.lang,
    city: app.city,
    configs: configs,
    doneToday: {
      for (final id in TaskId.values)
        if (app.isDone(id.name)) id,
    },
    prayerSound: app.prayerSound,
    taskSound: app.taskSound,
  );
  await AlarmService.sync(app, schedule);
}

/// Локализованные тексты уведомлений (ru/kz).
class _NotifText {
  final String title, body;
  const _NotifText(this.title, this.body);
}

/// Короткий текст для встроенных временных точек. Восход входит в
/// расписание, но не является намазом и не должен использовать общий
/// молитвенный шаблон.
({String title, String body}) prayerNotificationCopy(String lang, Prayer p) {
  final kz = lang == 'kz';
  if (p == Prayer.sunrise) {
    return (
      title: kz ? 'Күн шығуы' : 'Восход солнца',
      body: kz ? 'Күн шықты.' : 'Наступил восход солнца.',
    );
  }
  final names = kz
      ? ['Таң', 'Күн шығуы', 'Бесін', 'Екінті', 'Ақшам', 'Құптан']
      : ['Фаджр', 'Восход', 'Зухр', 'Аср', 'Магриб', 'Иша'];
  final name = names[p.index];
  return (
    title: name,
    body: kz ? '$name намазының уақыты кірді' : 'Наступило время намаза $name',
  );
}

/// Сервис локальных уведомлений.
///
/// iOS хранит в очереди максимум 64 запланированных уведомления и убивает
/// фоновые процессы, поэтому планируем очередь на несколько дней вперёд при
/// каждом открытии приложения и держимся в пределах лимита ([_cap]).
class NotificationService {
  NotificationService(this._schedule);

  final ScheduleService _schedule;
  final _plugin = FlutterLocalNotificationsPlugin();

  /// Запас под лимит iOS в 64.
  static const _cap = 58;
  static const _daysAhead = 14;
  static const _reminderBeforeEndMin = 30;

  /// Куда вести по тапу на уведомление зикров (id сборника) — читает main.
  String? pendingCollection;

  /// Главный экран подписывается, чтобы открыть чтение по тапу, даже когда
  /// приложение было в фоне (раньше тап в этом случае терялся).
  void Function(String target)? onOpen;

  /// Кнопка «Выполнено» нажата при запущенном приложении — обновить экран.
  VoidCallback? onTaskChanged;

  Future<void> init({String lang = 'ru'}) async {
    final kz = lang == 'kz';
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Almaty'));
    }
    final settings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            kTaskCategory,
            actions: [
              DarwinNotificationAction.plain(
                kActionDone,
                kz ? 'Орындалды' : 'Выполнено',
              ),
              DarwinNotificationAction.plain(
                kActionSnooze,
                kz ? '10 минуттан кейін' : 'Через 10 мин',
              ),
            ],
          ),
        ],
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: notificationActionBackground,
    );
    // Уведомление, из которого приложение было запущено (холодный старт).
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp ?? false) {
      final open = NotificationPayload.parse(response?.payload).open;
      if (open.isNotEmpty) pendingCollection = open;
    }
  }

  Future<void> _onResponse(NotificationResponse r) async {
    if (r.actionId == kActionDone || r.actionId == kActionSnooze) {
      await applyNotificationAction(r, _plugin);
      onTaskChanged?.call();
      return;
    }
    final open = NotificationPayload.parse(r.payload).open;
    if (open.isEmpty) return;
    final handler = onOpen;
    if (handler != null) {
      handler(open);
    } else {
      pendingCollection = open;
    }
  }

  /// Запросить разрешение на уведомления (iOS/Android 13+).
  Future<bool> requestPermission() async {
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  /// Прослушать звук: сразу показать пробное уведомление с ним — так
  /// слышно ровно то, что прозвучит в напоминании.
  Future<void> preview(String soundId, {required String lang}) => _plugin.show(
    id: 999001,
    title: lang == 'kz' ? 'Дауам' : 'Дауам',
    body: lang == 'kz'
        ? 'Еске салу осылай естіледі'
        : 'Так будет звучать напоминание',
    notificationDetails: notificationDetailsFor(
      soundId: soundId,
      task: false,
      lang: lang,
    ),
  );

  /// Перепланировать всю очередь. Вызывать при старте, смене города/настроек
  /// и при отметке «выполнено» ([doneToday] — какие задачи уже выполнены сегодня).
  Future<void> reschedule({
    required String lang,
    required City city,
    required List<ReminderConfig> configs,
    required Set<TaskId> doneToday,
    String prayerSound = 'default',
    String taskSound = 'default',
  }) async {
    await _plugin.cancelAll();
    final now = _schedule.now();
    int count = 0;
    final details = notificationDetailsFor(
      soundId: prayerSound,
      task: false,
      lang: lang,
    );
    final taskDetails = notificationDetailsFor(
      soundId: taskSound,
      task: true,
      lang: lang,
    );

    // Отложенные «через 10 минут» переживают перепланирование очереди.
    try {
      final prefs = await SharedPreferences.getInstance();
      final snoozes = _readSnoozes(prefs)
        ..removeWhere((s) => !s.at.isAfter(DateTime.now()));
      for (final snooze in snoozes) {
        await _scheduleSnooze(
          _plugin,
          snooze.id,
          snooze.at,
          snooze.payload,
          soundId: taskSound,
          lang: lang,
        );
        count++;
      }
      await prefs.setString(
        _snoozeKey,
        jsonEncode([for (final s in snoozes) s.toJson()]),
      );
    } catch (_) {}

    // Редкие расписания не должны зависеть от 14-дневного окна ежедневной
    // очереди. Для одноразового, ежемесячного и ежегодного напоминания заранее
    // ставим ближайшее срабатывание, после чего обычная синхронизация при
    // следующем открытии приложения продлит последовательность.
    for (final rc in configs.where(
      (item) =>
          item.enabled &&
          const {'once', 'monthly', 'yearly'}.contains(item.repeat),
    )) {
      if (count >= _cap) break;
      for (final date in _sparseCandidateDates(rc, now)) {
        final t = _schedule.timesFor(city, date);
        if (rc.isPrayerLinked && t == null) continue;
        final scheduledTime = reminderScheduledTime(rc, date, t);
        if (!scheduledTime.isAfter(now)) continue;
        final txt = _getNotificationText(lang, rc);
        final task = notificationTaskFor(rc.id);
        await _schedule0(
          900000 + _slotFor(rc.id, configs),
          scheduledTime,
          txt,
          _payload(rc.id, task, date, txt),
          task.isEmpty ? details : taskDetails,
        );
        count++;
        break;
      }
    }

    for (var d = 0; d < _daysAhead && count < _cap; d++) {
      final date = DateTime(now.year, now.month, now.day + d);
      final t = _schedule.timesFor(city, date);
      final isToday = d == 0;

      for (final rc in configs) {
        if (!rc.enabled) continue;
        if (const {'once', 'monthly', 'yearly'}.contains(rc.repeat)) continue;

        // Фильтр по частоте повторения
        if (rc.repeat == 'weekly') {
          if (!rc.effectiveWeekdays.contains(date.weekday)) continue;
        }

        // Проверяем, выполнено ли сегодня
        if (isToday) {
          if (rc.id == 'morning' && doneToday.contains(TaskId.morning)) {
            continue;
          }
          if (rc.id == 'evening' && doneToday.contains(TaskId.evening)) {
            continue;
          }
          if (rc.id == 'kahf' && doneToday.contains(TaskId.kahf)) continue;
          if (rc.id == 'dua' && doneToday.contains(TaskId.dua)) continue;
        }

        if (rc.isPrayerLinked && t == null) continue;
        final scheduledTime = reminderScheduledTime(rc, date, t);
        final slot = _slotFor(rc.id, configs);
        final task = notificationTaskFor(rc.id);
        final rcDetails = task.isEmpty ? details : taskDetails;

        // Первичное напоминание (в момент наступления события)
        if (scheduledTime.isAfter(now) && count < _cap) {
          final txt = _getNotificationText(lang, rc);
          await _schedule0(
            _id(d, slot),
            scheduledTime,
            txt,
            _payload(rc.id, task, date, txt),
            rcDetails,
          );
          count++;
        }

        // Дополнительное напоминание перед завершением утреннего/вечернего окна (за 30 минут)
        if (t != null && (rc.id == 'morning' || rc.id == 'evening')) {
          final endPrayer = rc.id == 'morning'
              ? Prayer.sunrise
              : Prayer.maghrib;
          final endTime = t.times[endPrayer];
          if (endTime != null) {
            final remindAt = _at(date, endTime - _reminderBeforeEndMin);
            if (remindAt.isAfter(now) && count < _cap) {
              final rTxt = _windowText(
                lang,
                rc.id == 'morning' ? TaskId.morning : TaskId.evening,
                opening: false,
              );
              await _schedule0(
                _id(d, slot + 20),
                remindAt,
                rTxt,
                _payload(rc.id, task, date, rTxt),
                rcDetails,
              );
              count++;
            }
          }
        }
      }
    }
  }

  Iterable<DateTime> _sparseCandidateDates(
    ReminderConfig reminder,
    DateTime now,
  ) sync* {
    if (reminder.repeat == 'once') {
      if (reminder.scheduleYear > 0) {
        yield DateTime(
          reminder.scheduleYear,
          reminder.scheduleMonth,
          reminder.scheduleDay,
        );
      }
      return;
    }

    if (reminder.repeat == 'monthly') {
      for (var delta = 0; delta <= 12; delta++) {
        final monthStart = DateTime(now.year, now.month + delta);
        final candidate = DateTime(
          monthStart.year,
          monthStart.month,
          reminder.scheduleDay,
        );
        if (candidate.month == monthStart.month) yield candidate;
      }
      return;
    }

    if (reminder.repeat == 'yearly') {
      for (var delta = 0; delta <= 1; delta++) {
        final year = now.year + delta;
        final candidate = DateTime(
          year,
          reminder.scheduleMonth,
          reminder.scheduleDay,
        );
        if (candidate.month == reminder.scheduleMonth &&
            candidate.day == reminder.scheduleDay) {
          yield candidate;
        }
      }
    }
  }

  int _slotFor(String id, List<ReminderConfig> configs) {
    switch (id) {
      case 'morning':
        return 0;
      case 'evening':
        return 1;
      case 'kahf':
        return 2;
      case 'dua':
        return 3;
      case 'fajr':
        return 4;
      case 'sunrise':
        return 5;
      case 'dhuhr':
        return 6;
      case 'asr':
        return 7;
      case 'maghrib':
        return 8;
      case 'isha':
        return 9;
      default:
        final idx = configs.indexWhere((c) => c.id == id);
        return 10 + (idx >= 0 ? idx : 0);
    }
  }

  _NotifText _getNotificationText(String lang, ReminderConfig rc) {
    if (rc.id == 'morning') {
      return _windowText(lang, TaskId.morning, opening: true);
    }
    if (rc.id == 'evening') {
      return _windowText(lang, TaskId.evening, opening: true);
    }
    if (rc.id == 'kahf') return _windowText(lang, TaskId.kahf, opening: true);
    if (rc.id == 'dua') return _windowText(lang, TaskId.dua, opening: true);

    final isBuiltInPrayer = [
      'fajr',
      'sunrise',
      'dhuhr',
      'asr',
      'maghrib',
      'isha',
    ].contains(rc.id);
    if (isBuiltInPrayer && rc.offsetMin == 0) {
      return _prayerText(lang, Prayer.values[rc.prayer]);
    }

    return _NotifText(rc.title, _customBody(lang, rc));
  }

  Future<void> _schedule0(
    int id,
    DateTime local,
    _NotifText txt,
    String payload,
    NotificationDetails details,
  ) async {
    final when = tz.TZDateTime.from(local, tz.local);
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: when,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: txt.title,
      body: txt.body,
      payload: payload,
    );
  }

  String _payload(String id, String task, DateTime date, _NotifText txt) =>
      NotificationPayload(
        open: notificationTargetFor(id),
        task: task,
        date: _dayKey(date),
        title: txt.title,
        body: txt.body,
      ).encode();

  DateTime _at(DateTime date, int minutes) =>
      DateTime(date.year, date.month, date.day).add(Duration(minutes: minutes));

  int _id(int day, int slot) => day * 100 + slot;

  _NotifText _windowText(String lang, TaskId id, {required bool opening}) {
    final kz = lang == 'kz';
    switch (id) {
      case TaskId.morning:
        return opening
            ? _NotifText(
                kz ? 'Таңғы зікірлер' : 'Утренние зикры',
                kz
                    ? 'Алланы еске алуға бірнеше минут бөліңіз.'
                    : 'Найдите несколько минут для поминания Аллаха.',
              )
            : _NotifText(
                kz ? 'Таңғы зікірлер' : 'Утренние зикры',
                kz ? 'Күн шығуына 30 минут қалды.' : 'До восхода 30 минут.',
              );
      case TaskId.evening:
        return opening
            ? _NotifText(
                kz ? 'Кешкі зікірлер' : 'Вечерние зикры',
                kz
                    ? 'Алланы еске алуға бірнеше минут бөліңіз.'
                    : 'Найдите несколько минут для поминания Аллаха.',
              )
            : _NotifText(
                kz ? 'Кешкі зікірлер' : 'Вечерние зикры',
                kz ? 'Ақшамға 30 минут қалды.' : 'До Магриба 30 минут.',
              );
      case TaskId.kahf:
        return _NotifText(
          kz ? '«әл-Кәһф» сүресі' : 'Сура аль-Кахф',
          kz ? 'Сүрені оқуға уақыт бөліңіз.' : 'Найдите время прочитать суру.',
        );
      case TaskId.dua:
        return _NotifText(
          kz ? 'Дұға сағаты' : 'Час дуа',
          kz
              ? 'Аллаға жеке дұға жасауға уақыт бөліңіз.'
              : 'Найдите время обратиться к Аллаху с личной мольбой.',
        );
    }
  }

  String _customBody(String lang, ReminderConfig r) {
    final kz = lang == 'kz';
    if (!r.isPrayerLinked) {
      final time =
          '${r.fixedHour.toString().padLeft(2, '0')}:${r.fixedMinute.toString().padLeft(2, '0')}';
      return kz ? 'Белгіленген уақыт: $time' : 'В указанное время: $time';
    }
    final names = kz
        ? ['Таң', 'Күн шығуы', 'Бесін', 'Екінті', 'Ақшам', 'Құптан']
        : ['Фаджр', 'Восход', 'Зухр', 'Аср', 'Магриб', 'Иша'];
    final n = names[r.prayer];
    final m = r.offsetMin.abs();
    if (r.offsetMin == 0) return kz ? '$n уақыты' : 'Время: $n';
    if (r.offsetMin < 0) {
      return kz ? '$n уақытына $m мин қалды' : 'До $n — $m мин';
    }
    return kz ? '$n кейін $m мин өтті' : '$m мин после $n';
  }

  _NotifText _prayerText(String lang, Prayer p) {
    final copy = prayerNotificationCopy(lang, p);
    return _NotifText(copy.title, copy.body);
  }
}
