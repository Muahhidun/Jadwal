import Flutter
import CoreLocation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var compassCapabilityChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    WatchSyncManager.shared.activate()

    if let url = launchOptions?[.url] as? URL, url.scheme == "dauam" {
      LiveActivityManager.handleDeepLink(url.absoluteString)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    LiveActivityManager.stopAllActivities()
    super.applicationWillTerminate(application)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    LiveActivityManager.cleanupExpiredPrayerActivities()
    WatchSyncManager.shared.refreshFromSharedStore()
    super.applicationDidBecomeActive(application)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "dauam" {
      LiveActivityManager.handleDeepLink(url.absoluteString)
    }
    return super.application(app, open: url, options: options) || url.scheme == "dauam"
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)

    if let registrar = registry.registrar(forPlugin: "LiveActivityManager") {
      LiveActivityManager.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "WidgetDataManager") {
      WidgetDataManager.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "AlarmManager") {
      AlarmManager.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZikrSpeechManager") {
      ZikrSpeechManager.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "CompassCapability") {
      let channel = FlutterMethodChannel(
        name: "kz.dauam/compass_capability",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "isCompassAvailable" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(CLLocationManager.headingAvailable())
      }
      compassCapabilityChannel = channel
    }
  }
}
