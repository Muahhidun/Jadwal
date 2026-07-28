import Foundation
import WatchConnectivity

/// Доставляет тот же JSON-снимок, который использует WidgetKit, на Apple Watch.
///
/// App Group не переносит данные между двумя физическими устройствами, поэтому
/// iPhone хранит снимок локально и передаёт его через WatchConnectivity.
final class WatchSyncManager: NSObject, WCSessionDelegate {
  static let shared = WatchSyncManager()

  private static let snapshotMessageKey = "snapshot"
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

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }
}
