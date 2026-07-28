import Flutter
import Foundation
import WidgetKit

/// Мост Flutter → WidgetKit.
public final class WidgetDataManager: NSObject, FlutterPlugin {
  static let appGroup = "group.kz.dauam.shared"
  static let snapshotKey = "widget_snapshot_v1"
  static var channel: FlutterMethodChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kz.dauam/widgets",
      binaryMessenger: registrar.messenger()
    )
    self.channel = channel
    registrar.addMethodCallDelegate(WidgetDataManager(), channel: channel)
  }

  public static func notifyTarget(_ target: String) {
    let defaults = UserDefaults(suiteName: appGroup)
    defaults?.set(target, forKey: "pending_intent_target")
    defaults?.synchronize()
    DispatchQueue.main.async {
      channel?.invokeMethod("onSiriTargetReceived", arguments: target)
    }
  }

  public func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    if call.method == "getPendingIntentTarget" {
      let defaults = UserDefaults(suiteName: Self.appGroup)
      let target = defaults?.string(forKey: "pending_intent_target")
      if target != nil {
        defaults?.removeObject(forKey: "pending_intent_target")
        defaults?.synchronize()
      }
      result(target)
      return
    }

    guard call.method == "saveSnapshot" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let json = call.arguments as? String else {
      result(
        FlutterError(
          code: "INVALID_WIDGET_SNAPSHOT",
          message: "Expected a JSON string.",
          details: nil
        )
      )
      return
    }
    guard let defaults = UserDefaults(suiteName: Self.appGroup) else {
      result(
        FlutterError(
          code: "APP_GROUP_UNAVAILABLE",
          message: "The Dauam App Group is unavailable.",
          details: nil
        )
      )
      return
    }

    defaults.set(json, forKey: Self.snapshotKey)
    defaults.synchronize()
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }
    WatchSyncManager.shared.push(snapshot: json)
    result(nil)
  }
}
