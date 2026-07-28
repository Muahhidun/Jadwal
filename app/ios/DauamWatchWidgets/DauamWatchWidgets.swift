import SwiftUI
import WidgetKit

private struct DauamWatchEntry: TimelineEntry {
  let date: Date
  let snapshot: DauamWatchSnapshot
}

private struct DauamWatchProvider: TimelineProvider {
  func placeholder(in context: Context) -> DauamWatchEntry {
    DauamWatchEntry(date: .now, snapshot: .placeholder)
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (DauamWatchEntry) -> Void
  ) {
    completion(
      DauamWatchEntry(
        date: .now,
        snapshot: context.isPreview ? .placeholder : DauamWatchSnapshotStore.load()
      )
    )
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<DauamWatchEntry>) -> Void
  ) {
    let now = Date.now
    let snapshot = DauamWatchSnapshotStore.load()
    var dates = [now]
    for prayer in snapshot.prayers {
      if prayer.date > now && prayer.date < now.addingTimeInterval(36 * 3_600) {
        dates.append(prayer.date.addingTimeInterval(1))
        if prayer.id != "sunrise" {
          dates.append(prayer.date.addingTimeInterval(601))
        }
      }
    }
    dates = Array(Set(dates)).sorted()
    let entries = dates.map { DauamWatchEntry(date: $0, snapshot: snapshot) }
    completion(
      Timeline(
        entries: entries,
        policy: .after(min(now.addingTimeInterval(6 * 3_600), dates.last ?? now))
      )
    )
  }
}

private struct DauamWatchPrayerComplicationView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DauamWatchEntry

  var body: some View {
    let called = entry.snapshot.justCalledPrayer(at: entry.date)
    let next = entry.snapshot.nextEvent(after: entry.date)
    let currentPrayer = called ?? next
    Group {
      switch family {
      case .accessoryCircular:
        ZStack {
          AccessoryWidgetBackground()
          VStack(spacing: 1) {
            Image(systemName: currentPrayer?.symbol ?? "moon.stars.fill")
              .font(.system(size: 14, weight: .semibold))
            Text(currentPrayer?.time ?? "—")
              .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
              .minimumScaleFactor(0.72)
          }
        }

      case .accessoryCorner:
        Image(systemName: currentPrayer?.symbol ?? "moon.stars.fill")
          .font(.system(size: 22, weight: .semibold))
          .widgetLabel {
            if let currentPrayer {
              Text(currentPrayer.time)
            } else {
              Text("Dauam")
            }
          }

      case .accessoryInline:
        if let called {
          Label {
            HStack(spacing: 3) {
              Text(entry.snapshot.isKazakh ? "Азаннан кейін" : "После азана")
              Text(called.date, style: .timer)
            }
          } icon: {
            Image(systemName: called.symbol)
          }
        } else if let next {
          Label {
            HStack(spacing: 3) {
              Text(entry.snapshot.until(next))
              Text(next.date, style: .timer)
            }
          } icon: {
            Image(systemName: next.symbol)
          }
        } else {
          Label("Dauam", systemImage: "moon.stars.fill")
        }

      default:
        if let called {
          HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
              HStack(spacing: 4) {
                Image(systemName: called.symbol)
                  .font(.system(size: 12, weight: .bold))
                  .widgetAccentable()
                Text(entry.snapshot.isKazakh ? "АЗАННАН КЕЙІН" : "ПОСЛЕ АЗАНА")
                  .font(.system(size: 12, weight: .bold, design: .rounded))
                  .lineLimit(1)
                  .minimumScaleFactor(0.75)
              }

              Text(called.date, style: .timer)
                .font(.system(size: 25, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.70)

              HStack(spacing: 3) {
                Image(systemName: "location.fill")
                  .font(.system(size: 7, weight: .semibold))
                Text(entry.snapshot.city)
                  .font(.system(size: 9, weight: .semibold, design: .rounded))
                  .lineLimit(1)
                  .minimumScaleFactor(0.80)
              }
              .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 1) {
              Image(systemName: called.symbol)
                .font(.system(size: 13, weight: .bold))
                .widgetAccentable()
              Text(called.time)
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.80)
              Text(called.title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minWidth: 54, maxHeight: .infinity)
            .background(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.secondary.opacity(0.16))
            )
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if let next {
          HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
              HStack(spacing: 4) {
                Image(systemName: next.symbol)
                  .font(.system(size: 12, weight: .bold))
                  .widgetAccentable()
                Text(entry.snapshot.until(next))
                  .font(.system(size: 12, weight: .bold, design: .rounded))
                  .lineLimit(1)
                  .minimumScaleFactor(0.75)
              }

              Text(next.date, style: .timer)
                .font(.system(size: 25, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.70)

              HStack(spacing: 3) {
                Image(systemName: "location.fill")
                  .font(.system(size: 7, weight: .semibold))
                Text(entry.snapshot.city)
                  .font(.system(size: 9, weight: .semibold, design: .rounded))
                  .lineLimit(1)
                  .minimumScaleFactor(0.80)
              }
              .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 1) {
              Image(systemName: next.symbol)
                .font(.system(size: 13, weight: .bold))
                .widgetAccentable()
              Text(next.time)
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.80)
              Text(next.title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minWidth: 54, maxHeight: .infinity)
            .background(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.secondary.opacity(0.16))
            )
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
          Label(entry.snapshot.openPhoneTitle, systemImage: "moon.stars.fill")
        }
      }
    }
    .containerBackground(for: .widget) { Color.clear }
    .accessibilityElement(children: .combine)
  }
}

private struct DauamWatchTasksComplicationView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DauamWatchEntry

  private var progress: Double {
    guard entry.snapshot.taskTotal > 0 else { return 0 }
    return min(
      1,
      max(0, Double(entry.snapshot.taskDone) / Double(entry.snapshot.taskTotal))
    )
  }

  var body: some View {
    Group {
      if family == .accessoryInline {
        Label(
          "\(entry.snapshot.tasksTitle): \(entry.snapshot.taskDone)/\(entry.snapshot.taskTotal)",
          systemImage: "checkmark.circle"
        )
      } else {
        ZStack {
          AccessoryWidgetBackground()
          Circle()
            .trim(from: 0, to: progress)
            .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
          Text("\(entry.snapshot.taskDone)/\(entry.snapshot.taskTotal)")
            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
        }
        .containerBackground(for: .widget) { Color.clear }
      }
    }
    .accessibilityElement(children: .combine)
  }
}

struct DauamWatchPrayerComplication: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "kz.dauam.watch.prayer",
      provider: DauamWatchProvider()
    ) { entry in
      DauamWatchPrayerComplicationView(entry: entry)
    }
    .configurationDisplayName("Dauam · Намаз")
    .description("Ближайшее время и живой отсчёт.")
    .supportedFamilies([
      .accessoryInline,
      .accessoryCircular,
      .accessoryRectangular,
      .accessoryCorner,
    ])
  }
}

struct DauamWatchTasksComplication: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "kz.dauam.watch.tasks",
      provider: DauamWatchProvider()
    ) { entry in
      DauamWatchTasksComplicationView(entry: entry)
    }
    .configurationDisplayName("Dauam · Дела")
    .description("Прогресс дел поклонения на сегодня.")
    .supportedFamilies([.accessoryInline, .accessoryCircular])
  }
}
