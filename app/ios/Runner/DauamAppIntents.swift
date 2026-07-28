import AppIntents
import Foundation
import UIKit

private struct SimplePrayerPoint: Codable {
  let id: String
  let title: String
  let time: String
  let timestamp: Double
  let isTomorrow: Bool
}

private struct SimpleSnapshot: Codable {
  let language: String
  let city: String
  let prayers: [SimplePrayerPoint]
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct NextPrayerIntent: AppIntent {
  public static var title: LocalizedStringResource = "Когда следующий намаз?"
  public static var description = IntentDescription(
    "Показывает точное время ближайшего намаза и живой отсчёт."
  )
  public static var openAppWhenRun: Bool = false

  public init() {}

  public func perform() async throws -> some IntentResult & ReturnsValue<String>
    & ProvidesDialog
  {
    let now = Date().timeIntervalSince1970
    if
      let defaults = UserDefaults(suiteName: "group.kz.dauam.shared"),
      let json = defaults.string(forKey: "widget_snapshot_v1"),
      let data = json.data(using: .utf8),
      let snapshot = try? JSONDecoder().decode(SimpleSnapshot.self, from: data),
      let next = snapshot.prayers.filter({ $0.timestamp > now }).min(by: { $0.timestamp < $1.timestamp })
    {
      let diff = Int((next.timestamp - now) / 60)
      let hours = diff / 60
      let mins = diff % 60
      let untilStr = hours > 0 ? "\(hours) ч \(mins) мин" : "\(mins) мин"
      let isKz = snapshot.language == "kz"
      let response = isKz
        ? "\(next.title) уақыты \(next.time) (\(untilStr) қалды)."
        : "\(next.title) в \(next.time) (осталось \(untilStr))."
      return .result(
        value: response,
        dialog: IntentDialog(stringLiteral: response)
      )
    } else {
      let response = "Ближайшая молитва в расписании. Откройте Dauam для проверки времён."
      return .result(
        value: response,
        dialog: IntentDialog(stringLiteral: response)
      )
    }
  }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct StartMorningAdhkarIntent: AppIntent {
  public static var title: LocalizedStringResource = "Начать утренние зикры"
  public static var description = IntentDescription(
    "Открывает утренние зикры."
  )
  public static var openAppWhenRun: Bool = true

  public init() {}

  @MainActor
  public func perform() async throws -> some IntentResult {
    WidgetDataManager.notifyTarget("morning")
    return .result()
  }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct StartEveningAdhkarIntent: AppIntent {
  public static var title: LocalizedStringResource = "Начать вечерние зикры"
  public static var description = IntentDescription(
    "Открывает вечерние зикры."
  )
  public static var openAppWhenRun: Bool = true

  public init() {}

  @MainActor
  public func perform() async throws -> some IntentResult {
    WidgetDataManager.notifyTarget("evening")
    return .result()
  }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct DauamShortcuts: AppShortcutsProvider {
  public static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: NextPrayerIntent(),
      phrases: [
        "Когда следующий намаз в \(.applicationName)?",
        "Сколько до намаза в \(.applicationName)?",
        "Время молитвы в \(.applicationName)",
      ],
      shortTitle: "Следующий намаз",
      systemImageName: "moon.stars.fill"
    )
    AppShortcut(
      intent: StartMorningAdhkarIntent(),
      phrases: [
        "Начать утренние зикры в \(.applicationName)",
        "Утренние зикры в \(.applicationName)",
      ],
      shortTitle: "Утренние зикры",
      systemImageName: "sun.max.fill"
    )
    AppShortcut(
      intent: StartEveningAdhkarIntent(),
      phrases: [
        "Начать вечерние зикры в \(.applicationName)",
        "Вечерние зикры в \(.applicationName)",
      ],
      shortTitle: "Вечерние зикры",
      systemImageName: "sunset.fill"
    )
  }
}
