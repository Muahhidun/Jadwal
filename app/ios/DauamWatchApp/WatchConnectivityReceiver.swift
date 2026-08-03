import Foundation
import WatchConnectivity
import WidgetKit

final class WatchConnectivityReceiver: NSObject, WCSessionDelegate {
  static let shared = WatchConnectivityReceiver()
  private static let snapshotRequestKey = "requestSnapshot"

  private override init() {
    super.init()
  }

  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  private func accept(_ payload: [String: Any]) {
    guard
      let json = payload[DauamWatchConstants.snapshotMessageKey] as? String,
      DauamWatchSnapshotStore.save(json: json)
    else {
      return
    }
    WidgetCenter.shared.reloadAllTimelines()
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: DauamWatchConstants.snapshotChanged, object: nil)
    }
  }

  private func requestLatestSnapshot(from session: WCSession) {
    guard session.activationState == .activated, session.isReachable else { return }
    session.sendMessage(
      [Self.snapshotRequestKey: true],
      replyHandler: { [weak self] payload in
        self?.accept(payload)
      },
      errorHandler: nil
    )
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if activationState == .activated {
      accept(session.receivedApplicationContext)
      requestLatestSnapshot(from: session)
    }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    requestLatestSnapshot(from: session)
  }

  func session(
    _ session: WCSession,
    didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    accept(applicationContext)
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    accept(message)
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    accept(message)
    replyHandler(["accepted": true])
  }
}
