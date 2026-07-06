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
Future<void> syncNotifications(AppState app) async {
  await gNotifier?.reschedule(
    lang: app.lang,
    city: app.city,
    settings: const NotifSettings(),
    doneToday: {
      for (final id in TaskId.values)
        if (app.isDone(id.name)) id
    },
  );
}

/// Настройки уведомлений (какие включены). По умолчанию всё включено —
/// 4 окна поклонения + оповещение о намазах (решение владельца).
class NotifSettings {
  final bool morning, evening, kahf, dua, prayers;
  const NotifSettings({
    this.morning = true,
    this.evening = true,
    this.kahf = true,
    this.dua = true,
    this.prayers = true,
  });
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
    required NotifSettings settings,
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

      // Окна поклонения: уведомление в начале + напоминание перед концом.
      for (final w in windowsFor(t)) {
        if (!_windowEnabled(w.id, settings)) continue;
        if (isToday && doneToday.contains(w.id)) continue; // выполнено — молчим
        final startAt = _at(date, w.start);
        final remindAt = _at(date, w.end - _reminderBeforeEndMin);
        final txt = _windowText(lang, w.id, opening: true);
        final rTxt = _windowText(lang, w.id, opening: false);
        final payload = _payloadFor(w.id);
        if (startAt.isAfter(now) && count < _cap) {
          await _schedule0(_id(d, w.id.index), startAt, txt, payload, details);
          count++;
        }
        if (remindAt.isAfter(now) && remindAt.isAfter(startAt) && count < _cap) {
          await _schedule0(_id(d, w.id.index + 20), remindAt, rTxt, payload, details);
          count++;
        }
      }

      // Оповещение о намазах (5 обязательных, без восхода).
      if (settings.prayers) {
        const prayers = [
          Prayer.fajr,
          Prayer.dhuhr,
          Prayer.asr,
          Prayer.maghrib,
          Prayer.isha
        ];
        for (final (i, p) in prayers.indexed) {
          if (count >= _cap) break;
          final at = _at(date, t.times[p]!);
          if (!at.isAfter(now)) continue;
          final txt = _prayerText(lang, p);
          await _schedule0(_id(d, 40 + i), at, txt, '', details);
          count++;
        }
      }
    }
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

  bool _windowEnabled(TaskId id, NotifSettings s) => switch (id) {
        TaskId.morning => s.morning,
        TaskId.evening => s.evening,
        TaskId.kahf => s.kahf,
        TaskId.dua => s.dua,
      };

  String _payloadFor(TaskId id) => switch (id) {
        TaskId.morning => 'morning',
        TaskId.evening => 'evening',
        _ => '',
      };

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

  _NotifText _prayerText(String lang, Prayer p) {
    final kz = lang == 'kz';
    final names = kz
        ? ['Таң', 'Күн шығуы', 'Бесін', 'Екінті', 'Ақшам', 'Құптан']
        : ['Фаджр', 'Восход', 'Зухр', 'Аср', 'Магриб', 'Иша'];
    final name = names[p.index];
    return _NotifText(name, kz ? '$name намазының уақыты кірді' : 'Наступило время намаза $name');
  }
}
