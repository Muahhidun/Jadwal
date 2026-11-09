import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jadwal/notifications/notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('кнопки есть только у дел, не у времени намаза', () {
    expect(notificationTaskFor('morning'), 'morning');
    expect(notificationTaskFor('kahf'), 'kahf');
    expect(notificationTaskFor('dua'), 'dua');
    expect(notificationTaskFor('abc123'), 'custom:abc123');
    for (final prayer in [
      'fajr',
      'sunrise',
      'dhuhr',
      'asr',
      'maghrib',
      'isha',
    ]) {
      expect(notificationTaskFor(prayer), isEmpty);
    }
  });

  test('данные уведомления переживают кодирование', () {
    const payload = NotificationPayload(
      open: 'evening',
      task: 'evening',
      date: '2026-9-29',
      title: 'Вечерние зикры',
      body: 'Найдите несколько минут',
    );
    final back = NotificationPayload.parse(payload.encode());
    expect(back.open, 'evening');
    expect(back.task, 'evening');
    expect(back.date, '2026-9-29');
    expect(back.title, 'Вечерние зикры');
  });

  test('старые уведомления без кнопок по-прежнему открывают чтение', () {
    expect(NotificationPayload.parse('kahf').open, 'kahf');
    expect(NotificationPayload.parse('kahf').task, isEmpty);
    expect(NotificationPayload.parse('').open, isEmpty);
    expect(NotificationPayload.parse('{битый').open, isEmpty);
  });

  test('«Выполнено» отмечает дело за день уведомления', () async {
    SharedPreferences.setMockInitialValues({});
    const payload = NotificationPayload(
      open: 'morning',
      task: 'morning',
      date: '2026-9-29',
    );
    await applyNotificationAction(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: kActionDone,
        payload: payload.encode(),
      ),
      FlutterLocalNotificationsPlugin(),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('done:2026-9-29'), ['morning']);
  });

  test('уведомление о намазе не отмечает ничего', () async {
    SharedPreferences.setMockInitialValues({});
    await applyNotificationAction(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: kActionDone,
        payload: const NotificationPayload(date: '2026-9-29').encode(),
      ),
      FlutterLocalNotificationsPlugin(),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });
}
