import Foundation
import WatchConnectivity

/// Доставляет тот же JSON-снимок, который использует WidgetKit, на Apple Watch.
///
/// App Group не переносит данные между двумя физическими устройствами, поэтому
/// iPhone хранит снимок локально и передаёт его через WatchConnectivity.
final class WatchSyncManager: NSObject, WCSessionDelegate {
  static let shared = WatchSyncManager()

  private static let snapshotMessageKey = "snapshot"
  private static let snapshotRequestKey = "requestSnapshot"
  private var pendingSnapshot: String?

  private override init() {
    super.init()
  }

  func activate() {
    guard WCSession.isSupported() else { return }
    if
      let defaults = UserDefaults(suiteName: WidgetDataManager.appGroup),
      let json = defaults.string(forKey: WidgetDataManager.snapshotKey)
    {
      pendingSnapshot = json
    }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  func push(snapshot json: String) {
    pendingSnapshot = json
    deliverIfPossible()
  }

  /// Повторно читает самый свежий снимок из App Group и отправляет его часам.
  /// Это важно после переустановки Watch-приложения: его локальный контейнер
  /// пуст, хотя iPhone и WidgetKit уже располагают актуальными данными.
  func refreshFromSharedStore() {
    if
      let defaults = UserDefaults(suiteName: WidgetDataManager.appGroup),
      let json = defaults.string(forKey: WidgetDataManager.snapshotKey)
    {
      pendingSnapshot = json
    }
    deliverIfPossible()
  }

  private func latestSnapshot() -> String? {
    if let pendingSnapshot {
      return pendingSnapshot
    }
    return UserDefaults(suiteName: WidgetDataManager.appGroup)?
      .string(forKey: WidgetDataManager.snapshotKey)
  }

  private func deliverIfPossible() {
    guard
      WCSession.isSupported(),
      WCSession.default.activationState == .activated,
      let json = pendingSnapshot
    else {
      return
    }

    let payload = [Self.snapshotMessageKey: json]
    do {
      try WCSession.default.updateApplicationContext(payload)
      pendingSnapshot = nil
    } catch {
      // applicationContext сохранит только самый свежий снимок; следующая
      // синхронизация Flutter повторит отправку без влияния на основной экран.
    }

    if WCSession.default.isReachable {
      WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    deliverIfPossible()
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionWatchStateDidChange(_ session: WCSession) {
    refreshFromSharedStore()
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    if session.isReachable {
      refreshFromSharedStore()
    }
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    guard message[Self.snapshotRequestKey] as? Bool == true else { return }
    refreshFromSharedStore()
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    guard message[Self.snapshotRequestKey] as? Bool == true else {
      replyHandler([:])
      return
    }
    if let json = latestSnapshot() {
      replyHandler([Self.snapshotMessageKey: json])
    } else {
      replyHandler([:])
    }
  }

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }
}
