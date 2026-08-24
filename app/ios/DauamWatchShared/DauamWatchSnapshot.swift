import Foundation

enum DauamWatchConstants {
  static let appGroup = "group.kz.dauam.shared"
  static let snapshotKey = "widget_snapshot_v1"
  static let snapshotMessageKey = "snapshot"
  static let snapshotChanged = Notification.Name("kz.dauam.watch.snapshot.changed")
}

struct DauamWatchPrayer: Codable, Hashable, Identifiable {
  let id: String
  let title: String
  let time: String
  let timestamp: Double
  let isTomorrow: Bool

  var date: Date { Date(timeIntervalSince1970: timestamp) }

  var symbol: String {
    switch id {
    case "fajr": "moon.stars.fill"
    case "sunrise": "sunrise.fill"
    case "dhuhr": "sun.max.fill"
    case "asr": "sun.haze.fill"
    case "maghrib": "sunset.fill"
    case "isha": "moon.fill"
    default: "clock.fill"
    }
  }
}

struct DauamWatchTask: Codable, Hashable, Identifiable {
  let id: String
  let title: String
  let done: Bool
}

struct DauamWatchSnapshot: Codable, Hashable {
  let schemaVersion: Int
  let generatedAt: Double
  let language: String
  let city: String
  let dateLabel: String
  let prayers: [DauamWatchPrayer]
  let tasks: [DauamWatchTask]
  let taskDone: Int
  let taskTotal: Int
  /// Координаты города для Киблы. Optional: снапшоты старых версий их не
  /// содержат — тогда экран Киблы просит открыть приложение на iPhone.
  let lat: Double?
  let lng: Double?

  var isKazakh: Bool { language == "kz" }

  func prayers(on date: Date) -> [DauamWatchPrayer] {
    prayers.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
  }

  func nextEvent(after date: Date) -> DauamWatchPrayer? {
    prayers
      .filter { $0.date > date }
      .min { $0.date < $1.date }
  }

  func justCalledPrayer(at date: Date, graceMinutes: Double = 10) -> DauamWatchPrayer? {
    let valid = prayers.filter { $0.id != "sunrise" }
    guard let last = valid.filter({ $0.date <= date }).max(by: { $0.date < $1.date }) else {
      return nil
    }
    let elapsed = date.timeIntervalSince(last.date)
    return (elapsed >= 0 && elapsed < graceMinutes * 60) ? last : nil
  }

  func progress(to prayer: DauamWatchPrayer, at date: Date) -> Double {
    guard
      let previous = prayers
        .filter({ $0.date <= date })
        .max(by: { $0.date < $1.date })
    else {
      return 0
    }

    let duration = prayer.date.timeIntervalSince(previous.date)
    guard duration > 0 else { return 0 }
    return min(1, max(0, date.timeIntervalSince(previous.date) / duration))
  }

  func prayer(id: String, on date: Date) -> DauamWatchPrayer? {
    prayers(on: date).first { $0.id == id }
  }

  func until(_ prayer: DauamWatchPrayer, uppercase: Bool = false) -> String {
    let target: String
    if isKazakh {
      target = switch prayer.id {
      case "fajr": "Таңға"
      case "sunrise": "Күн шығуына"
      case "dhuhr": "Бесінге"
      case "asr": "Екінтіге"
      case "maghrib": "Ақшамға"
      case "isha": "Құптанға"
      default: prayer.title
      }
    } else {
      target = switch prayer.id {
      case "fajr": "Фаджра"
      case "sunrise": "восхода"
      case "dhuhr": "Зухра"
      case "asr": "Асра"
      case "maghrib": "Магриба"
      case "isha": "Иша"
      default: prayer.title
      }
    }
    let value = isKazakh ? "\(target) дейін" : "До \(target)"
    return uppercase ? value.uppercased() : value
  }

  var scheduleTitle: String { isKazakh ? "Намаз уақыттары" : "Времена молитв" }
  var tasksTitle: String { isKazakh ? "Бүгінгі істер" : "Дела сегодня" }
  var noTasksTitle: String { isKazakh ? "Бүгін іс жоқ" : "Сегодня дел нет" }
  var openPhoneTitle: String {
    isKazakh ? "Dauam қолданбасын iPhone-да ашыңыз" : "Откройте Dauam на iPhone"
  }

  static let placeholder: DauamWatchSnapshot = {
    let calendar = Calendar.current
    let now = Date.now
    let weekdayFormatter = DateFormatter()
    weekdayFormatter.locale = Locale(identifier: "ru_RU")
    weekdayFormatter.dateFormat = "EEEE"
    let currentWeekday = weekdayFormatter.string(from: now).capitalized
    func makeDate(hour: Int, minute: Int, tomorrow: Bool = false) -> Date {
      var components = calendar.dateComponents([.year, .month, .day], from: now)
      components.hour = hour
      components.minute = minute
      let date = calendar.date(from: components) ?? now
      return tomorrow ? calendar.date(byAdding: .day, value: 1, to: date) ?? date : date
    }

    func prayer(
      _ id: String,
      _ title: String,
      _ timeStr: String,
      hour: Int,
      minute: Int,
      tomorrow: Bool = false
    ) -> DauamWatchPrayer {
      let d = makeDate(hour: hour, minute: minute, tomorrow: tomorrow)
      return DauamWatchPrayer(
        id: id,
        title: title,
        time: timeStr,
        timestamp: d.timeIntervalSince1970,
        isTomorrow: tomorrow
      )
    }

    return DauamWatchSnapshot(
      schemaVersion: 1,
      generatedAt: now.timeIntervalSince1970,
      language: "ru",
      city: "Экибастуз",
      // До первой синхронизации хотя бы не показываем заведомо устаревший
      // день недели. Реальные дата и времена сразу заменяются снимком iPhone.
      dateLabel: currentWeekday,
      prayers: [
        prayer("fajr", "Фаджр", "03:45", hour: 3, minute: 45),
        prayer("sunrise", "Восход", "05:15", hour: 5, minute: 15),
        prayer("dhuhr", "Зухр", "12:55", hour: 12, minute: 55),
        prayer("asr", "Аср", "17:34", hour: 17, minute: 34),
        prayer("maghrib", "Магриб", "20:50", hour: 20, minute: 50),
        prayer("isha", "Иша", "22:30", hour: 22, minute: 30),
        prayer("fajr", "Фаджр", "03:45", hour: 3, minute: 45, tomorrow: true),
      ],
      tasks: [
        DauamWatchTask(id: "morning", title: "Утренние зикры", done: true),
        DauamWatchTask(id: "evening", title: "Вечерние зикры", done: false),
      ],
      taskDone: 1,
      taskTotal: 2,
      lat: nil,
      lng: nil
    )
  }()
}

enum DauamWatchSnapshotStore {
  static func load() -> DauamWatchSnapshot {
    guard
      let defaults = UserDefaults(suiteName: DauamWatchConstants.appGroup),
      let json = defaults.string(forKey: DauamWatchConstants.snapshotKey),
      let data = json.data(using: .utf8),
      let snapshot = try? JSONDecoder().decode(DauamWatchSnapshot.self, from: data)
    else {
      return .placeholder
    }
    return snapshot
  }

  @discardableResult
  static func save(json: String) -> Bool {
    guard
      let data = json.data(using: .utf8),
      (try? JSONDecoder().decode(DauamWatchSnapshot.self, from: data)) != nil,
      let defaults = UserDefaults(suiteName: DauamWatchConstants.appGroup)
    else {
      return false
    }
    defaults.set(json, forKey: DauamWatchConstants.snapshotKey)
    defaults.synchronize()
    return true
  }
}

struct DauamWatchPalette {
  let top: UInt
  let bottom: UInt
  let accent: UInt
  let darkText: Bool

  static func resolve(snapshot: DauamWatchSnapshot, at date: Date) -> DauamWatchPalette {
    let fajr = snapshot.prayer(id: "fajr", on: date)?.date ?? date
    let sunrise = snapshot.prayer(id: "sunrise", on: date)?.date ?? date
    let asr = snapshot.prayer(id: "asr", on: date)?.date ?? date
    let maghrib = snapshot.prayer(id: "maghrib", on: date)?.date ?? date
    let isha = snapshot.prayer(id: "isha", on: date)?.date ?? date

    if date < fajr || date >= isha {
      return .init(top: 0x0C142B, bottom: 0x1A1F3D, accent: 0x7AC7D6, darkText: false)
    }
    if date < sunrise {
      return .init(top: 0x384578, bottom: 0xA86661, accent: 0xFFC261, darkText: false)
    }
    if date < asr {
      return .init(top: 0x87BFEA, bottom: 0xC7E0F0, accent: 0x0A6D89, darkText: true)
    }
    if date < maghrib {
      return .init(top: 0x6E91C2, bottom: 0xE8A36E, accent: 0x0D617A, darkText: true)
    }
    return .init(top: 0x573A59, bottom: 0x22294A, accent: 0x8AD1DB, darkText: false)
  }
}
