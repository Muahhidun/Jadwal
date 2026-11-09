import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/main.dart';
import 'package:jadwal/notifications/notifications.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule_service.dart';

class _RefreshableSchedule extends ScheduleService {
  _RefreshableSchedule(super.prefs, DateTime Function() clock)
    : super(now: clock);

  void publish(City city, DateTime day, {int fajr = 300}) {
    preload(city, day.year, {
      for (var offset = 0; offset < 14; offset++)
        DateTime(
          day.year,
          day.month,
          day.day + offset,
        ).toIso8601String().substring(0, 10): [
          fajr,
          420,
          780,
          1020,
          1140,
          1260,
        ],
    });
    notifyListeners();
  }
}

class _RecordingNotifications extends NotificationService {
  _RecordingNotifications(super.schedule);
  final calls = <({City city, Set<String> done, String sound})>[];

  @override
  Future<void> reschedule({
    required String lang,
    required City city,
    required List<ReminderConfig> configs,
    required Set<String> doneToday,
    String prayerSound = 'default',
    String taskSound = 'default',
  }) async {
    calls.add((city: city, done: Set.of(doneToday), sound: taskSound));
  }
}

Future<void> _tick(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  tearDown(() => gNotifier = null);

  Future<
    ({
      AppState app,
      _RefreshableSchedule schedule,
      _RecordingNotifications notifications,
    })
  >
  start(WidgetTester tester, DateTime Function() clock) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'pagesDiscoveryV1Seen': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final app = await AppState.load();
    final schedule = _RefreshableSchedule(prefs, clock);
    schedule.publish(app.city, clock());
    final notifications = _RecordingNotifications(schedule);
    gNotifier = notifications;
    await tester.pumpWidget(JadwalApp(state: app, schedule: schedule));
    await _tick(tester);
    return (app: app, schedule: schedule, notifications: notifications);
  }

  testWidgets('personal completion and unchecking refresh notifications', (
    tester,
  ) async {
    final state = await start(tester, DateTime.now);
    final initial = state.notifications.calls.length;
    state.app.markDone('custom:personal');
    await _tick(tester);
    expect(state.notifications.calls.length, greaterThan(initial));
    expect(state.notifications.calls.last.done, contains('custom:personal'));
    final marked = state.notifications.calls.length;
    state.app.toggleDone('custom:personal');
    await _tick(tester);
    expect(state.notifications.calls.length, greaterThan(marked));
    expect(
      state.notifications.calls.last.done,
      isNot(contains('custom:personal')),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new prayer data refreshes notifications without changing city', (
    tester,
  ) async {
    final state = await start(tester, DateTime.now);
    final initial = state.notifications.calls.length;
    state.schedule.publish(state.app.city, DateTime.now(), fajr: 342);
    await _tick(tester);
    expect(state.notifications.calls.length, greaterThan(initial));
    final refreshed = state.notifications.calls.length;
    await _tick(tester);
    expect(state.notifications.calls.length, refreshed);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('midnight refreshes the queue even without completion changes', (
    tester,
  ) async {
    var at = DateTime.now();
    final state = await start(tester, () => at);
    final initial = state.notifications.calls.length;
    at = at.add(const Duration(days: 1));
    await _tick(tester);
    expect(state.notifications.calls.length, greaterThan(initial));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'coordinates and sounds refresh the queue, reader palette does not',
    (tester) async {
      final state = await start(tester, DateTime.now);
      final initial = state.notifications.calls.length;
      final city = City(state.app.city.name, '51.1694', '71.4491');
      state.schedule.publish(city, DateTime.now());
      state.app.setCity(city);
      await _tick(tester);
      expect(state.notifications.calls.length, greaterThan(initial));
      expect(state.notifications.calls.last.city.latStr, city.latStr);
      final moved = state.notifications.calls.length;
      state.app.taskSound = 'bell';
      await _tick(tester);
      expect(state.notifications.calls.length, greaterThan(moved));
      expect(state.notifications.calls.last.sound, 'bell');
      final configured = state.notifications.calls.length;
      state.app.readerPalette = 'night';
      await _tick(tester);
      expect(state.notifications.calls.length, configured);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
