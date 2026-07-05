/// Слой времён молитв: модель дня + астрономический расчёт (запасной источник).
///
/// Основной источник — таблицы ДУМК (см. muftyat.dart), чтобы совпадать
/// с муфтиятом минута в минуту. Расчёт пакетом adhan используется как
/// офлайн-запас и для мест за пределами Казахстана.
library;

import 'package:adhan/adhan.dart';
import 'city.dart';

enum Prayer { fajr, sunrise, dhuhr, asr, maghrib, isha }

/// Времена шести точек дня в минутах от полуночи локального времени.
class DayTimes {
  final DateTime date;
  final Map<Prayer, int> times;
  const DayTimes({required this.date, required this.times});

  bool get isFriday => date.weekday == DateTime.friday;

  String fmt(Prayer p) {
    final t = times[p]!;
    return '${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}';
  }

  static String fmtDuration(int minutes) {
    if (minutes < 0) minutes = 0;
    return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
  }
}

/// Запасной астрономический расчёт (adhan). Метод — Muslim World League,
/// аср — ханафитский (стандарт для Казахстана). Возможны расхождения
/// с таблицами ДУМК на несколько минут — поэтому он только fallback.
DayTimes calculateDayTimes(City city, DateTime date) {
  final params = CalculationMethod.muslim_world_league.getParameters()
    ..madhab = Madhab.hanafi;
  final pt = PrayerTimes(
      Coordinates(city.lat, city.lng), DateComponents.from(date), params);
  int mins(DateTime t) {
    final l = t.toLocal();
    return l.hour * 60 + l.minute;
  }

  return DayTimes(date: DateTime(date.year, date.month, date.day), times: {
    Prayer.fajr: mins(pt.fajr),
    Prayer.sunrise: mins(pt.sunrise),
    Prayer.dhuhr: mins(pt.dhuhr),
    Prayer.asr: mins(pt.asr),
    Prayer.maghrib: mins(pt.maghrib),
    Prayer.isha: mins(pt.isha),
  });
}
