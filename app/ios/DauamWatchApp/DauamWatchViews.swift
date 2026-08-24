import CoreLocation
import SwiftUI

private extension Color {
  init(rgb: UInt, opacity: Double = 1) {
    self.init(
      .sRGB,
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255,
      opacity: opacity
    )
  }
}

private struct DauamWatchBackground: View {
  let snapshot: DauamWatchSnapshot

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      let palette = DauamWatchPalette.resolve(snapshot: snapshot, at: context.date)
      LinearGradient(
        colors: [Color(rgb: palette.top), Color(rgb: palette.bottom)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()
    }
  }
}

struct DauamWatchRootView: View {
  @EnvironmentObject private var model: DauamWatchModel
  @State private var selection: Int

  init() {
    let arguments = ProcessInfo.processInfo.arguments
    let page: Int
    if let index = arguments.firstIndex(of: "-watchPage"),
       arguments.indices.contains(index + 1),
       let value = Int(arguments[index + 1]) {
      page = min(3, max(0, value))
    } else {
      page = 0
    }
    _selection = State(initialValue: page)
  }

  var body: some View {
    TabView(selection: $selection) {
      DauamWatchNextView(snapshot: model.snapshot)
        .tag(0)
      DauamWatchScheduleView(snapshot: model.snapshot)
        .tag(1)
      DauamWatchTasksView(snapshot: model.snapshot)
        .tag(2)
      DauamWatchQiblaView(snapshot: model.snapshot)
        .tag(3)
    }
    .tabViewStyle(.verticalPage(transitionStyle: .blur))
  }
}

private struct DauamWatchNextView: View {
  let snapshot: DauamWatchSnapshot

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let called = snapshot.justCalledPrayer(at: context.date)
      let next = snapshot.nextEvent(after: context.date)
      let currentPrayer = called ?? next
      let palette = DauamWatchPalette.resolve(snapshot: snapshot, at: context.date)
      let primary = palette.darkText ? Color(rgb: 0x101F2A) : Color(rgb: 0xF8F4EA)
      let secondary = primary.opacity(0.68)
      let accent = Color(rgb: palette.accent)

      ZStack {
        DauamWatchBackground(snapshot: snapshot)
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("دوام")
              .font(.system(size: 16, weight: .bold, design: .serif))
              .foregroundStyle(accent)
            Spacer()
            if let currentPrayer {
              HStack(spacing: 3) {
                Image(systemName: currentPrayer.symbol)
                  .font(.system(size: 10, weight: .semibold))
                Text(currentPrayer.time)
                  .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
              }
              .foregroundStyle(secondary)
            }
          }

          Spacer(minLength: 0)

          if let called {
            VStack(spacing: 2) {
              Text(snapshot.isKazakh ? "АЗАННАН КЕЙІН" : "ПОСЛЕ АЗАНА")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
              Text(called.date, style: .timer)
                .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            }
            .frame(maxWidth: .infinity, alignment: .center)
          } else if let next {
            VStack(spacing: 2) {
              Text(snapshot.until(next, uppercase: true))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
              Text(next.date, style: .timer)
                .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText(countsDown: true))
            }
            .frame(maxWidth: .infinity, alignment: .center)
          } else {
            Text(snapshot.openPhoneTitle)
              .font(.system(size: 14, weight: .semibold, design: .rounded))
              .foregroundStyle(primary)
              .multilineTextAlignment(.center)
              .frame(maxWidth: .infinity)
          }

          Spacer(minLength: 0)

          HStack {
            HStack(spacing: 3) {
              Image(systemName: "location.fill")
                .font(.system(size: 8, weight: .semibold))
              Text(snapshot.city)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(snapshot.dateLabel)
              .font(.system(size: 10, weight: .medium, design: .rounded))
              .lineLimit(1)
              .minimumScaleFactor(0.72)
          }
          .foregroundStyle(secondary)
          .privacySensitive()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
      }
    }
  }
}

private struct DauamWatchScheduleView: View {
  let snapshot: DauamWatchSnapshot

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let next = snapshot.nextEvent(after: context.date)
      let palette = DauamWatchPalette.resolve(snapshot: snapshot, at: context.date)
      let primary = palette.darkText ? Color(rgb: 0x101F2A) : Color(rgb: 0xF8F4EA)
      let secondary = primary.opacity(0.62)
      let accent = Color(rgb: palette.accent)

      ZStack {
        DauamWatchBackground(snapshot: snapshot)
        VStack(alignment: .leading, spacing: 4) {
          Text(snapshot.scheduleTitle)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(primary)

          ForEach(snapshot.prayers(on: context.date)) { prayer in
            HStack(spacing: 6) {
              Image(systemName: prayer.symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 16)
              Text(prayer.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
              Spacer(minLength: 4)
              Text(prayer.time)
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
            }
            .foregroundStyle(prayer.id == next?.id ? accent : primary)
            .padding(.horizontal, 8)
            .frame(height: 23)
            .background(
              prayer.id == next?.id ? accent.opacity(0.14) : primary.opacity(0.07),
              in: RoundedRectangle(cornerRadius: 9)
            )
          }

          Text(snapshot.dateLabel)
            .font(.system(size: 8.5, weight: .medium, design: .rounded))
            .foregroundStyle(secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
      }
    }
  }
}

private struct DauamWatchTasksView: View {
  let snapshot: DauamWatchSnapshot

  private var progress: Double {
    guard snapshot.taskTotal > 0 else { return 0 }
    return min(1, max(0, Double(snapshot.taskDone) / Double(snapshot.taskTotal)))
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      let palette = DauamWatchPalette.resolve(snapshot: snapshot, at: context.date)
      let primary = palette.darkText ? Color(rgb: 0x101F2A) : Color(rgb: 0xF8F4EA)
      let accent = Color(rgb: palette.accent)

      ZStack {
        DauamWatchBackground(snapshot: snapshot)
        ScrollView {
          VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
              ZStack {
                Circle()
                  .stroke(primary.opacity(0.14), lineWidth: 5)
                Circle()
                  .trim(from: 0, to: progress)
                  .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                  .rotationEffect(.degrees(-90))
                Text("\(snapshot.taskDone)/\(snapshot.taskTotal)")
                  .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                  .foregroundStyle(primary)
              }
              .frame(width: 48, height: 48)

              VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.tasksTitle)
                  .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(snapshot.city)
                  .font(.system(size: 9, weight: .medium, design: .rounded))
                  .opacity(0.62)
                  .lineLimit(1)
              }
              .foregroundStyle(primary)
            }

            if snapshot.tasks.isEmpty {
              Text(snapshot.noTasksTitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(primary.opacity(0.7))
            } else {
              ForEach(snapshot.tasks) { task in
                HStack(spacing: 7) {
                  Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.done ? accent : primary.opacity(0.5))
                  Text(task.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(primary.opacity(task.done ? 0.58 : 1))
                    .lineLimit(2)
                  Spacer(minLength: 0)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
              }
            }
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
        }
      }
    }
  }
}

@MainActor
private final class DauamWatchCompass: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
  @Published private(set) var heading: CLLocationDirection?
  @Published private(set) var coordinate: CLLocationCoordinate2D?
  @Published private(set) var isAvailable = CLLocationManager.headingAvailable()

  private let manager = CLLocationManager()
  private var isActive = false

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.headingFilter = 1
  }

  func start() {
    isActive = true
    guard CLLocationManager.headingAvailable() else {
      isAvailable = false
      return
    }

    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      beginUpdates()
    default:
      isAvailable = false
    }
  }

  func stop() {
    isActive = false
    manager.stopUpdatingHeading()
    manager.stopUpdatingLocation()
  }

  private func beginUpdates() {
    guard isActive else { return }
    isAvailable = true
    manager.startUpdatingLocation()
    manager.startUpdatingHeading()
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus == .authorizedAlways ||
        manager.authorizationStatus == .authorizedWhenInUse {
      beginUpdates()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    if let coordinate = locations.last?.coordinate {
      self.coordinate = coordinate
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    guard newHeading.headingAccuracy >= 0 else { return }
    let raw = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    guard let previous = heading else {
      heading = raw
      return
    }

    // Сглаживаем по кратчайшей дуге, чтобы переход 359° → 0° не вращал
    // стрелку через весь круг.
    let delta = (raw - previous + 540).truncatingRemainder(dividingBy: 360) - 180
    heading = (previous + delta * 0.28 + 360).truncatingRemainder(dividingBy: 360)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // Последнее валидное направление остаётся на экране; Core Location сам
    // продолжит доставку после временного сбоя датчика.
  }
}

private struct DauamWatchQiblaView: View {
  let snapshot: DauamWatchSnapshot
  @StateObject private var compass = DauamWatchCompass()

  // Мекка: 21.422487, 39.826206
  private var sourceCoordinate: (lat: Double, lng: Double)? {
    if let live = compass.coordinate {
      return (live.latitude, live.longitude)
    }
    guard let lat = snapshot.lat, let lng = snapshot.lng else { return nil }
    return (lat, lng)
  }

  private var qiblaAngle: Double? {
    guard let sourceCoordinate else { return nil }
    let lat = sourceCoordinate.lat
    let lng = sourceCoordinate.lng
    let lat1 = (lat * .pi) / 180.0
    let lng1 = (lng * .pi) / 180.0
    let lat2 = (21.422487 * .pi) / 180.0
    let lng2 = (39.826206 * .pi) / 180.0

    let dLng = lng2 - lng1
    let y = sin(dLng) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng)
    let bearing = atan2(y, x) * (180.0 / .pi)
    return (bearing + 360.0).truncatingRemainder(dividingBy: 360.0)
  }

  private var distanceToMecca: Double? {
    guard let sourceCoordinate else { return nil }
    let lat1 = sourceCoordinate.lat * .pi / 180
    let lat2 = 21.422487 * .pi / 180
    let dLat = lat2 - lat1
    let dLng = (39.826206 - sourceCoordinate.lng) * .pi / 180
    let a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
    return 6_371 * 2 * atan2(sqrt(a), sqrt(1 - a))
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      let palette = DauamWatchPalette.resolve(snapshot: snapshot, at: context.date)
      let primary = palette.darkText ? Color(rgb: 0x101F2A) : Color(rgb: 0xF8F4EA)
      let accent = Color(rgb: palette.accent)

      ZStack {
        DauamWatchBackground(snapshot: snapshot)
        VStack(spacing: 6) {
          HStack {
            Text(snapshot.isKazakh ? "ҚҰБЛА" : "КИБЛА")
              .font(.system(size: 13, weight: .bold, design: .rounded))
              .foregroundStyle(accent)
            Spacer()
            Text(qiblaAngle.map { "\(Int($0))°" } ?? "—")
              .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
              .foregroundStyle(primary.opacity(0.8))
          }
          .padding(.horizontal, 10)

          Spacer(minLength: 0)

          ZStack {
            Circle()
              .stroke(primary.opacity(0.18), lineWidth: 3)
              .frame(width: 86, height: 86)

            // Стрелка показывает Киблу относительно фактического направления
            // корпуса часов, а не просто статичный азимут от севера.
            VStack {
              Image(systemName: "location.north.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(accent)
              Spacer()
            }
            .frame(width: 86, height: 86)
            .rotationEffect(.degrees((qiblaAngle ?? 0) - (compass.heading ?? 0)))
            .opacity(qiblaAngle == nil ? 0.25 : 1)

            Text(snapshot.city)
              .font(.system(size: 9, weight: .semibold, design: .rounded))
              .foregroundStyle(primary.opacity(0.7))
              .lineLimit(1)
          }

          Spacer(minLength: 0)

          Text(
            distanceToMecca.map { "Мекке: \(Int($0.rounded())) км" } ??
              (snapshot.isKazakh ? "Бағыт анықталуда" : "Определяем направление")
          )
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(primary.opacity(0.65))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
      }
    }
    .onAppear { compass.start() }
    .onDisappear { compass.stop() }
  }
}
