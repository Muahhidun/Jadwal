import Foundation
import SwiftUI
import WidgetKit

private enum DauamWidgetStore {
  static let appGroup = "group.kz.dauam.shared"
  static let snapshotKey = "widget_snapshot_v1"

  static func load() -> DauamSnapshot {
    guard
      let defaults = UserDefaults(suiteName: appGroup),
      let json = defaults.string(forKey: snapshotKey),
      let data = json.data(using: .utf8),
      let snapshot = try? JSONDecoder().decode(DauamSnapshot.self, from: data)
    else {
      return .placeholder
    }
    return snapshot
  }
}

private struct DauamPrayerPoint: Codable, Hashable {
  let id: String
  let title: String
  let time: String
  let timestamp: Double
  let isTomorrow: Bool

  var date: Date { Date(timeIntervalSince1970: timestamp) }

  var symbol: String {
    switch id {
    case "fajr": return "moon.stars.fill"
    case "sunrise": return "sunrise.fill"
    case "dhuhr": return "sun.max.fill"
    case "asr": return "sun.haze.fill"
    case "maghrib": return "sunset.fill"
    case "isha": return "moon.fill"
    default: return "clock.fill"
    }
  }
}

private struct DauamTask: Codable, Hashable {
  let id: String
  let title: String
  let done: Bool
}

private struct DauamSnapshot: Codable, Hashable {
  let schemaVersion: Int
  let generatedAt: Double
  let language: String
  let city: String
  let dateLabel: String
  let prayers: [DauamPrayerPoint]
  let tasks: [DauamTask]
  let taskDone: Int
  let taskTotal: Int

  static let placeholder = DauamSnapshot(
    schemaVersion: 1,
    generatedAt: Date.now.timeIntervalSince1970,
    language: "ru",
    city: "Экибастуз",
    dateLabel: "Пятница · 10 сафар",
    prayers: [
      .init(id: "fajr", title: "Фаджр", time: "03:45", timestamp: Date.now.addingTimeInterval(2_700).timeIntervalSince1970, isTomorrow: false),
      .init(id: "sunrise", title: "Восход", time: "05:15", timestamp: Date.now.addingTimeInterval(8_160).timeIntervalSince1970, isTomorrow: false),
      .init(id: "dhuhr", title: "Зухр", time: "12:55", timestamp: Date.now.addingTimeInterval(27_480).timeIntervalSince1970, isTomorrow: false),
      .init(id: "asr", title: "Аср", time: "17:34", timestamp: Date.now.addingTimeInterval(41_640).timeIntervalSince1970, isTomorrow: false),
      .init(id: "maghrib", title: "Магриб", time: "20:50", timestamp: Date.now.addingTimeInterval(53_520).timeIntervalSince1970, isTomorrow: false),
      .init(id: "isha", title: "Иша", time: "22:30", timestamp: Date.now.addingTimeInterval(58_620).timeIntervalSince1970, isTomorrow: false),
    ],
    tasks: [
      .init(id: "morning", title: "Утренние зикры", done: true),
      .init(id: "evening", title: "Вечерние зикры", done: false),
    ],
    taskDone: 1,
    taskTotal: 2
  )

  var isPlaceholder: Bool {
    prayers.allSatisfy { $0.timestamp <= generatedAt + 60 }
  }

  /// Ближайшая временная точка расписания. Восход не является намазом,
  /// но для виджета остаётся полноценным следующим событием после Фаджра.
  func nextEvent(after date: Date) -> DauamPrayerPoint? {
    prayers
      .filter { $0.date > date }
      .min { $0.date < $1.date }
  }

  func justCalledPrayer(at date: Date, graceMinutes: Double = 10) -> DauamPrayerPoint? {
    let valid = prayers.filter { $0.id != "sunrise" }
    guard let last = valid.filter({ $0.date <= date }).max(by: { $0.date < $1.date }) else {
      return nil
    }
    let elapsed = date.timeIntervalSince(last.date)
    return (elapsed >= 0 && elapsed < graceMinutes * 60) ? last : nil
  }

  func prayers(on date: Date) -> [DauamPrayerPoint] {
    prayers.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
  }

  func prayer(id: String, on date: Date) -> DauamPrayerPoint? {
    prayers(on: date).first { $0.id == id }
  }

  var isKazakh: Bool { language == "kz" }

  func until(_ prayer: DauamPrayerPoint, uppercase: Bool = false) -> String {
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

  var openDauam: String {
    isKazakh ? "Dauam қолданбасын ашыңыз" : "Откройте Dauam"
  }

  var todayTasksTitle: String {
    isKazakh ? "Бүгінгі істер" : "Дела сегодня"
  }

  var completedSummary: String {
    isKazakh
      ? "\(taskDone) / \(taskTotal) орындалды"
      : "\(taskDone) из \(taskTotal) выполнено"
  }
}

private struct DauamEntry: TimelineEntry {
  let date: Date
  let snapshot: DauamSnapshot
}

private struct DauamProvider: TimelineProvider {
  func placeholder(in context: Context) -> DauamEntry {
    DauamEntry(date: .now, snapshot: .placeholder)
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (DauamEntry) -> Void
  ) {
    completion(
      DauamEntry(
        date: .now,
        snapshot: context.isPreview ? .placeholder : DauamWidgetStore.load()
      )
    )
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<DauamEntry>) -> Void
  ) {
    let now = Date.now
    let snapshot = DauamWidgetStore.load()
    var dates = [now]

    // В момент наступления любой точки расписания (включая восход) контент
    // должен перейти к следующему событию.
    // Сам countdown между этими точками обновляет системный Text(.timer).
    let horizon = now.addingTimeInterval(36 * 3_600)
    for prayer in snapshot.prayers {
      let eventStart = prayer.date.addingTimeInterval(1)
      if eventStart > now && eventStart < horizon {
        dates.append(eventStart)
      }

      // Конец десятиминутного окна планируется независимо от его начала.
      // Если WidgetKit запросил новый timeline уже после азана, начало осталось
      // в прошлом, но будущая граница всё равно обязана попасть в timeline.
      let graceEnd = prayer.date.addingTimeInterval(601)
      if prayer.id != "sunrise" && graceEnd > now && graceEnd < horizon {
        dates.append(graceEnd)
      }
    }
    dates = Array(Set(dates)).sorted()

    let entries = dates.map { DauamEntry(date: $0, snapshot: snapshot) }
    let refresh = min(
      dates.last?.addingTimeInterval(60) ?? now.addingTimeInterval(6 * 3_600),
      now.addingTimeInterval(12 * 3_600)
    )
    completion(Timeline(entries: entries, policy: .after(refresh)))
  }
}

private struct DauamPalette {
  let top: Color
  let bottom: Color
  let text: Color
  let secondary: Color
  let accent: Color

  static func resolve(snapshot: DauamSnapshot, at date: Date) -> DauamPalette {
    let fajr = snapshot.prayer(id: "fajr", on: date)?.date ?? date
    let sunrise = snapshot.prayer(id: "sunrise", on: date)?.date ?? date
    let asr = snapshot.prayer(id: "asr", on: date)?.date ?? date
    let maghrib = snapshot.prayer(id: "maghrib", on: date)?.date ?? date
    let isha = snapshot.prayer(id: "isha", on: date)?.date ?? date

    if date < fajr || date >= isha {
      return .init(
        top: Color(red: 0.045, green: 0.075, blue: 0.16),
        bottom: Color(red: 0.10, green: 0.12, blue: 0.24),
        text: Color(red: 0.96, green: 0.95, blue: 0.91),
        secondary: Color.white.opacity(0.66),
        accent: Color(red: 0.48, green: 0.78, blue: 0.84)
      )
    }
    if date < sunrise {
      return .init(
        top: Color(red: 0.22, green: 0.27, blue: 0.47),
        bottom: Color(red: 0.66, green: 0.40, blue: 0.38),
        text: Color(red: 0.99, green: 0.96, blue: 0.91),
        secondary: Color.white.opacity(0.72),
        accent: Color(red: 1.0, green: 0.76, blue: 0.38)
      )
    }
    if date < asr {
      return .init(
        top: Color(red: 0.53, green: 0.75, blue: 0.92),
        bottom: Color(red: 0.78, green: 0.88, blue: 0.94),
        text: Color(red: 0.06, green: 0.13, blue: 0.19),
        secondary: Color(red: 0.18, green: 0.30, blue: 0.36),
        accent: Color(red: 0.04, green: 0.43, blue: 0.54)
      )
    }
    if date < maghrib {
      return .init(
        top: Color(red: 0.43, green: 0.57, blue: 0.76),
        bottom: Color(red: 0.91, green: 0.64, blue: 0.43),
        text: Color(red: 0.08, green: 0.12, blue: 0.17),
        secondary: Color(red: 0.20, green: 0.23, blue: 0.27),
        accent: Color(red: 0.05, green: 0.38, blue: 0.48)
      )
    }
    return .init(
      top: Color(red: 0.34, green: 0.23, blue: 0.35),
      bottom: Color(red: 0.13, green: 0.16, blue: 0.29),
      text: Color(red: 0.98, green: 0.95, blue: 0.90),
      secondary: Color.white.opacity(0.68),
      accent: Color(red: 0.54, green: 0.82, blue: 0.86)
    )
  }

  var gradient: LinearGradient {
    LinearGradient(
      colors: [top, bottom],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
}

private extension View {
  @ViewBuilder
  func dauamWidgetBackground(_ palette: DauamPalette) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) {
        palette.gradient
      }
    } else {
      background(palette.gradient)
    }
  }

  @ViewBuilder
  func dauamAccessoryBackground() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) {
        Color.clear
      }
    } else {
      self
    }
  }
}

private struct DauamMark: View {
  let palette: DauamPalette

  var body: some View {
    Text("دوام")
      .font(.system(size: 15, weight: .bold, design: .serif))
      .foregroundStyle(palette.accent)
      .accessibilityLabel("Dauam")
  }
}

private struct NextPrayerBlock: View {
  let entryDate: Date
  let next: DauamPrayerPoint?
  let snapshot: DauamSnapshot
  let palette: DauamPalette
  let compact: Bool
  let timerSize: CGFloat

  var body: some View {
    if let called = snapshot.justCalledPrayer(at: entryDate) {
      VStack(alignment: .leading, spacing: compact ? 4 : 7) {
        Text(snapshot.isKazakh ? "АЗАННАН КЕЙІН" : "ПОСЛЕ АЗАНА")
          .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
          .tracking(1.2)
          .foregroundStyle(palette.accent)
          .lineLimit(1)
        Text(called.date, style: .timer)
          .font(
            .system(
              size: timerSize,
              weight: .medium,
              design: .rounded
            )
            .monospacedDigit()
          )
          .foregroundStyle(palette.text)
          .minimumScaleFactor(0.68)
          .lineLimit(1)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(snapshot.isKazakh ? "Азаннан кейін" : "После азана")
    } else if let next {
      VStack(alignment: .leading, spacing: compact ? 4 : 7) {
        Text(snapshot.until(next, uppercase: true))
          .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
          .tracking(1.2)
          .foregroundStyle(palette.accent)
          .lineLimit(1)
        if next.date > entryDate {
          Text(next.date, style: .timer)
            .font(
              .system(
                size: timerSize,
                weight: .medium,
                design: .rounded
              )
              .monospacedDigit()
            )
            .foregroundStyle(palette.text)
            .minimumScaleFactor(0.68)
            .lineLimit(1)
        } else {
          Text(next.time)
            .font(.system(size: timerSize, weight: .medium, design: .rounded))
            .foregroundStyle(palette.text)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(snapshot.until(next))
    } else {
      Text(snapshot.openDauam)
        .font(.system(size: 16, weight: .semibold, design: .rounded))
        .foregroundStyle(palette.text)
    }
  }
}

private struct PrayerGrid: View {
  let snapshot: DauamSnapshot
  let date: Date
  let next: DauamPrayerPoint?
  let palette: DauamPalette

  private let columns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
  ]

  var body: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
      ForEach(snapshot.prayers(on: date), id: \.id) { prayer in
        HStack(spacing: 4) {
          Image(systemName: prayer.symbol)
            .font(.system(size: 9, weight: .semibold))
            .frame(width: 12)
          VStack(alignment: .leading, spacing: 1) {
            Text(prayer.title)
              .font(.system(size: 10, weight: .semibold, design: .rounded))
              .lineLimit(1)
              .minimumScaleFactor(0.80)
              .allowsTightening(true)
            Text(prayer.time)
              .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
              .lineLimit(1)
              .minimumScaleFactor(0.82)
              .allowsTightening(true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(prayer.id == next?.id ? palette.accent : palette.text)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

private struct DauamSmallPrayerView: View {
  let entry: DauamEntry
  let palette: DauamPalette

  var body: some View {
    let next = entry.snapshot.nextEvent(after: entry.date)
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        DauamMark(palette: palette)
        Spacer()
        Image(systemName: next?.symbol ?? "moon.stars.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(palette.accent)
      }
      Spacer(minLength: 5)
      NextPrayerBlock(
        entryDate: entry.date,
        next: next,
        snapshot: entry.snapshot,
        palette: palette,
        compact: true,
        timerSize: 29
      )
      Spacer(minLength: 6)
      HStack(spacing: 4) {
        Image(systemName: "location.fill")
          .font(.system(size: 8))
        Text(entry.snapshot.city)
          .font(.system(size: 10, weight: .medium, design: .rounded))
          .lineLimit(1)
      }
      .foregroundStyle(palette.secondary)
      .privacySensitive()
    }
    .padding(14)
    .dauamWidgetBackground(palette)
    .widgetURL(URL(string: "dauam://home"))
  }
}

private struct DauamMediumPrayerView: View {
  let entry: DauamEntry
  let palette: DauamPalette

  var body: some View {
    let next = entry.snapshot.nextEvent(after: entry.date)
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 0) {
        DauamMark(palette: palette)
        Spacer()
        NextPrayerBlock(
          entryDate: entry.date,
          next: next,
          snapshot: entry.snapshot,
          palette: palette,
          compact: true,
          timerSize: 28
        )
        Spacer()
        Text(entry.snapshot.city)
          .font(.system(size: 10, weight: .medium, design: .rounded))
          .foregroundStyle(palette.secondary)
          .lineLimit(1)
          .privacySensitive()
      }
      .frame(width: 126, alignment: .leading)

      Rectangle()
        .fill(palette.text.opacity(0.14))
        .frame(width: 1)

      PrayerGrid(snapshot: entry.snapshot, date: entry.date, next: next, palette: palette)
        .frame(maxWidth: .infinity)
    }
    .padding(14)
    .dauamWidgetBackground(palette)
    .widgetURL(URL(string: "dauam://home"))
  }
}

private struct DauamLargePrayerView: View {
  let entry: DauamEntry
  let palette: DauamPalette

  var body: some View {
    let next = entry.snapshot.nextEvent(after: entry.date)
    let dayPrayers = entry.snapshot.prayers(on: entry.date)
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          DauamMark(palette: palette)
          Text(entry.snapshot.dateLabel)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(palette.secondary)
        }
        Spacer()
        Text(entry.snapshot.city)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(palette.secondary)
          .lineLimit(1)
          .privacySensitive()
      }

      NextPrayerBlock(
        entryDate: entry.date,
        next: next,
        snapshot: entry.snapshot,
        palette: palette,
        compact: false,
        timerSize: 36
      )

      VStack(spacing: 0) {
        ForEach(dayPrayers, id: \.id) { prayer in
          HStack {
            Image(systemName: prayer.symbol)
              .font(.system(size: 11, weight: .semibold))
              .frame(width: 18)
            Text(prayer.title)
              .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer()
            Text(prayer.time)
              .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
          }
          .foregroundStyle(prayer.id == next?.id ? palette.accent : palette.text)
          .padding(.vertical, 5)
          if prayer.id != dayPrayers.last?.id {
            Rectangle()
              .fill(palette.text.opacity(0.10))
              .frame(height: 1)
          }
        }
      }
      .padding(.horizontal, 10)
      .background(palette.text.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

      HStack(spacing: 12) {
        DauamProgressRing(
          done: entry.snapshot.taskDone,
          total: entry.snapshot.taskTotal,
          palette: palette,
          size: 42
        )
        VStack(alignment: .leading, spacing: 3) {
          Text(entry.snapshot.todayTasksTitle.uppercased())
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(1)
            .foregroundStyle(palette.secondary)
          Text(entry.snapshot.completedSummary)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(palette.text)
        }
        Spacer()
      }
    }
    .padding(16)
    .dauamWidgetBackground(palette)
    .widgetURL(URL(string: "dauam://home"))
  }
}

private struct DauamProgressRing: View {
  let done: Int
  let total: Int
  let palette: DauamPalette
  let size: CGFloat

  private var progress: Double {
    guard total > 0 else { return 0 }
    return min(1, max(0, Double(done) / Double(total)))
  }

  var body: some View {
    ZStack {
      Circle()
        .stroke(palette.text.opacity(0.16), lineWidth: 4)
      Circle()
        .trim(from: 0, to: progress)
        .stroke(
          palette.accent,
          style: StrokeStyle(lineWidth: 4, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
      Text("\(done)/\(total)")
        .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
        .foregroundStyle(palette.text)
    }
    .frame(width: size, height: size)
    .accessibilityLabel("\(done) из \(total) дел выполнено")
  }
}

private struct DauamTasksView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DauamEntry

  var body: some View {
    let palette = DauamPalette.resolve(snapshot: entry.snapshot, at: entry.date)
    Group {
      if family == .systemSmall {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            DauamMark(palette: palette)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(palette.accent)
          }
          Text(entry.snapshot.todayTasksTitle)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(palette.text)
          Spacer()
          HStack {
            DauamProgressRing(
              done: entry.snapshot.taskDone,
              total: entry.snapshot.taskTotal,
              palette: palette,
              size: 52
            )
            Spacer()
            Text(
              entry.snapshot.isKazakh
                ? "\(entry.snapshot.taskDone)\n/ \(entry.snapshot.taskTotal)"
                : "\(entry.snapshot.taskDone)\nиз \(entry.snapshot.taskTotal)"
            )
              .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
              .multilineTextAlignment(.trailing)
              .foregroundStyle(palette.text)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 9) {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(entry.snapshot.todayTasksTitle)
                .font(.system(size: 17, weight: .bold, design: .rounded))
              Text(entry.snapshot.completedSummary)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(palette.secondary)
            }
            Spacer()
            DauamProgressRing(
              done: entry.snapshot.taskDone,
              total: entry.snapshot.taskTotal,
              palette: palette,
              size: 44
            )
          }
          ForEach(entry.snapshot.tasks.prefix(3), id: \.id) { task in
            HStack(spacing: 8) {
              Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.done ? palette.accent : palette.secondary)
              Text(task.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
              Spacer()
            }
          }
        }
        .foregroundStyle(palette.text)
      }
    }
    .padding(15)
    .dauamWidgetBackground(palette)
    .widgetURL(URL(string: "dauam://home"))
  }
}

private struct DauamAccessoryView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DauamEntry

  var body: some View {
    let called = entry.snapshot.justCalledPrayer(at: entry.date)
    let next = entry.snapshot.nextEvent(after: entry.date)
    let currentPrayer = called ?? next
    Group {
      switch family {
      case .accessoryInline:
        if let called {
          Label {
            HStack(spacing: 3) {
              Text(entry.snapshot.isKazakh ? "Азаннан кейін" : "После азана")
              Text(called.date, style: .timer)
            }
          } icon: {
            Image(systemName: called.symbol)
          }
        } else if let next {
          Label {
            HStack(spacing: 3) {
              Text(entry.snapshot.until(next))
              Text(next.date, style: .timer)
            }
          } icon: {
            Image(systemName: next.symbol)
          }
        } else {
          Label(entry.snapshot.openDauam, systemImage: "moon.stars.fill")
        }

      case .accessoryCircular:
        ZStack {
          AccessoryWidgetBackground()
          VStack(spacing: 1) {
            Image(systemName: currentPrayer?.symbol ?? "moon.stars.fill")
              .font(.system(size: 13, weight: .bold))
            Text(currentPrayer?.time ?? "—")
              .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
              .minimumScaleFactor(0.7)
          }
        }

      default:
        // Вариант 1: Отсчёт + Время молитвы (Жирный таймер слева, время справа)
        if let called {
          HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
              Text(entry.snapshot.isKazakh ? "АЗАННАН КЕЙІН" : "ПОСЛЕ АЗАНА")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
              Text(called.date, style: .timer)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 1) {
              Image(systemName: called.symbol)
                .font(.system(size: 14, weight: .bold))
              Text(called.time)
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.80)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minWidth: 50)
          }
        } else if let next {
          HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
              Text(entry.snapshot.until(next, uppercase: true))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
              Text(next.date, style: .timer)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 1) {
              Image(systemName: next.symbol)
                .font(.system(size: 14, weight: .bold))
              Text(next.time)
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.80)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minWidth: 50)
          }
        } else {
          HStack(alignment: .center, spacing: 7) {
            Image(systemName: "moon.stars.fill")
              .font(.system(size: 22, weight: .bold))
            VStack(alignment: .leading, spacing: 0) {
              Text("Dauam")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
              Text(entry.snapshot.city)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
            }
          }
        }
      }
    }
    .dauamAccessoryBackground()
    .widgetURL(URL(string: "dauam://home"))
    .accessibilityElement(children: .combine)
  }
}

// Вариант 2: Крупный таймер на всю ширину + Город
private struct DauamAccessoryFullTimerView: View {
  let entry: DauamEntry

  var body: some View {
    let called = entry.snapshot.justCalledPrayer(at: entry.date)
    let next = entry.snapshot.nextEvent(after: entry.date)
    Group {
      if let called {
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 4) {
            Image(systemName: called.symbol)
              .font(.system(size: 10, weight: .bold))
            Text("\(entry.snapshot.isKazakh ? "Азаннан кейін" : "После азана") · \(called.time)")
              .font(.system(size: 11, weight: .semibold, design: .rounded))
              .lineLimit(1)
          }
          Text(called.date, style: .timer)
            .font(.system(size: 24, weight: .heavy, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.70)
          HStack(spacing: 3) {
            Image(systemName: "location.fill")
              .font(.system(size: 7, weight: .semibold))
            Text(entry.snapshot.city)
              .font(.system(size: 9, weight: .semibold, design: .rounded))
              .lineLimit(1)
          }
          .foregroundStyle(.secondary)
        }
      } else if let next {
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 4) {
            Image(systemName: next.symbol)
              .font(.system(size: 10, weight: .bold))
            Text("\(entry.snapshot.until(next)) · \(next.time)")
              .font(.system(size: 11, weight: .semibold, design: .rounded))
              .lineLimit(1)
          }
          Text(next.date, style: .timer)
            .font(.system(size: 24, weight: .heavy, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.70)
          HStack(spacing: 3) {
            Image(systemName: "location.fill")
              .font(.system(size: 7, weight: .semibold))
            Text(entry.snapshot.city)
              .font(.system(size: 9, weight: .semibold, design: .rounded))
              .lineLimit(1)
          }
          .foregroundStyle(.secondary)
        }
      } else {
        Text("Dauam")
          .font(.system(size: 16, weight: .bold, design: .rounded))
      }
    }
    .dauamAccessoryBackground()
    .widgetURL(URL(string: "dauam://home"))
  }
}

// Вариант 3: Намаз + Дела поклонения (Гибрид)
private struct DauamAccessoryWorshipView: View {
  let entry: DauamEntry

  var body: some View {
    let next = entry.snapshot.nextEvent(after: entry.date)
    Group {
      if let next {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 4) {
            Image(systemName: next.symbol)
              .font(.system(size: 11, weight: .bold))
            Text(entry.snapshot.until(next))
              .font(.system(size: 12, weight: .bold, design: .rounded))
              .lineLimit(1)
            Spacer(minLength: 4)
            Text(next.date, style: .timer)
              .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
              .lineLimit(1)
          }

          HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 11, weight: .semibold))
            Text(entry.snapshot.todayTasksTitle)
              .font(.system(size: 11, weight: .semibold, design: .rounded))
              .lineLimit(1)
            Spacer(minLength: 2)
            Text("\(entry.snapshot.taskDone)/\(entry.snapshot.taskTotal)")
              .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .fill(.secondary.opacity(0.18))
          )
        }
      } else {
        Text("Dauam")
          .font(.system(size: 16, weight: .bold, design: .rounded))
      }
    }
    .dauamAccessoryBackground()
    .widgetURL(URL(string: "dauam://home"))
    .accessibilityElement(children: .combine)
  }
}

private struct DauamPrayerEntryView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DauamEntry

  var body: some View {
    let palette = DauamPalette.resolve(snapshot: entry.snapshot, at: entry.date)
    switch family {
    case .systemMedium:
      DauamMediumPrayerView(entry: entry, palette: palette)
    case .systemLarge:
      DauamLargePrayerView(entry: entry, palette: palette)
    default:
      DauamSmallPrayerView(entry: entry, palette: palette)
    }
  }
}

@available(iOS 17.0, *)
public struct DauamPrayerWidget: Widget {
  public init() {}

  public var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "kz.dauam.prayer",
      provider: DauamProvider()
    ) { entry in
      DauamPrayerEntryView(entry: entry)
    }
    .configurationDisplayName("До следующего намаза")
    .description("Живой отсчёт и времена молитв вашего города.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    .containerBackgroundRemovable()
  }
}

@available(iOS 17.0, *)
public struct DauamTasksWidget: Widget {
  public init() {}

  public var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "kz.dauam.tasks",
      provider: DauamProvider()
    ) { entry in
      DauamTasksView(entry: entry)
    }
    .configurationDisplayName("Дела сегодня")
    .description("Утренние и вечерние зикры и ваши напоминания.")
    .supportedFamilies([.systemSmall, .systemMedium])
    .containerBackgroundRemovable()
  }
}

// Вариант 1: Отсчёт + Время
@available(iOS 16.0, *)
public struct DauamAccessoryWidget: Widget {
  public init() {}

  public var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "kz.dauam.accessory",
      provider: DauamProvider()
    ) { entry in
      DauamAccessoryView(entry: entry)
    }
    .configurationDisplayName("Отсчёт и Время (Lock Screen)")
    .description("Живой жирный отсчёт слева и время молитвы справа.")
    .supportedFamilies([
      .accessoryInline,
      .accessoryCircular,
      .accessoryRectangular,
    ])
  }
}

// Вариант 2: Крупный таймер
@available(iOS 16.0, *)
public struct DauamAccessoryFullTimerWidget: Widget {
  public init() {}

  public var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "kz.dauam.accessory.fulltimer",
      provider: DauamProvider()
    ) { entry in
      DauamAccessoryFullTimerView(entry: entry)
    }
    .configurationDisplayName("Крупный таймер (Lock Screen)")
    .description("Максимально крупный жирный отсчёт времени и город.")
    .supportedFamilies([.accessoryRectangular])
  }
}

// Вариант 3: Намаз + Дела поклонения
@available(iOS 16.0, *)
public struct DauamAccessoryWorshipWidget: Widget {
  public init() {}

  public var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "kz.dauam.accessory.worship",
      provider: DauamProvider()
    ) { entry in
      DauamAccessoryWorshipView(entry: entry)
    }
    .configurationDisplayName("Намаз и Дела (Lock Screen)")
    .description("Живой отсчёт молитвы и статус выполнения зикров.")
    .supportedFamilies([.accessoryRectangular])
  }
}
