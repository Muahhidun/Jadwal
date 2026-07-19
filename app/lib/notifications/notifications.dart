import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/app_state.dart';
import '../prayer/city.dart';
import '../prayer/schedule.dart';
import '../prayer/schedule_service.dart';
import '../prayer/windows.dart';

/// Глобальный сервис уведомлений (создаётся в main; null в тестах).
NotificationService? gNotifier;

/// Перепланировать очередь из текущего состояния приложения.
Future<void> syncNotifications(AppState app, ScheduleService schedule) async {
  final now = schedule.now();
  // Асинхронно ожидаем загрузку данных ДУМК из кэша/сети, чтобы время не расходилось с Sajda.kz!
  await schedule.ensureLoaded(app.city, now.year);
  if (now.month == 12 && now.day >= 18) {
    await schedule.ensureLoaded(app.city, now.year + 1);
  }

  final ids = ['morning', 'evening', 'kahf', 'dua', 'fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];
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
        if (app.isDone(id.name)) id
    },
  );
}

/// Локализованные тексты уведомлений (ru/kz).
class _NotifText {
  final String title, body;
  const _NotifText(this.title, this.body);
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

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Almaty'));
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onTap,
    );
    // Уведомление, из которого приложение было запущено (холодный старт).
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if (payload != null && payload.isNotEmpty) pendingCollection = payload;
  }

  void _onTap(NotificationResponse r) {
    if ((r.payload ?? '').isNotEmpty) pendingCollection = r.payload;
  }

  /// Запросить разрешение на уведомления (iOS/Android 13+).
  Future<bool> requestPermission() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails('jadwal_worship', 'Поклонение',
            channelDescription: 'Напоминания об окнах зикра и намазах',
            importance: Importance.high,
            priority: Priority.high),
        iOS: DarwinNotificationDetails(),
      );

  /// Перепланировать всю очередь. Вызывать при старте, смене города/настроек
  /// и при отметке «выполнено» ([doneToday] — какие задачи уже выполнены сегодня).
  Future<void> reschedule({
    required String lang,
    required City city,
    required List<ReminderConfig> configs,
    required Set<TaskId> doneToday,
  }) async {
    await _plugin.cancelAll();
    final now = _schedule.now();
    int count = 0;
    final details = _details();

    for (var d = 0; d < _daysAhead && count < _cap; d++) {
      final date = DateTime(now.year, now.month, now.day + d);
      final t = _schedule.timesFor(city, date);
      if (t == null) continue;
      final isToday = d == 0;

      for (final rc in configs) {
        if (!rc.enabled) continue;

        // Фильтр по частоте повторения
        if (rc.repeat == 'weekly') {
          if (rc.id == 'kahf' || rc.id == 'dua') {
            if (date.weekday != DateTime.friday) continue;
          } else {
            if (date.weekday != rc.weekday) continue;
          }
        } else if (rc.repeat == 'monthly') {
          if (date.day != 1) continue;
        }

        // Проверяем, выполнено ли сегодня
        if (isToday) {
          if (rc.id == 'morning' && doneToday.contains(TaskId.morning)) continue;
          if (rc.id == 'evening' && doneToday.contains(TaskId.evening)) continue;
          if (rc.id == 'kahf' && doneToday.contains(TaskId.kahf)) continue;
          if (rc.id == 'dua' && doneToday.contains(TaskId.dua)) continue;
        }

        final basePrayer = Prayer.values[rc.prayer];
        final baseTime = t.times[basePrayer];
        if (baseTime == null) continue;

        final scheduledTime = _at(date, baseTime + rc.offsetMin);
        if (!scheduledTime.isAfter(now)) continue;

        if (count >= _cap) break;

        final txt = _getNotificationText(lang, rc);
        final payload = rc.id == 'morning' || rc.id == 'evening' ? rc.id : '';

        final slot = _slotFor(rc.id, configs);
        await _schedule0(_id(d, slot), scheduledTime, txt, payload, details);
        count++;

        // Дополнительное напоминание перед завершением утреннего/вечернего окна (за 30 минут)
        if ((rc.id == 'morning' || rc.id == 'evening') && rc.offsetMin == 0) {
          final endPrayer = rc.id == 'morning' ? Prayer.sunrise : Prayer.maghrib;
          final endTime = t.times[endPrayer];
          if (endTime != null) {
            final remindAt = _at(date, endTime - _reminderBeforeEndMin);
            if (remindAt.isAfter(now) && remindAt.isAfter(scheduledTime) && count < _cap) {
              final rTxt = _windowText(lang, rc.id == 'morning' ? TaskId.morning : TaskId.evening, opening: false);
              await _schedule0(_id(d, slot + 20), remindAt, rTxt, payload, details);
              count++;
            }
          }
        }
      }
    }
  }

  int _slotFor(String id, List<ReminderConfig> configs) {
    switch (id) {
      case 'morning': return 0;
      case 'evening': return 1;
      case 'kahf': return 2;
      case 'dua': return 3;
      case 'fajr': return 4;
      case 'sunrise': return 5;
      case 'dhuhr': return 6;
      case 'asr': return 7;
      case 'maghrib': return 8;
      case 'isha': return 9;
      default:
        final idx = configs.indexWhere((c) => c.id == id);
        return 10 + (idx >= 0 ? idx : 0);
    }
  }

  _NotifText _getNotificationText(String lang, ReminderConfig rc) {
    if (rc.id == 'morning') return _windowText(lang, TaskId.morning, opening: true);
    if (rc.id == 'evening') return _windowText(lang, TaskId.evening, opening: true);
    if (rc.id == 'kahf') return _windowText(lang, TaskId.kahf, opening: true);
    if (rc.id == 'dua') return _windowText(lang, TaskId.dua, opening: true);

    final isBuiltInPrayer = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'].contains(rc.id);
    if (isBuiltInPrayer && rc.offsetMin == 0) {
      return _prayerText(lang, Prayer.values[rc.prayer]);
    }

    return _NotifText(rc.title, _customBody(lang, rc));
  }

  Future<void> _schedule0(int id, DateTime local, _NotifText txt, String payload,
      NotificationDetails details) async {
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

  DateTime _at(DateTime date, int minutes) =>
      DateTime(date.year, date.month, date.day).add(Duration(minutes: minutes));

  int _id(int day, int slot) => day * 100 + slot;



  _NotifText _windowText(String lang, TaskId id, {required bool opening}) {
    final kz = lang == 'kz';
    switch (id) {
      case TaskId.morning:
        return opening
            ? _NotifText(kz ? 'Таңғы зікірлер' : 'Утренние зикры',
                kz ? 'Уақыт ашылды: таңнан кейін, күн шыққанға дейін.' : 'Окно открыто: после Фаджра, до восхода солнца.')
            : _NotifText(kz ? 'Таңғы зікірлерді ұмытпаңыз' : 'Не забудьте утренние зикры',
                kz ? 'Күн шығуына аз қалды.' : 'Скоро восход — успейте прочитать.');
      case TaskId.evening:
        return opening
            ? _NotifText(kz ? 'Кешкі зікірлер' : 'Вечерние зикры',
                kz ? 'Уақыт ашылды: екінтіден кейін, күн батқанға дейін.' : 'Окно открыто: после Асра, до захода солнца.')
            : _NotifText(kz ? 'Кешкі зікірлерді ұмытпаңыз' : 'Не забудьте вечерние зикры',
                kz ? 'Ақшамға аз қалды.' : 'Скоро Магриб — успейте прочитать.');
      case TaskId.kahf:
        return _NotifText(kz ? '«әл-Кәһф» сүресі' : 'Сура аль-Кахф',
            kz ? 'Жұма — жұма намазына дейін «әл-Кәһф» сүресін оқу уақыты.' : 'Пятница — время прочитать суру аль-Кахф до Джума.');
      case TaskId.dua:
        return _NotifText(kz ? 'Дұға сағаты' : 'Час дуа',
            kz ? 'Жұма — Ақшам алдындағы дұға қабыл болатын сағат.' : 'Пятница — час принятия дуа перед Магрибом.');
    }
  }

  String _customBody(String lang, ReminderConfig r) {
    final kz = lang == 'kz';
    final names = kz
        ? ['Таң', 'Күн шығуы', 'Бесін', 'Екінті', 'Ақшам', 'Құптан']
        : ['Фаджр', 'Восход', 'Зухр', 'Аср', 'Магриб', 'Иша'];
    final n = names[r.prayer];
    final m = r.offsetMin.abs();
    if (r.offsetMin == 0) return kz ? '$n уақыты' : 'Время: $n';
    if (r.offsetMin < 0) return kz ? '$n уақытына $m мин қалды' : 'До $n — $m мин';
    return kz ? '$n кейін $m мин өтті' : '$m мин после $n';
  }

  _NotifText _prayerText(String lang, Prayer p) {
    final kz = lang == 'kz';
    final names = kz
        ? ['Таң', 'Күн шығуы', 'Бесін', 'Екінті', 'Ақшам', 'Құптан']
        : ['Фаджр', 'Восход', 'Зухр', 'Аср', 'Магриб', 'Иша'];
    final name = names[p.index];
    return _NotifText(name, kz ? '$name намазының уақыты кірді' : 'Наступило время намаза $name');
  }
}
