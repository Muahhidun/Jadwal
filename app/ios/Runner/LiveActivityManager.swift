import ActivityKit
import Flutter
import UIKit

public class LiveActivityManager: NSObject, FlutterPlugin {
  private var methodChannel: FlutterMethodChannel?
  private static weak var activeInstance: LiveActivityManager?
  private static var pendingDeepLink: String?
  @MainActor private static var prayerExpiryTasks = [String: Task<Void, Never>]()

  @objc public static func handleDeepLink(_ rawValue: String) {
    pendingDeepLink = rawValue
    activeInstance?.methodChannel?.invokeMethod("onOpenDeepLink", arguments: rawValue)
  }

  @available(iOS 16.1, *)
  private static func state(
    of activity: Activity<JadwalActivityAttributes>
  ) -> JadwalActivityAttributes.ContentState {
    if #available(iOS 16.2, *) {
      return activity.content.state
    }
    return activity.contentState
  }

  private static func staleDate(
    mode: String,
    targetTimestamp: Double
  ) -> Date? {
    guard mode == "prayer", targetTimestamp > 0 else { return nil }
    return Date(timeIntervalSince1970: targetTimestamp)
  }

  /// Планирует явное завершение молитвенной Live Activity на границе намаза.
  /// `staleDate` сам по себе лишь помечает данные устаревшими и не удаляет
  /// системную карточку. Отдельная задача закрывает её, пока процесс приложения
  /// ещё получает время выполнения; повторное обновление заменяет старый таймер.
  @available(iOS 16.1, *)
  @MainActor private static func observePrayerExpiry(
    _ activity: Activity<JadwalActivityAttributes>
  ) {
    let content = state(of: activity)
    guard content.mode == "prayer" else { return }
    prayerExpiryTasks[activity.id]?.cancel()

    prayerExpiryTasks[activity.id] = Task { @MainActor in
      let delay = max(0, content.targetTimestamp - Date.now.timeIntervalSince1970)
      do {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      } catch {
        return
      }

      guard !Task.isCancelled else { return }
      let latest = state(of: activity)
      if latest.mode == "prayer"
        && latest.targetTimestamp <= Date.now.timeIntervalSince1970 + 0.5
      {
        await activity.end(dismissalPolicy: .immediate)
      }
      prayerExpiryTasks[activity.id] = nil
    }
  }

  @objc public static func stopAllActivities() {
    guard #available(iOS 16.1, *) else { return }
    Task { @MainActor in
      for activity in Activity<JadwalActivityAttributes>.activities {
        prayerExpiryTasks[activity.id]?.cancel()
        prayerExpiryTasks[activity.id] = nil
        await activity.end(dismissalPolicy: .immediate)
      }
    }
  }

  /// Удаляет молитвенные активности, цель которых уже наступила. Вызывается
  /// при регистрации плагина и при каждом возвращении приложения на экран.
  @objc public static func cleanupExpiredPrayerActivities() {
    guard #available(iOS 16.1, *) else { return }
    Task { @MainActor in
      let now = Date.now.timeIntervalSince1970
      for activity in Activity<JadwalActivityAttributes>.activities {
        let content = state(of: activity)
        if content.mode == "prayer" && content.targetTimestamp <= now {
          prayerExpiryTasks[activity.id]?.cancel()
          prayerExpiryTasks[activity.id] = nil
          await activity.end(dismissalPolicy: .immediate)
        } else if content.mode == "prayer" {
          observePrayerExpiry(activity)
        }
      }
    }
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "kz.dauam/live_activity", binaryMessenger: registrar.messenger())
    let instance = LiveActivityManager()
    activeInstance = instance
    instance.methodChannel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)

    NotificationCenter.default.addObserver(instance, selector: #selector(instance.handleNextZikr), name: NSNotification.Name("ZikrNextPressed"), object: nil)
    NotificationCenter.default.addObserver(instance, selector: #selector(instance.handlePrevZikr), name: NSNotification.Name("ZikrPrevPressed"), object: nil)
    NotificationCenter.default.addObserver(instance, selector: #selector(instance.handleTickZikr), name: NSNotification.Name("ZikrTickPressed"), object: nil)
    cleanupExpiredPrayerActivities()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startActivity":
      if let args = call.arguments as? [String: Any] {
        startActivity(args: args, result: result)
      } else {
        result(FlutterError(code: "INVALID_ARGS", message: "Arguments missing", details: nil))
      }
    case "updateActivity":
      if let args = call.arguments as? [String: Any] {
        updateActivity(args: args, result: result)
      } else {
        result(FlutterError(code: "INVALID_ARGS", message: "Arguments missing", details: nil))
      }
    case "stopActivity":
      stopActivity(result: result)
    case "stopPrayerActivity":
      stopPrayerActivity(result: result)
    case "isSupported":
      if #available(iOS 16.1, *) {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        result(enabled)
      } else {
        result(false)
      }
    case "getPendingDeepLink":
      result(Self.pendingDeepLink)
      Self.pendingDeepLink = nil
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc private func handleNextZikr() {
    methodChannel?.invokeMethod("onZikrNext", arguments: nil)
  }

  @objc private func handlePrevZikr() {
    methodChannel?.invokeMethod("onZikrPrev", arguments: nil)
  }

  @objc private func handleTickZikr() {
    methodChannel?.invokeMethod("onZikrTick", arguments: nil)
  }

  private func startActivity(args: [String: Any], result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      result(FlutterError(code: "UNSUPPORTED", message: "iOS 16.1+ required", details: nil))
      return
    }

    let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
    if !enabled {
      result(FlutterError(code: "DISABLED", message: "Live Activities disabled in iOS Settings", details: nil))
      return
    }

    let mode = args["mode"] as? String ?? "prayer"
    let title = args["title"] as? String ?? ""
    let subtitle = args["subtitle"] as? String ?? ""
    let targetTimestamp = args["targetTimestamp"] as? Double ?? 0.0
    let counterCurrent = args["counterCurrent"] as? Int ?? 0
    let counterTotal = args["counterTotal"] as? Int ?? 0
    let zikrArabic = args["zikrArabic"] as? String ?? ""
    let zikrTranslation = args["zikrTranslation"] as? String ?? ""
    let collectionId = args["collectionId"] as? String ?? ""
    let currentIndex = args["currentIndex"] as? Int ?? 0

    if mode == "prayer" && targetTimestamp <= Date.now.timeIntervalSince1970 {
      stopPrayerActivity(result: result)
      return
    }

    let state = JadwalActivityAttributes.ContentState(
      mode: mode,
      title: title,
      subtitle: subtitle,
      targetTimestamp: targetTimestamp,
      counterCurrent: counterCurrent,
      counterTotal: counterTotal,
      zikrArabic: zikrArabic,
      zikrTranslation: zikrTranslation,
      collectionId: collectionId,
      currentIndex: currentIndex
    )

    let attributes = JadwalActivityAttributes(name: "DauamSession")
    let expiresAt = Self.staleDate(
      mode: mode,
      targetTimestamp: targetTimestamp
    )

    Task { @MainActor in
      let activeActivities = Activity<JadwalActivityAttributes>.activities
      // Чтение зикров важнее фонового приближения намаза: молитвенная
      // активность не должна перезаписывать открытую сессию чтения.
      if mode == "prayer" && activeActivities.contains(where: {
        Self.state(of: $0).mode == "zikr"
      }) {
        result("ZIKR_ACTIVE")
        return
      }

      if mode == "zikr" {
        for activity in activeActivities where Self.state(of: activity).mode == "prayer" {
          Self.prayerExpiryTasks[activity.id]?.cancel()
          Self.prayerExpiryTasks[activity.id] = nil
          await activity.end(dismissalPolicy: .immediate)
        }
      }

      if let currentActivity = activeActivities.first(where: {
        Self.state(of: $0).mode == mode
      }) {
        if #available(iOS 16.2, *) {
          await currentActivity.update(
            ActivityContent(state: state, staleDate: expiresAt)
          )
        } else {
          await currentActivity.update(using: state)
        }
        if mode == "prayer" {
          Self.observePrayerExpiry(currentActivity)
        }
        result(currentActivity.id)
        return
      }

      if #available(iOS 16.2, *) {
        do {
          let activity = try Activity<JadwalActivityAttributes>.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: expiresAt),
            pushType: nil
          )
          if mode == "prayer" {
            Self.observePrayerExpiry(activity)
          }
          result(activity.id)
        } catch {
          result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
        }
      } else {
        do {
          let activity = try Activity<JadwalActivityAttributes>.request(
            attributes: attributes,
            contentState: state,
            pushType: nil
          )
          if mode == "prayer" {
            Self.observePrayerExpiry(activity)
          }
          result(activity.id)
        } catch {
          result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func updateActivity(args: [String: Any], result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      result(nil)
      return
    }

    let mode = args["mode"] as? String ?? "prayer"
    let title = args["title"] as? String ?? ""
    let subtitle = args["subtitle"] as? String ?? ""
    let targetTimestamp = args["targetTimestamp"] as? Double ?? 0.0
    let counterCurrent = args["counterCurrent"] as? Int ?? 0
    let counterTotal = args["counterTotal"] as? Int ?? 0
    let zikrArabic = args["zikrArabic"] as? String ?? ""
    let zikrTranslation = args["zikrTranslation"] as? String ?? ""
    let collectionId = args["collectionId"] as? String ?? ""
    let currentIndex = args["currentIndex"] as? Int ?? 0

    let state = JadwalActivityAttributes.ContentState(
      mode: mode,
      title: title,
      subtitle: subtitle,
      targetTimestamp: targetTimestamp,
      counterCurrent: counterCurrent,
      counterTotal: counterTotal,
      zikrArabic: zikrArabic,
      zikrTranslation: zikrTranslation,
      collectionId: collectionId,
      currentIndex: currentIndex
    )
    let expiresAt = Self.staleDate(
      mode: mode,
      targetTimestamp: targetTimestamp
    )

    Task { @MainActor in
      for activity in Activity<JadwalActivityAttributes>.activities {
        guard Self.state(of: activity).mode == mode else { continue }
        if #available(iOS 16.2, *) {
          await activity.update(
            ActivityContent(state: state, staleDate: expiresAt)
          )
        } else {
          await activity.update(using: state)
        }
        if mode == "prayer" {
          Self.observePrayerExpiry(activity)
        }
      }
      result(true)
    }
  }

  private func stopActivity(result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      result(true)
      return
    }

    Task { @MainActor in
      for activity in Activity<JadwalActivityAttributes>.activities {
        Self.prayerExpiryTasks[activity.id]?.cancel()
        Self.prayerExpiryTasks[activity.id] = nil
        await activity.end(dismissalPolicy: .immediate)
      }
      result(true)
    }
  }

  private func stopPrayerActivity(result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      result(true)
      return
    }

    Task { @MainActor in
      for activity in Activity<JadwalActivityAttributes>.activities {
        if Self.state(of: activity).mode == "prayer" {
          Self.prayerExpiryTasks[activity.id]?.cancel()
          Self.prayerExpiryTasks[activity.id] = nil
          await activity.end(dismissalPolicy: .immediate)
        }
      }
      result(true)
    }
  }
}
