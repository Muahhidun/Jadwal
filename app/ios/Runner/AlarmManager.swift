#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI

@available(iOS 26.0, *)
struct DauamAlarmMetadata: AlarmMetadata {
  var title: String
  var kind: String
}
#endif

/// Мост Flutter → AlarmKit для настоящих системных будильников намазов.
///
/// Важно: этот класс намеренно не подменяет ошибку AlarmKit обычным
/// UNUserNotificationCenter-уведомлением. Иначе Flutter сообщает об успешном
/// будильнике, хотя iOS зарегистрировала только простое уведомление.
public final class AlarmManager: NSObject, FlutterPlugin {
  static let channelName = "kz.dauam/alarm"

  private static let legacyNotificationPrefix = "dauam.fajr.alarm"
  private static let fajrAlarmID = UUID(
    uuidString: "DA0A0000-0000-4000-8000-000000000001"
  )!
  private static let testAlarmID = UUID(
    uuidString: "DA0A0000-0000-4000-8000-000000000002"
  )!
  private static let testHeavySleeperBackupIDs: [UUID] = [
    UUID(uuidString: "DA0A0000-0000-4000-8000-000000000011")!,
    UUID(uuidString: "DA0A0000-0000-4000-8000-000000000012")!,
    UUID(uuidString: "DA0A0000-0000-4000-8000-000000000013")!,
  ]
  private static let prayerAlarmIDs: [String: UUID] = [
    "fajr": fajrAlarmID,
    "sunrise": UUID(uuidString: "DA0A0000-0000-4000-8000-000000000007")!,
    "dhuhr": UUID(uuidString: "DA0A0000-0000-4000-8000-000000000003")!,
    "asr": UUID(uuidString: "DA0A0000-0000-4000-8000-000000000004")!,
    "maghrib": UUID(uuidString: "DA0A0000-0000-4000-8000-000000000005")!,
    "isha": UUID(uuidString: "DA0A0000-0000-4000-8000-000000000006")!,
  ]
  private static let heavySleeperBackupIDs: [UUID] = [
    UUID(uuidString: "DA0A0000-0000-4000-8000-000000000008")!,
    UUID(uuidString: "DA0A0000-0000-4000-8000-000000000009")!,
    UUID(uuidString: "DA0A0000-0000-4000-8000-000000000010")!,
  ]

  private enum BridgeError: LocalizedError {
    case alarmKitUnavailable
    case authorizationDenied
    case invalidDate

    var errorDescription: String? {
      switch self {
      case .alarmKitUnavailable:
        return "Настоящие системные будильники доступны только в iOS 26 и новее."
      case .authorizationDenied:
        return "Dauam не получил разрешение iOS на создание будильников."
      case .invalidDate:
        return "Время будильника уже прошло."
      }
    }

    var flutterCode: String {
      switch self {
      case .alarmKitUnavailable:
        return "ALARMKIT_UNAVAILABLE"
      case .authorizationDenied:
        return "ALARM_PERMISSION_DENIED"
      case .invalidDate:
        return "INVALID_ALARM_DATE"
      }
    }
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(AlarmManager(), channel: channel)
  }

  public func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "getPendingAlarms":
      getPendingAlarms(result: result)

    case "syncPrayerAlarms":
      guard
        let args = call.arguments as? [String: Any],
        let alarms = args["alarms"] as? [[String: Any]]
      else {
        result(
          FlutterError(
            code: "INVALID_ARGS",
            message: "Expected an alarms array.",
            details: nil
          )
        )
        return
      }
      syncPrayerAlarms(alarms, result: result)

    case "testFajrAlarm":
      let args = call.arguments as? [String: Any]
      let seconds = max(args?["seconds"] as? Double ?? 10, 1)
      let title = args?["title"] as? String ?? "Фаджр (Тест)"
      let heavySleeper = args?["heavySleeper"] as? Bool ?? false
      let repeatButtonTitle = args?["repeatButtonTitle"] as? String
        ?? "Повторить через 3 минуты"
      let requestedMinutes = (args?["backupMinutes"] as? [NSNumber])?
        .map(\.intValue) ?? [3, 6, 9]
      scheduleTestAlarm(
        at: Date().addingTimeInterval(seconds),
        title: title,
        heavySleeper: heavySleeper,
        repeatButtonTitle: repeatButtonTitle,
        backupMinutes: requestedMinutes,
        result: result
      )

    case "scheduleFajrAlarm":
      guard let args = call.arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "INVALID_ARGS",
            message: "Expected dictionary arguments.",
            details: nil
          )
        )
        return
      }

      let enabled = args["enabled"] as? Bool ?? false
      guard enabled else {
        cancelFajrAlarm(result: result)
        return
      }

      let timestamp = args["timestamp"] as? Double ?? 0
      let title = args["title"] as? String ?? "Фаджр"
      schedule(
        at: Date(timeIntervalSince1970: timestamp),
        title: title,
        kind: "fajr",
        id: Self.fajrAlarmID,
        result: result
      )

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func syncPrayerAlarms(
    _ entries: [[String: Any]],
    result: @escaping FlutterResult
  ) {
    removeLegacyNotificationFallbacks()

    let validEntries = entries.filter { entry in
      guard let kind = entry["id"] as? String else { return false }
      return Self.prayerAlarmIDs[kind] != nil
    }
    let enabledEntries = validEntries.filter {
      $0["enabled"] as? Bool ?? false
    }

    for entry in enabledEntries {
      let timestamp = entry["timestamp"] as? Double ?? 0
      if Date(timeIntervalSince1970: timestamp).timeIntervalSinceNow <= 0 {
        finish(result, with: BridgeError.invalidDate)
        return
      }
    }

    #if canImport(AlarmKit)
    guard #available(iOS 26.0, *) else {
      if enabledEntries.isEmpty {
        finish(
          result,
          value: ["success": true, "mode": "alarmKit", "scheduled": 0]
        )
      } else {
        finish(result, with: BridgeError.alarmKitUnavailable)
      }
      return
    }

    Task {
      do {
        let manager = AlarmKit.AlarmManager.shared
        if !enabledEntries.isEmpty {
          try await ensureAuthorization(using: manager)
        }

        removeLegacyAlarmKitAlarms(using: manager)
        for id in Self.heavySleeperBackupIDs {
          try? manager.cancel(id: id)
        }
        var scheduled: [[String: Any]] = []

        for (kind, id) in Self.prayerAlarmIDs {
          let entry = validEntries.first { $0["id"] as? String == kind }
          let enabled = entry?["enabled"] as? Bool ?? false
          try? manager.cancel(id: id)
          guard enabled, let entry else { continue }

          let timestamp = entry["timestamp"] as? Double ?? 0
          let title = entry["title"] as? String ?? kind
          let date = Date(timeIntervalSince1970: timestamp)
          let heavySleeper = kind == "fajr"
            && (entry["heavySleeper"] as? Bool ?? false)
          let repeatButtonTitle = entry["repeatButtonTitle"] as? String
            ?? "Повторить через 3 минуты"
          let alarm = try await scheduleAlarm(
            at: date,
            title: title,
            kind: kind,
            id: id,
            heavySleeper: heavySleeper,
            repeatButtonTitle: repeatButtonTitle,
            using: manager
          )
          scheduled.append([
            "kind": kind,
            "id": alarm.id.uuidString,
            "nextTrigger": date.timeIntervalSince1970,
            "state": stateName(alarm.state),
          ])

          if heavySleeper {
            let requestedMinutes = (entry["backupMinutes"] as? [NSNumber])?
              .map(\.intValue) ?? [3, 6, 9]
            let backupMinutes = Array(requestedMinutes.prefix(
              Self.heavySleeperBackupIDs.count
            ))
            for (index, pair) in zip(
              Self.heavySleeperBackupIDs,
              backupMinutes
            ).enumerated() {
              let (backupID, minutes) = pair
              let backupDate = date.addingTimeInterval(
                TimeInterval(minutes * 60)
              )
              let backupTitle = "\(title) · \(index + 2)/\(backupMinutes.count + 1)"
              let backup = try await scheduleAlarm(
                at: backupDate,
                title: backupTitle,
                kind: "fajr_backup_\(index + 1)",
                id: backupID,
                heavySleeper: true,
                repeatButtonTitle: repeatButtonTitle,
                using: manager
              )
              scheduled.append([
                "kind": "fajr_backup_\(index + 1)",
                "id": backup.id.uuidString,
                "nextTrigger": backupDate.timeIntervalSince1970,
                "state": stateName(backup.state),
              ])
            }
          }
        }

        finish(
          result,
          value: [
            "success": true,
            "mode": "alarmKit",
            "scheduled": scheduled.count,
            "alarms": scheduled,
          ]
        )
      } catch {
        finish(result, with: error)
      }
    }
    #else
    if enabledEntries.isEmpty {
      finish(
        result,
        value: ["success": true, "mode": "alarmKit", "scheduled": 0]
      )
    } else {
      finish(result, with: BridgeError.alarmKitUnavailable)
    }
    #endif
  }

  private func scheduleTestAlarm(
    at date: Date,
    title: String,
    heavySleeper: Bool,
    repeatButtonTitle: String,
    backupMinutes requestedMinutes: [Int],
    result: @escaping FlutterResult
  ) {
    guard date.timeIntervalSinceNow > 0 else {
      finish(result, with: BridgeError.invalidDate)
      return
    }

    removeLegacyNotificationFallbacks()

    #if canImport(AlarmKit)
    guard #available(iOS 26.0, *) else {
      finish(result, with: BridgeError.alarmKitUnavailable)
      return
    }

    Task {
      do {
        let manager = AlarmKit.AlarmManager.shared
        try await ensureAuthorization(using: manager)
        let testIDs = [Self.testAlarmID] + Self.testHeavySleeperBackupIDs
        for id in testIDs {
          try? manager.cancel(id: id)
        }
        removeLegacyAlarmKitAlarms(using: manager)

        var scheduled: [[String: Any]] = []
        let primary = try await scheduleAlarm(
          at: date,
          title: title,
          kind: "test",
          id: Self.testAlarmID,
          heavySleeper: heavySleeper,
          repeatButtonTitle: repeatButtonTitle,
          using: manager
        )
        scheduled.append([
          "kind": "test",
          "id": primary.id.uuidString,
          "nextTrigger": date.timeIntervalSince1970,
          "state": stateName(primary.state),
        ])

        if heavySleeper {
          let backupMinutes = Array(requestedMinutes.prefix(
            Self.testHeavySleeperBackupIDs.count
          ))
          for (index, pair) in zip(
            Self.testHeavySleeperBackupIDs,
            backupMinutes
          ).enumerated() {
            let (backupID, minutes) = pair
            let backupDate = date.addingTimeInterval(TimeInterval(minutes * 60))
            let backup = try await scheduleAlarm(
              at: backupDate,
              title: "\(title) · \(index + 2)/\(backupMinutes.count + 1)",
              kind: "test_backup_\(index + 1)",
              id: backupID,
              heavySleeper: true,
              repeatButtonTitle: repeatButtonTitle,
              using: manager
            )
            scheduled.append([
              "kind": "test_backup_\(index + 1)",
              "id": backup.id.uuidString,
              "nextTrigger": backupDate.timeIntervalSince1970,
              "state": stateName(backup.state),
            ])
          }
        }

        finish(
          result,
          value: [
            "success": true,
            "mode": "alarmKit",
            "scheduled": scheduled.count,
            "alarms": scheduled,
          ]
        )
      } catch {
        finish(result, with: error)
      }
    }
    #else
    finish(result, with: BridgeError.alarmKitUnavailable)
    #endif
  }

  private func schedule(
    at date: Date,
    title: String,
    kind: String,
    id: UUID,
    result: @escaping FlutterResult
  ) {
    guard date.timeIntervalSinceNow > 0 else {
      finish(result, with: BridgeError.invalidDate)
      return
    }

    removeLegacyNotificationFallbacks()

    #if canImport(AlarmKit)
    guard #available(iOS 26.0, *) else {
      finish(result, with: BridgeError.alarmKitUnavailable)
      return
    }

    Task {
      do {
        let alarmManager = AlarmKit.AlarmManager.shared
        try await ensureAuthorization(using: alarmManager)
        try? alarmManager.cancel(id: id)
        removeLegacyAlarmKitAlarms(using: alarmManager)
        let alarm = try await scheduleAlarm(
          at: date,
          title: title,
          kind: kind,
          id: id,
          using: alarmManager
        )

        finish(
          result,
          value: [
            "success": true,
            "mode": "alarmKit",
            "id": alarm.id.uuidString,
            "nextTrigger": date.timeIntervalSince1970,
            "state": stateName(alarm.state),
          ]
        )
      } catch {
        finish(result, with: error)
      }
    }
    #else
    finish(result, with: BridgeError.alarmKitUnavailable)
    #endif
  }

  private func cancelFajrAlarm(result: @escaping FlutterResult) {
    removeLegacyNotificationFallbacks()

    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      do {
        let manager = AlarmKit.AlarmManager.shared
        try? manager.cancel(id: Self.fajrAlarmID)
        // Старые сборки использовали случайные UUID. При явном выключении
        // будильника безопасно удалить все AlarmKit-будильники Dauam.
        for alarm in try manager.alarms {
          try? manager.cancel(id: alarm.id)
        }
      } catch {
        finish(result, with: error)
        return
      }
    }
    #endif

    finish(
      result,
      value: [
        "success": true,
        "mode": "alarmKit",
        "cancelled": true,
      ]
    )
  }

  private func getPendingAlarms(result: @escaping FlutterResult) {
    removeLegacyNotificationFallbacks()

    #if canImport(AlarmKit)
    guard #available(iOS 26.0, *) else {
      finish(result, value: [])
      return
    }

    do {
      let alarms = try AlarmKit.AlarmManager.shared.alarms.map { alarm in
        var item: [String: Any] = [
          "id": alarm.id.uuidString,
          "state": stateName(alarm.state),
          "mode": "alarmKit",
        ]
        if case .fixed(let date)? = alarm.schedule {
          item["nextTrigger"] = date.timeIntervalSince1970
        }
        return item
      }
      finish(result, value: alarms)
    } catch {
      finish(result, with: error)
    }
    #else
    finish(result, value: [])
    #endif
  }

  private func removeLegacyNotificationFallbacks() {
    let center = UNUserNotificationCenter.current()
    center.getPendingNotificationRequests { requests in
      let identifiers = requests
        .map(\.identifier)
        .filter { $0.hasPrefix(Self.legacyNotificationPrefix) }
      center.removePendingNotificationRequests(withIdentifiers: identifiers)
      center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
  }

  #if canImport(AlarmKit)
  @available(iOS 26.0, *)
  private func ensureAuthorization(
    using manager: AlarmKit.AlarmManager
  ) async throws {
    let authorization: AlarmKit.AlarmManager.AuthorizationState
    switch manager.authorizationState {
    case .notDetermined:
      authorization = try await manager.requestAuthorization()
    case .authorized:
      authorization = .authorized
    case .denied:
      authorization = .denied
    @unknown default:
      authorization = .denied
    }
    guard authorization == .authorized else {
      throw BridgeError.authorizationDenied
    }
  }

  @available(iOS 26.0, *)
  private func scheduleAlarm(
    at date: Date,
    title: String,
    kind: String,
    id: UUID,
    heavySleeper: Bool = false,
    repeatButtonTitle: String = "Повторить через 3 минуты",
    using manager: AlarmKit.AlarmManager
  ) async throws -> Alarm {
    let titleResource = LocalizedStringResource(stringLiteral: title)
    let alert: AlarmPresentation.Alert
    let repeatButton = heavySleeper
      ? AlarmButton(
          text: LocalizedStringResource(stringLiteral: repeatButtonTitle),
          textColor: .white,
          systemImageName: "repeat"
        )
      : nil
    if #available(iOS 26.1, *) {
      alert = AlarmPresentation.Alert(
        title: titleResource,
        secondaryButton: repeatButton,
        secondaryButtonBehavior: heavySleeper ? .custom : nil
      )
    } else {
      let stopButton = AlarmButton(
        text: "Остановить",
        textColor: .white,
        systemImageName: "stop.fill"
      )
      alert = AlarmPresentation.Alert(
        title: titleResource,
        stopButton: stopButton,
        secondaryButton: repeatButton,
        secondaryButtonBehavior: heavySleeper ? .custom : nil
      )
    }

    let presentation = AlarmPresentation(alert: alert)
    let attributes = AlarmAttributes<DauamAlarmMetadata>(
      presentation: presentation,
      metadata: DauamAlarmMetadata(title: title, kind: kind),
      tintColor: .orange
    )
    let configuration = AlarmKit.AlarmManager.AlarmConfiguration.alarm(
      schedule: .fixed(date),
      attributes: attributes,
      stopIntent: heavySleeper
        ? DauamWakeUpConfirmedIntent(alarmID: id.uuidString)
        : nil,
      secondaryIntent: heavySleeper
        ? DauamRepeatAlarmIntent(alarmID: id.uuidString)
        : nil,
      sound: heavySleeper ? .named("DauamWake.caf") : .default
    )
    return try await manager.schedule(id: id, configuration: configuration)
  }

  /// Вызывается системным контролом остановки AlarmKit. Останавливает текущий
  /// сигнал и снимает все оставшиеся сигналы соответствующего теста/цикла.
  /// Следующий запуск приложения поставит уже завтрашнюю серию.
  @available(iOS 26.0, *)
  static func confirmWakeUp(alarmID: String) {
    let manager = AlarmKit.AlarmManager.shared
    guard let id = UUID(uuidString: alarmID) else { return }
    try? manager.stop(id: id)
    let testIDs = Set(testHeavySleeperBackupIDs).union([testAlarmID])
    let ids = testIDs.contains(id)
      ? testIDs
      : Set(heavySleeperBackupIDs).union([fajrAlarmID])
    for id in ids {
      try? manager.cancel(id: id)
    }
  }

  /// Останавливает только текущий сигнал. Следующий заранее поставленный
  /// резервный сигнал остаётся и повторит будильник через три минуты.
  @available(iOS 26.0, *)
  static func repeatAlarm(alarmID: String) {
    let manager = AlarmKit.AlarmManager.shared
    if let id = UUID(uuidString: alarmID) {
      try? manager.stop(id: id)
    }
  }

  @available(iOS 26.0, *)
  private func removeLegacyAlarmKitAlarms(
    using manager: AlarmKit.AlarmManager
  ) {
    guard let alarms = try? manager.alarms else { return }
    let currentIDs = Set(Self.prayerAlarmIDs.values)
      .union(Self.heavySleeperBackupIDs)
      .union(Self.testHeavySleeperBackupIDs)
      .union([Self.testAlarmID])
    for alarm in alarms where !currentIDs.contains(alarm.id) {
      try? manager.cancel(id: alarm.id)
    }
  }

  @available(iOS 26.0, *)
  private func stateName(_ state: Alarm.State) -> String {
    switch state {
    case .scheduled:
      return "scheduled"
    case .countdown:
      return "countdown"
    case .paused:
      return "paused"
    case .alerting:
      return "alerting"
    @unknown default:
      return "unknown"
    }
  }
  #endif

  private func finish(
    _ result: @escaping FlutterResult,
    value: Any
  ) {
    DispatchQueue.main.async {
      result(value)
    }
  }

  private func finish(
    _ result: @escaping FlutterResult,
    with error: Error
  ) {
    let code = (error as? BridgeError)?.flutterCode ?? "ALARM_SCHEDULE_FAILED"
    let message = (error as? LocalizedError)?.errorDescription
      ?? error.localizedDescription

    DispatchQueue.main.async {
      result(
        FlutterError(
          code: code,
          message: message,
          details: String(describing: error)
        )
      )
    }
  }
}

#if canImport(AlarmKit)
/// Системная остановка означает, что пользователь окончательно проснулся:
/// текущий и все оставшиеся резервные сигналы этого теста/цикла снимаются.
@available(iOS 26.0, *)
public struct DauamWakeUpConfirmedIntent: LiveActivityIntent {
  public static var title: LocalizedStringResource = "Остановить серию"
  public static var description = IntentDescription(
    "Отменяет оставшиеся резервные будильники Фаджра."
  )
  public static var openAppWhenRun: Bool = false

  @Parameter(title: "Alarm ID")
  public var alarmID: String

  public init(alarmID: String) {
    self.alarmID = alarmID
  }

  public init() {
    self.alarmID = ""
  }

  public func perform() async throws -> some IntentResult {
    AlarmManager.confirmWakeUp(alarmID: alarmID)
    return .result()
  }
}

/// Акцентная дополнительная кнопка не завершает усиленный цикл: она глушит
/// текущий сигнал, а следующий заранее поставленный резерв сработает через
/// три минуты. Это максимально близкая к snooze семантика, разрешённая
/// системным интерфейсом AlarmKit.
@available(iOS 26.0, *)
public struct DauamRepeatAlarmIntent: LiveActivityIntent {
  public static var title: LocalizedStringResource = "Повторить через 3 минуты"
  public static var description = IntentDescription(
    "Останавливает текущий сигнал и оставляет следующий резервный будильник."
  )
  public static var openAppWhenRun: Bool = false

  @Parameter(title: "Alarm ID")
  public var alarmID: String

  public init(alarmID: String) {
    self.alarmID = alarmID
  }

  public init() {
    self.alarmID = ""
  }

  public func perform() async throws -> some IntentResult {
    AlarmManager.repeatAlarm(alarmID: alarmID)
    return .result()
  }
}
#endif
