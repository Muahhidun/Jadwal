import Foundation

@main
enum SnapshotChecks {
  struct Failure: Error, CustomStringConvertible {
    let description: String
  }

  static func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure(description: message) }
  }

  static func main() {
    let suite = "kz.dauam.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let format = ISO8601DateFormatter()
    let today = format.date(from: "2026-10-23T12:00:00Z")!
    let tomorrow = format.date(from: "2026-10-24T00:00:00Z")!
    let sample = DauamWatchSnapshot(
      schemaVersion: 2, generatedAt: today.timeIntervalSince1970,
      language: "ru", city: "Алматы", dateLabel: "Пятница · вчерашняя дата",
      prayers: [
        .init(id: "asr", title: "Аср", time: "16:00",
              timestamp: today.addingTimeInterval(4 * 3_600).timeIntervalSince1970,
              isTomorrow: false),
        .init(id: "fajr", title: "Фаджр", time: "05:00",
              timestamp: tomorrow.addingTimeInterval(5 * 3_600).timeIntervalSince1970,
              isTomorrow: true),
      ],
      tasks: [.init(id: "kahf", title: "Пятничное дело", done: true)],
      taskDone: 1, taskTotal: 1, lat: 43.2389, lng: 76.8897
    )
    let name = CommandLine.arguments.dropFirst().first ?? ""
    do {
      switch name {
      case "empty":
        let value = DauamWatchSnapshotStore.load(defaults: defaults)
        try expect(value.prayers.isEmpty && value.tasks.isEmpty && value.taskDone == 0,
                   "Missing snapshot must not become real prayers or completed tasks")
        try expect(value.city.isEmpty, "Missing snapshot must not invent a city")
      case "broken":
        defaults.set("{broken", forKey: DauamWatchConstants.snapshotKey)
        let value = DauamWatchSnapshotStore.load(defaults: defaults)
        try expect(value.prayers.isEmpty && value.tasks.isEmpty,
                   "Broken snapshot must not become demo data")
      case "unsupported":
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as! [String: Any]
        json["schemaVersion"] = 999
        defaults.set(String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8),
                     forKey: DauamWatchConstants.snapshotKey)
        try expect(DauamWatchSnapshotStore.load(defaults: defaults).prayers.isEmpty,
                   "Unsupported data must be rejected")
      case "stale":
        let value = sample.projected(at: tomorrow)
        try expect(value.tasks.isEmpty && value.taskDone == 0 && value.taskTotal == 0,
                   "Friday completion must not survive into Saturday")
        try expect(value.prayers.count == sample.prayers.count && value.nextEvent(after: tomorrow) != nil,
                   "Real future prayer times must remain usable")
      case "date":
        let value = sample.projected(at: tomorrow)
        try expect(value.dateLabel != sample.dateLabel && !value.dateLabel.isEmpty,
                   "Yesterday's date must not be reused")
      case "same-day":
        try expect(sample.projected(at: today.addingTimeInterval(60)) == sample,
                   "Today's tasks and check marks must remain unchanged")
      case "midnight":
        try expect(sample.timelineDates(from: today).contains(tomorrow),
                   "Timeline must invalidate daily state at midnight, not just at Fajr")
      case "empty-timeline":
        let value = DauamWatchSnapshotStore.load(defaults: defaults)
        try expect(value.timelineDates(from: today).contains(tomorrow),
                   "Even an empty/expired schedule must have a next-day refresh")
      case "legacy":
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as! [String: Any]
        json["schemaVersion"] = 1
        json.removeValue(forKey: "lat")
        json.removeValue(forKey: "lng")
        defaults.set(String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8),
                     forKey: DauamWatchConstants.snapshotKey)
        let value = DauamWatchSnapshotStore.load(defaults: defaults)
        try expect(value.city == "Алматы" && value.tasks == sample.tasks,
                   "Existing schema 1 user data must remain readable")
      case "expired":
        let later = tomorrow.addingTimeInterval(30 * 86_400)
        let value = sample.projected(at: later)
        try expect(value.nextEvent(after: later) == nil && value.tasks.isEmpty && !value.hasCurrentTasks(at: later),
                   "Expired real data must not be replaced with new demo events or old check marks")
      case "grace-boundary":
        let asr = sample.prayers[0].date
        try expect(sample.timelineDates(from: asr.addingTimeInterval(300))
          .contains(asr.addingTimeInterval(601)),
                   "An azan grace end is needed even when its start is already in the past")
      case "save-validation":
        let valid = String(data: try JSONEncoder().encode(sample), encoding: .utf8)!
        try expect(DauamWatchSnapshotStore.save(json: valid, defaults: defaults), "Valid data must be saved")
        try expect(!DauamWatchSnapshotStore.save(json: "{broken", defaults: defaults), "Broken data must be rejected")
        try expect(defaults.string(forKey: DauamWatchConstants.snapshotKey) == valid,
                   "An invalid update must not destroy the user's last valid snapshot")
      case "heading-missing":
        try expect(DauamWatchQiblaPresentation.arrowAngle(bearing: 235, heading: nil, available: true) == nil,
                   "Unknown heading is not north: do not draw a directional arrow")
      case "heading-unavailable":
        try expect(DauamWatchQiblaPresentation.arrowAngle(bearing: 235, heading: 10, available: false) == nil,
                   "A denied/unavailable compass must not draw an old arrow")
      case "heading-invalid":
        try expect(DauamWatchQiblaPresentation.arrowAngle(bearing: 235, heading: -.infinity, available: true) == nil,
                   "Non-finite sensor data must not draw an arrow")
        try expect(DauamWatchQiblaPresentation.arrowAngle(bearing: 235, heading: -1, available: true) == nil,
                   "Invalid heading must not become a measured direction")
      case "heading-ready":
        let result = DauamWatchQiblaPresentation.arrowAngle(bearing: 10, heading: 350, available: true)
        try expect(result.map { abs($0 - 20) < 0.001 } ?? false,
                   "A valid compass must show the relative bearing across north")
      default:
        throw Failure(description: "Unknown test: \(name)")
      }
      print("PASS \(name)")
    } catch {
      print("FAIL \(name): \(error)")
      exit(1)
    }
  }
}
