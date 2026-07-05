/// Слой времён молитв.
///
/// Сейчас — демо-провайдер с фиксированным днём из дизайн-прототипа
/// (пятница 20:11, Алматы), чтобы строить и проверять UI детерминированно.
/// Дальше его заменит боевой провайдер: таблицы ДУМК (namaz.muftyat.kz)
/// + астрономический расчёт (пакет adhan) как офлайн-запас. Интерфейс общий.
library;

enum Prayer { fajr, sunrise, dhuhr, asr, maghrib, isha }

class DaySchedule {
  /// Времена шести точек дня в минутах от полуночи.
  final Map<Prayer, int> times;
  final bool isFriday;

  /// «Сейчас» в минутах от полуночи (в демо зафиксировано).
  final int nowMinutes;

  const DaySchedule({required this.times, required this.isFriday, required this.nowMinutes});

  String fmt(Prayer p) {
    final t = times[p]!;
    return '${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}';
  }

  /// Осталось минут до точки (отрицательное — точка прошла).
  int minutesUntil(Prayer p) => times[p]! - nowMinutes;

  static String fmtDuration(int minutes) =>
      '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
}

abstract class ScheduleProvider {
  DaySchedule today();
}

/// Демо: день из прототипа — пятница, Алматы, 20:11.
class DemoScheduleProvider implements ScheduleProvider {
  const DemoScheduleProvider();

  @override
  DaySchedule today() => const DaySchedule(
        times: {
          Prayer.fajr: 3 * 60 + 5,
          Prayer.sunrise: 4 * 60 + 58,
          Prayer.dhuhr: 12 * 60 + 59,
          Prayer.asr: 17 * 60 + 54,
          Prayer.maghrib: 20 * 60 + 53,
          Prayer.isha: 22 * 60 + 38,
        },
        isFriday: true,
        nowMinutes: 20 * 60 + 11,
      );
}
