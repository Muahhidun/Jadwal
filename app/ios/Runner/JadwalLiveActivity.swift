import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

@available(iOS 17.0, *)
public struct ZikrNextIntent: LiveActivityIntent {
  public static var title: LocalizedStringResource = "Следующий зикр"
  public init() {}

  public func perform() async throws -> some IntentResult {
    NotificationCenter.default.post(name: NSNotification.Name("ZikrNextPressed"), object: nil)
    return .result()
  }
}

@available(iOS 17.0, *)
public struct ZikrPrevIntent: LiveActivityIntent {
  public static var title: LocalizedStringResource = "Предыдущий зикр"
  public init() {}

  public func perform() async throws -> some IntentResult {
    NotificationCenter.default.post(name: NSNotification.Name("ZikrPrevPressed"), object: nil)
    return .result()
  }
}

@available(iOS 17.0, *)
public struct ZikrTickIntent: LiveActivityIntent {
  public static var title: LocalizedStringResource = "Отметить повторение"
  public init() {}

  public func perform() async throws -> some IntentResult {
    NotificationCenter.default.post(name: NSNotification.Name("ZikrTickPressed"), object: nil)
    return .result()
  }
}

/// Безопасный системный таймер. После наступления цели SwiftUI не должен
/// получать обратный ClosedRange<Date> — именно он приводил к placeholders в
/// Dynamic Island при повторном открытии уже истёкшей активности.
@available(iOS 16.1, *)
private struct PrayerCountdown: View {
  let targetTimestamp: Double

  var body: some View {
    let now = Date.now
    let targetDate = Date(timeIntervalSince1970: targetTimestamp)
    if targetTimestamp.isFinite && targetDate > now {
      Text(timerInterval: now...targetDate, countsDown: true)
    } else {
      EmptyView()
    }
  }
}

@available(iOS 16.1, *)
public struct JadwalLiveActivity: Widget {
  public init() {}

  /// `staleDate` не завершает Live Activity — она только переводит её в
  /// состояние stale. Пока основной процесс получает возможность выполнить
  /// явное завершение, показываем компактный финал вместо пустого контейнера.
  private func prayerExpired(
    _ context: ActivityViewContext<JadwalActivityAttributes>
  ) -> Bool {
    guard context.state.mode == "prayer" else { return false }
    if #available(iOS 16.2, *) {
      return context.isStale
    }
    return context.state.targetTimestamp <= Date.now.timeIntervalSince1970
  }

  private func targetURL(_ state: JadwalActivityAttributes.ContentState) -> URL? {
    guard state.mode == "zikr", !state.collectionId.isEmpty else {
      return URL(string: "dauam://home")
    }
    var parts = URLComponents()
    parts.scheme = "dauam"
    parts.host = "zikr"
    parts.queryItems = [
      URLQueryItem(name: "collection", value: state.collectionId),
      URLQueryItem(name: "index", value: String(state.currentIndex))
    ]
    return parts.url
  }

  private func prayerName(_ title: String) -> String {
    let prefix = "До намаза "
    return title.hasPrefix(prefix) ? String(title.dropFirst(prefix.count)) : title
  }

  public var body: some WidgetConfiguration {
    ActivityConfiguration(for: JadwalActivityAttributes.self) { context in
      if prayerExpired(context) {
        HStack(spacing: 10) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
          VStack(alignment: .leading, spacing: 2) {
            Text(prayerName(context.state.title))
              .font(.system(size: 15, weight: .bold))
              .foregroundColor(.white)
            Text("Время намаза наступило")
              .font(.system(size: 13, weight: .medium))
              .foregroundColor(.white.opacity(0.72))
          }
          Spacer()
        }
        .padding(16)
        .background(Color(red: 0.07, green: 0.09, blue: 0.15))
      } else {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("دوام")
              .font(.system(size: 16, weight: .bold, design: .serif))
              .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
            Text(context.state.title)
              .font(.system(size: 15, weight: .bold))
              .foregroundColor(.white)
            Spacer()
            if context.state.mode == "prayer" {
              PrayerCountdown(targetTimestamp: context.state.targetTimestamp)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
            } else {
              Image(systemName: "book.closed.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
            }
          }

          if context.state.mode == "zikr" && !context.state.zikrArabic.isEmpty {
            Text(context.state.zikrArabic)
              .font(.system(size: 16, weight: .bold, design: .serif))
              .foregroundColor(Color(red: 0.95, green: 0.92, blue: 0.85))
              .lineLimit(2)
              .multilineTextAlignment(.trailing)
              .frame(maxWidth: .infinity, alignment: .trailing)

            if !context.state.zikrTranslation.isEmpty {
              Text(context.state.zikrTranslation)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color.white.opacity(0.8))
                .lineLimit(2)
            }
          } else {
            Text(context.state.subtitle)
              .font(.system(size: 13, weight: .medium))
              .foregroundColor(Color.white.opacity(0.7))
          }
        }
        .padding(16)
        .background(Color(red: 0.07, green: 0.09, blue: 0.15))
        .widgetURL(targetURL(context.state))
      }
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          if prayerExpired(context) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
              .padding(.leading, 4)
          } else {
            HStack(spacing: 4) {
              Text("دوام")
                .font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
            }
            .padding(.leading, 4)
          }
        }

        DynamicIslandExpandedRegion(.trailing) {
          if prayerExpired(context) {
            Text("Готово")
              .font(.system(size: 13, weight: .semibold))
              .foregroundColor(.white.opacity(0.85))
              .padding(.trailing, 4)
          } else {
            if context.state.mode == "prayer" {
              PrayerCountdown(targetTimestamp: context.state.targetTimestamp)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
                .padding(.trailing, 4)
            } else {
              Image(systemName: "book.closed.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
                .padding(.trailing, 4)
            }
          }
        }

        DynamicIslandExpandedRegion(.bottom) {
          if prayerExpired(context) {
            Text("Время намаза наступило")
              .font(.system(size: 13, weight: .semibold))
              .foregroundColor(.white.opacity(0.9))
          } else {
            VStack(spacing: 6) {
              Text(context.state.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

              if context.state.mode == "zikr" {
                if !context.state.zikrArabic.isEmpty {
                  Text(context.state.zikrArabic)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundColor(Color(red: 0.95, green: 0.92, blue: 0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                }
                if !context.state.zikrTranslation.isEmpty {
                  Text(context.state.zikrTranslation)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.75))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                }

                if #available(iOS 17.0, *) {
                  HStack(spacing: 16) {
                    Button(intent: ZikrPrevIntent()) {
                      Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 30)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button(intent: ZikrNextIntent()) {
                      Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 30)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                  }
                  .padding(.top, 2)
                }
              } else {
                Text(context.state.subtitle)
                  .font(.system(size: 13, weight: .medium))
                  .foregroundColor(.white.opacity(0.7))
              }
            }
            .padding(.top, 2)
          }
        }
      } compactLeading: {
        if prayerExpired(context) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
        } else {
          Image(systemName: "moon.stars.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
        }
      } compactTrailing: {
        if prayerExpired(context) {
          Text("✓")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
            .frame(width: 20)
        } else {
          if context.state.mode == "prayer" {
            PrayerCountdown(targetTimestamp: context.state.targetTimestamp)
              .font(.system(size: 12, weight: .bold, design: .monospaced))
              .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
              .frame(width: 44)
          } else {
            Image(systemName: "book.closed.fill")
              .font(.system(size: 11, weight: .semibold))
              .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
          }
        }
      } minimal: {
        if prayerExpired(context) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
        } else {
          Image(systemName: "moon.stars.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color(red: 0.85, green: 0.72, blue: 0.42))
        }
      }
      .widgetURL(targetURL(context.state))
    }
  }
}
