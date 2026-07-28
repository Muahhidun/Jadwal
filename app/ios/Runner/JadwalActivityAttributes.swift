import ActivityKit
import Foundation

public struct JadwalActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    public var mode: String
    public var title: String
    public var subtitle: String
    public var targetTimestamp: Double
    public var counterCurrent: Int
    public var counterTotal: Int
    public var zikrArabic: String
    public var zikrTranslation: String

    public init(
      mode: String = "prayer",
      title: String = "",
      subtitle: String = "",
      targetTimestamp: Double = 0.0,
      counterCurrent: Int = 0,
      counterTotal: Int = 0,
      zikrArabic: String = "",
      zikrTranslation: String = ""
    ) {
      self.mode = mode
      self.title = title
      self.subtitle = subtitle
      self.targetTimestamp = targetTimestamp
      self.counterCurrent = counterCurrent
      self.counterTotal = counterTotal
      self.zikrArabic = zikrArabic
      self.zikrTranslation = zikrTranslation
    }
  }

  public var name: String

  public init(name: String = "JadwalSession") {
    self.name = name
  }
}
