import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../i18n/strings.dart';
import '../prayer/schedule.dart';
import '../prayer/schedule_service.dart';

/// Передаёт WidgetKit компактный снимок локальных данных Dauam.
///
/// Виджет живёт в отдельном процессе и не может читать Flutter
/// `SharedPreferences`. На iOS снимок сохраняется в общей App Group, после
/// чего WidgetKit получает команду перестроить timelines.
class WidgetDataService {
  static const MethodChannel _channel = MethodChannel('kz.dauam/widgets');

  static Future<bool> sync({
    required AppState app,
    required ScheduleService schedule,
    required S strings,
    required DayTimes today,
    required DateTime now,
    required String dateLabel,
  }) async {
    final tomorrowDate = DateTime(now.year, now.month, now.day + 1);
    final tomorrow = schedule.timesFor(app.city, tomorrowDate);
    if (tomorrow == null) return false;

    DateTime timestampFor(DayTimes day, Prayer prayer) {
      final minutes = day.times[prayer]!;
      return DateTime(
        day.date.year,
        day.date.month,
        day.date.day,
        minutes ~/ 60,
        minutes % 60,
      );
    }

    Map<String, Object> prayerJson(
      DayTimes day,
      Prayer prayer, {
      required bool isTomorrow,
    }) => {
      'id': prayer.name,
      'title': strings.prayers[prayer.index],
      'time': day.fmt(prayer),
      'timestamp': timestampFor(day, prayer).millisecondsSinceEpoch / 1000.0,
      'isTomorrow': isTomorrow,
    };

    final prayerPoints = <Map<String, Object>>[
      for (final prayer in Prayer.values)
        prayerJson(today, prayer, isTomorrow: false),
      for (final prayer in Prayer.values)
        prayerJson(tomorrow, prayer, isTomorrow: true),
    ];

    final tasks = <Map<String, Object>>[
      {
        'id': 'morning',
        'title': strings.morningTitle.replaceAll('\u00a0', ' '),
        'done': app.isDone('morning'),
      },
      if (today.isFriday)
        {
          'id': 'kahf',
          'title': strings.kahfTitle.replaceAll('\u00a0', ' '),
          'done': app.isDone('kahf'),
        },
      {
        'id': 'evening',
        'title': strings.eveningTitle.replaceAll('\u00a0', ' '),
        'done': app.isDone('evening'),
      },
      if (today.isFriday)
        {
          'id': 'dua',
          'title': strings.duaTitle.replaceAll('\u00a0', ' '),
          'done': app.isDone('dua'),
        },
      for (final reminder in app.customReminders.where(
        (item) => app.reminderOccursOn(item, today.date),
      ))
        {
          'id': 'custom:${reminder.id}',
          'title': reminder.title,
          'done': app.isDone('custom:${reminder.id}'),
        },
    ];

    final (doneCount, totalCount) = app.taskProgressOn(today.date);
    final payload = <String, Object>{
      'schemaVersion': 1,
      'generatedAt': now.millisecondsSinceEpoch / 1000.0,
      'language': app.lang,
      'city': app.city.name,
      'dateLabel': dateLabel,
      'prayers': prayerPoints,
      'tasks': tasks,
      'taskDone': doneCount,
      'taskTotal': totalCount,
    };

    try {
      await _channel.invokeMethod<void>('saveSnapshot', jsonEncode(payload));
      return true;
    } on MissingPluginException {
      // Android и widget-тесты не имеют iOS-плагина.
      return false;
    } on PlatformException {
      // Виджеты не должны влиять на основной экран, даже если App Group
      // временно недоступна (например, до обновления provisioning profile).
      return false;
    }
  }
}
