#if canImport(AlarmKit)
import AlarmKit
import SwiftUI

@available(iOS 26.0, *)
struct DauamAlarmMetadata: AlarmMetadata {
  var title: String
  var kind: String
}
#endif

/// Мост Flutter → AlarmKit для настоящего системного будильника Фаджра.
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

    case "testFajrAlarm":
      let args = call.arguments as? [String: Any]
      let seconds = max(args?["seconds"] as? Double ?? 10, 1)
      let title = args?["title"] as? String ?? "Фаджр (Тест)"
      schedule(
        at: Date().addingTimeInterval(seconds),
        title: title,
        kind: "test",
        id: Self.testAlarmID,
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
        let authorization: AlarmKit.AlarmManager.AuthorizationState

        switch alarmManager.authorizationState {
        case .notDetermined:
          authorization = try await alarmManager.requestAuthorization()
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

        // Один стабильный ID для обычного Фаджра и отдельный — для теста.
        // Это позволяет тестировать будильник, не удаляя ежедневный.
        try? alarmManager.cancel(id: id)
        removeLegacyAlarmKitAlarms(using: alarmManager)

        let titleResource = LocalizedStringResource(stringLiteral: title)
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
          alert = AlarmPresentation.Alert(title: titleResource)
        } else {
          let stopButton = AlarmButton(
            text: "Остановить",
            textColor: .white,
            systemImageName: "stop.fill"
          )
          alert = AlarmPresentation.Alert(
            title: titleResource,
            stopButton: stopButton
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
          attributes: attributes
        )

        let alarm = try await alarmManager.schedule(
          id: id,
          configuration: configuration
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
  private func removeLegacyAlarmKitAlarms(
    using manager: AlarmKit.AlarmManager
  ) {
    guard let alarms = try? manager.alarms else { return }
    let currentIDs = Set([Self.fajrAlarmID, Self.testAlarmID])
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
