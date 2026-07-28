import SwiftUI

@main
struct DauamWatchApp: App {
  @StateObject private var model = DauamWatchModel()

  init() {
    WatchConnectivityReceiver.shared.activate()
  }

  var body: some Scene {
    WindowGroup {
      DauamWatchRootView()
        .environmentObject(model)
    }
  }
}

@MainActor
final class DauamWatchModel: ObservableObject {
  @Published private(set) var snapshot = DauamWatchSnapshotStore.load()

  init() {
    NotificationCenter.default.addObserver(
      forName: DauamWatchConstants.snapshotChanged,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.snapshot = DauamWatchSnapshotStore.load()
      }
    }
  }
}
