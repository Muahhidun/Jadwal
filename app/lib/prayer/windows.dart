import 'schedule.dart';

/// Движок окон поклонения — сердце продукта.
/// Каждое окно имеет основание в Сунне; границы — от времён молитв дня.
enum TaskId { morning, kahf, evening, dua }

class WorshipWindow {
  final TaskId id;

  /// Границы в минутах от полуночи.
  final int start, end;
  const WorshipWindow(this.id, this.start, this.end);

  bool contains(int nowMin) => nowMin >= start && nowMin < end;
}

/// После закрытия окна ещё полчаса держим дело рядом: пользователь мог
/// закончить чтение на границе времени. Затем лента автоматически ставит
/// первым следующее актуальное дело.
const taskRailGraceMinutes = 30;

bool isWorshipWindowPast(
  WorshipWindow window,
  int nowMin, {
  int graceMinutes = taskRailGraceMinutes,
}) => nowMin >= window.end + graceMinutes;

/// Окна на день. Пятничные (Кахф, час дуа) — только в пятницу.
List<WorshipWindow> windowsFor(DayTimes t) => [
  // Утренние зикры: после Фаджра, до восхода.
  WorshipWindow(
    TaskId.morning,
    t.times[Prayer.fajr]!,
    t.times[Prayer.sunrise]!,
  ),
  // Сура аль-Кахф: пятница, до Джума (Зухр).
  if (t.isFriday)
    WorshipWindow(
      TaskId.kahf,
      t.times[Prayer.sunrise]!,
      t.times[Prayer.dhuhr]!,
    ),
  // Вечерние зикры: после Асра, до захода (Магриба).
  WorshipWindow(TaskId.evening, t.times[Prayer.asr]!, t.times[Prayer.maghrib]!),
  // Час дуа: пятница, последний час перед Магрибом.
  if (t.isFriday)
    WorshipWindow(
      TaskId.dua,
      t.times[Prayer.maghrib]! - 60,
      t.times[Prayer.maghrib]!,
    ),
];

/// Первое открытое сейчас окно, задача которого ещё не выполнена.
WorshipWindow? currentWindow(
  DayTimes t,
  int nowMin,
  bool Function(TaskId) isDone,
) => windowsFor(t)
    .where((w) => w.contains(nowMin) && !isDone(w.id))
    .fold<WorshipWindow?>(null, (acc, w) => acc ?? w);

/// Все задачи дня выполнены?
bool allDone(DayTimes t, bool Function(TaskId) isDone) =>
    windowsFor(t).every((w) => isDone(w.id));

/// Ближайшая следующая молитва после nowMin (null — день закончился, Иша прошла).
Prayer? nextPrayer(DayTimes t, int nowMin) {
  for (final p in Prayer.values) {
    if (t.times[p]! > nowMin) return p;
  }
  return null;
}

/// Ближайший из пяти намазов для уведомлений и Live Activity.
/// Восход присутствует в расписании как важная граница дня, но намазом не
/// является и не должен получать подпись «До намаза».
Prayer? nextNamaz(DayTimes t, int nowMin) {
  for (final prayer in const [
    Prayer.fajr,
    Prayer.dhuhr,
    Prayer.asr,
    Prayer.maghrib,
    Prayer.isha,
  ]) {
    if (t.times[prayer]! > nowMin) return prayer;
  }
  return null;
}

/// Режим «после азана»: молитва наступила менее [graceMinutes] назад.
/// Возвращает её, чтобы показать «после азана прошло X мин» (README §2 плана).
Prayer? justCalledPrayer(DayTimes t, int nowMin, {int graceMinutes = 10}) {
  Prayer? last;
  for (final p in Prayer.values) {
    if (p == Prayer.sunrise) continue; // восход — не азан
    if (t.times[p]! <= nowMin) last = p;
  }
  if (last == null) return null;
  return (nowMin - t.times[last]!) < graceMinutes ? last : null;
}
