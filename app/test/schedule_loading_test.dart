import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule.dart';
import 'package:jadwal/prayer/schedule_service.dart';

http.Response _reply(String date, String fajr) => http.Response(
  jsonEncode({
    'result': [
      {
        'Date': date,
        'fajr': fajr,
        'sunrise': '07:00',
        'dhuhr': '13:00',
        'asr': '16:00',
        'maghrib': '18:00',
        'isha': '20:00',
      },
    ],
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'ensureLoaded waits for the request already started by timesFor',
    () async {
      final response = Completer<http.Response>();
      final entered = Completer<void>();
      var requests = 0;
      await http.runWithClient(
        () async {
          final service = ScheduleService(
            await SharedPreferences.getInstance(),
          );
          service.timesFor(kDefaultCity, DateTime(2026, 10, 21));
          await entered.future;
          var finished = false;
          final waiting = service
              .ensureLoaded(kDefaultCity, 2026)
              .then((_) => finished = true);
          await Future<void>.delayed(Duration.zero);
          final returnedBeforeResponse = finished;
          response.complete(_reply('2026-10-21', '05:12'));
          await waiting;

          expect(returnedBeforeResponse, isFalse);
          expect(requests, 1);
          expect(
            service
                .timesFor(kDefaultCity, DateTime(2026, 10, 21))!
                .times[Prayer.fajr],
            312,
          );
        },
        () => MockClient((_) {
          requests++;
          if (!entered.isCompleted) entered.complete();
          return response.future;
        }),
      );
    },
  );

  test('a city change during loading gets its own complete schedule', () async {
    const other = City('Другой город', '51.1694', '71.4491');
    final first = Completer<http.Response>();
    final second = Completer<http.Response>();
    final requested = <String>[];
    await http.runWithClient(
      () async {
        final service = ScheduleService(await SharedPreferences.getInstance());
        final a = service.ensureLoaded(kDefaultCity, 2026);
        final b = service.ensureLoaded(other, 2026);
        await Future<void>.delayed(Duration.zero);
        first.complete(_reply('2026-10-21', '05:12'));
        second.complete(_reply('2026-10-21', '06:34'));
        await Future.wait([a, b]);

        final aTime = service
            .timesFor(kDefaultCity, DateTime(2026, 10, 21))!
            .times[Prayer.fajr];
        final bTime = service
            .timesFor(other, DateTime(2026, 10, 21))!
            .times[Prayer.fajr];
        expect(requested, hasLength(2));
        expect(aTime, 312);
        expect(bTime, 394);
      },
      () => MockClient((request) {
        requested.add(request.url.path);
        return request.url.path.contains(other.latStr)
            ? second.future
            : first.future;
      }),
    );
  });

  test(
    'the year boundary keeps both cached schedules without republishing them',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final ck = ScheduleService.cityKey(kDefaultCity);
      await prefs.setString(
        'pt:$ck:2026',
        jsonEncode({
          '2026-12-31': [300, 420, 780, 960, 1080, 1200],
        }),
      );
      await prefs.setString(
        'pt:$ck:2027',
        jsonEncode({
          '2027-01-01': [301, 421, 781, 961, 1081, 1201],
        }),
      );
      final service = ScheduleService(prefs);
      var updates = 0;
      service.addListener(() => updates++);
      await service.ensureLoaded(kDefaultCity, 2026);
      await service.ensureLoaded(kDefaultCity, 2027);
      for (var i = 0; i < 3; i++) {
        expect(
          service
              .timesFor(kDefaultCity, DateTime(2026, 12, 31))!
              .times[Prayer.fajr],
          300,
        );
        expect(
          service
              .timesFor(kDefaultCity, DateTime(2027, 1, 1))!
              .times[Prayer.fajr],
          301,
        );
      }
      expect(updates, 2);
    },
  );

  test(
    'failure completes all waiters and a subsequent request can recover',
    () async {
      var requests = 0;
      await http.runWithClient(
        () async {
          final service = ScheduleService(
            await SharedPreferences.getInstance(),
          );
          await Future.wait([
            service.ensureLoaded(kDefaultCity, 2026),
            service.ensureLoaded(kDefaultCity, 2026),
          ]);
          await service.ensureLoaded(kDefaultCity, 2026);
          expect(requests, 2);
          expect(
            service
                .timesFor(kDefaultCity, DateTime(2026, 10, 21))!
                .times[Prayer.fajr],
            312,
          );
        },
        () => MockClient(
          (_) async => ++requests == 1
              ? http.Response('', 503)
              : _reply('2026-10-21', '05:12'),
        ),
      );
    },
  );
}
