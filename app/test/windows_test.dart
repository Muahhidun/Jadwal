import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/prayer/schedule.dart';
import 'package:jadwal/prayer/windows.dart';

DayTimes day({required bool friday}) => DayTimes(
      // 03.07.2026 — пятница, 04.07.2026 — суббота.
      date: friday ? DateTime(2026, 7, 3) : DateTime(2026, 7, 4),
      times: const {
        Prayer.fajr: 185, // 03:05
        Prayer.sunrise: 298, // 04:58
        Prayer.dhuhr: 779, // 12:59
        Prayer.asr: 1074, // 17:54
        Prayer.maghrib: 1253, // 20:53
        Prayer.isha: 1358, // 22:38
      },
    );

void main() {
  test('утреннее окно: после Фаджра, до восхода', () {
    final w = currentWindow(day(friday: false), 200, (_) => false);
    expect(w?.id, TaskId.morning);
    final closed = currentWindow(day(friday: false), 300, (_) => false);
    expect(closed, isNull); // после восхода окно закрыто
  });

  test('пятница добавляет Кахф и час дуа', () {
    final ids = windowsFor(day(friday: true)).map((w) => w.id).toList();
    expect(ids, [TaskId.morning, TaskId.kahf, TaskId.evening, TaskId.dua]);
    expect(windowsFor(day(friday: false)).map((w) => w.id).toList(),
        [TaskId.morning, TaskId.evening]);
  });

  test('выполненная задача уступает окно следующей', () {
    // 20:11 пятницы: открыты и вечерние (аср→магриб), и час дуа (магриб−60).
    final w = currentWindow(day(friday: true), 1211, (id) => id == TaskId.evening);
    expect(w?.id, TaskId.dua);
  });

  test('после Иша следующая молитва — null (завтрашний Фаджр)', () {
    expect(nextPrayer(day(friday: false), 1400), isNull);
    expect(nextPrayer(day(friday: false), 100), Prayer.fajr);
  });

  test('режим «после азана» действует первые 15 минут', () {
    expect(justCalledPrayer(day(friday: false), 1074 + 5), Prayer.asr);
    expect(justCalledPrayer(day(friday: false), 1074 + 20), isNull);
  });
}
