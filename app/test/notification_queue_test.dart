import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/notifications/notifications.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule_service.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

ReminderConfig _personal(
  String id, {
  String repeat = 'daily',
  DateTime? date,
}) => ReminderConfig(
  id: id,
  title: id,
  prayer: 0,
  offsetMin: 0,
  anchor: 'clock',
  fixedHour: 12,
  repeat: repeat,
  scheduleYear: date?.year ?? 0,
  scheduleMonth: date?.month ?? 1,
  scheduleDay: date?.day ?? 1,
);

Future<ScheduleService> _schedule(DateTime now) async {
  final service = ScheduleService(
    await SharedPreferences.getInstance(),
    now: () => now,
  );
  final dates = [
    for (var d = 0; d < 14; d++) DateTime(now.year, now.month, now.day + d),
  ];
  for (final year in dates.map((date) => date.year).toSet()) {
    service.preload(kDefaultCity, year, {
      for (final date in dates.where((date) => date.year == year))
        date.toIso8601String().substring(0, 10): [
          300,
          420,
          780,
          1020,
          1140,
          1260,
        ],
    });
  }
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final events = <Map<String, dynamic>>[];
  final pending = <int, Map<String, dynamic>>{};
  Future<void> Function(Map<String, dynamic>)? beforeSchedule;
  // Native plugin validation uses the real clock. Keep every generated event
  // in the future while the scheduler's injected clock starts before Fajr.
  final actual = DateTime.now();
  final now = DateTime(actual.year, actual.month, actual.day + 1, 0, 1);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
    events.clear();
    pending.clear();
    beforeSchedule = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'cancelAll') pending.clear();
          if (call.method == 'cancel') {
            pending.remove((call.arguments as Map)['id']);
          }
          if (call.method == 'pendingNotificationRequests') {
            return pending.values.toList();
          }
          if (call.method == 'zonedSchedule') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            await beforeSchedule?.call(args);
            events.add(args);
            pending[args['id'] as int] = args;
          }
          return null;
        });
  });
  tearDown(() {
    gNotifier = null;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test(
    'personal reminders and both window follow-ups have distinct IDs',
    () async {
      final app = await AppState.load();
      app.addReminder(_personal('personal-a'));
      app.addReminder(_personal('personal-b'));
      final schedule = await _schedule(now);
      gNotifier = NotificationService(schedule);
      await syncNotifications(app, schedule);

      expect(events, hasLength(58));
      expect(
        events.map((event) => event['id']).toSet(),
        hasLength(events.length),
      );
      final today = pending.values
          .map((event) => NotificationPayload.parse(event['payload'] as String))
          .where((payload) => payload.date == AppState.dayKey(now))
          .toList();
      expect(today.where((payload) => payload.task == 'morning'), hasLength(2));
      expect(today.where((payload) => payload.task == 'evening'), hasLength(2));
      expect(
        today.where((payload) => payload.task == 'custom:personal-a'),
        hasLength(1),
      );
      expect(
        today.where((payload) => payload.task == 'custom:personal-b'),
        hasLength(1),
      );
    },
  );

  for (final repeat in ['daily', 'once', 'monthly', 'yearly']) {
    test(
      'completed $repeat personal reminder is not scheduled again today',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('done:${AppState.dayKey(now)}', [
          'custom:personal',
        ]);
        final app = await AppState.load();
        app.addReminder(_personal('personal', repeat: repeat, date: now));
        gNotifier = NotificationService(await _schedule(now));
        await syncNotifications(app, await _schedule(now));

        final tasks = pending.values
            .map(
              (event) => NotificationPayload.parse(event['payload'] as String),
            )
            .where((payload) => payload.task == 'custom:personal')
            .toList();
        expect(
          tasks.where((payload) => payload.date == AppState.dayKey(now)),
          isEmpty,
        );
        if (repeat == 'daily') {
          expect(
            tasks.any((payload) => payload.date != AppState.dayKey(now)),
            isTrue,
          );
        }
        if (repeat == 'once') expect(tasks, isEmpty);
      },
    );
  }

  test(
    'completed task removes its saved snooze but preserves another day',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('done:${AppState.dayKey(now)}', [
        'custom:personal',
      ]);
      final at = DateTime.now().add(const Duration(hours: 1));
      await prefs.setString(
        'notif:snoozes',
        jsonEncode([
          for (final (id, date) in [
            (950001, AppState.dayKey(now)),
            (950002, AppState.dayKey(now.add(const Duration(days: 1)))),
          ])
            {
              'id': id,
              'at': at.millisecondsSinceEpoch,
              'p': NotificationPayload(
                task: 'custom:personal',
                date: date,
              ).encode(),
            },
        ]),
      );
      final app = await AppState.load();
      final schedule = await _schedule(now);
      gNotifier = NotificationService(schedule);
      await syncNotifications(app, schedule);

      expect(pending.containsKey(950001), isFalse);
      expect(pending.containsKey(950002), isTrue);
      final saved = jsonDecode(prefs.getString('notif:snoozes')!) as List;
      expect(saved, hasLength(1));
    },
  );

  test('a scheduling failure does not block the next reschedule', () async {
    final service = NotificationService(await _schedule(now));
    beforeSchedule = (_) async => throw PlatformException(code: 'test-error');
    await expectLater(
      service.reschedule(
        lang: 'ru',
        city: kDefaultCity,
        configs: [_personal('failed')],
        doneToday: {},
      ),
      throwsA(isA<PlatformException>()),
    );
    beforeSchedule = null;
    await service.reschedule(
      lang: 'ru',
      city: kDefaultCity,
      configs: [_personal('recovered')],
      doneToday: {},
    );
    expect(pending, isNotEmpty);
    expect(
      pending.values.every(
        (event) =>
            NotificationPayload.parse(event['payload'] as String).task ==
            'custom:recovered',
      ),
      isTrue,
    );
  });

  test('completing a notification preserves snoozes for another day', () async {
    final prefs = await SharedPreferences.getInstance();
    final at = DateTime.now().add(const Duration(hours: 1));
    final days = [
      AppState.dayKey(now),
      AppState.dayKey(now.add(const Duration(days: 1))),
    ];
    await prefs.setString(
      'notif:snoozes',
      jsonEncode([
        for (final (index, day) in days.indexed)
          {
            'id': 950001 + index,
            'at': at.millisecondsSinceEpoch,
            'p': NotificationPayload(
              task: 'custom:personal',
              date: day,
            ).encode(),
          },
      ]),
    );
    for (final (index, day) in days.indexed) {
      pending[950001 + index] = {
        'id': 950001 + index,
        'title': 'Дело',
        'body': '',
        'payload': NotificationPayload(
          task: 'custom:personal',
          date: day,
        ).encode(),
      };
    }
    await applyNotificationAction(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: kActionDone,
        payload: NotificationPayload(
          task: 'custom:personal',
          date: days.first,
        ).encode(),
      ),
      FlutterLocalNotificationsPlugin(),
    );
    expect(prefs.getStringList('done:${days.first}'), ['custom:personal']);
    expect(prefs.getStringList('done:${days.last}'), isNull);
    expect(pending.keys, [950002]);
    final saved = (jsonDecode(prefs.getString('notif:snoozes')!) as List);
    expect(saved, hasLength(1));
    expect((saved.single as Map)['id'], 950002);
  });

  test('overlapping reschedules leave only the last requested queue', () async {
    final service = NotificationService(await _schedule(now));
    final entered = Completer<void>();
    final release = Completer<void>();
    var blocked = false;
    beforeSchedule = (_) async {
      if (blocked) return;
      blocked = true;
      entered.complete();
      await release.future;
    };
    final first = service.reschedule(
      lang: 'ru',
      city: kDefaultCity,
      configs: [_personal('old')],
      doneToday: {},
    );
    await entered.future;
    final second = service.reschedule(
      lang: 'ru',
      city: kDefaultCity,
      configs: [_personal('new')],
      doneToday: {},
    );
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await Future.wait([first, second]);

    expect(pending, isNotEmpty);
    expect(
      pending.values.every(
        (event) =>
            NotificationPayload.parse(event['payload'] as String).task ==
            'custom:new',
      ),
      isTrue,
    );
  });
}
