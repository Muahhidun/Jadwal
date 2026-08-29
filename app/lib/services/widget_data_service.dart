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
  static const int scheduleLookaheadDays = 14;

  static Future<bool> sync({
    required AppState app,
    required ScheduleService schedule,
    required S strings,
    required DayTimes today,
    required DateTime now,
    required String dateLabel,
  }) async {
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

    final scheduleDays = <DayTimes>[today];
    for (var offset = 1; offset < scheduleLookaheadDays; offset++) {
      final date = DateTime(now.year, now.month, now.day + offset);
      final day = schedule.timesFor(app.city, date);
      if (day != null) scheduleDays.add(day);
    }

    final prayerPoints = <Map<String, Object>>[
      for (var dayIndex = 0; dayIndex < scheduleDays.length; dayIndex++)
        for (final prayer in Prayer.values)
          prayerJson(scheduleDays[dayIndex], prayer, isTomorrow: dayIndex > 0),
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
      'schemaVersion': 2,
      'generatedAt': now.millisecondsSinceEpoch / 1000.0,
      'language': app.lang,
      'city': app.city.displayName(app.lang),
      'dateLabel': dateLabel,
      'prayers': prayerPoints,
      'scheduleDays': scheduleDays.length,
      'tasks': tasks,
      'taskDone': doneCount,
      'taskTotal': totalCount,
      // Координаты города — для экрана Киблы на часах.
      'lat': double.tryParse(app.city.latStr) ?? 0,
      'lng': double.tryParse(app.city.lngStr) ?? 0,
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
