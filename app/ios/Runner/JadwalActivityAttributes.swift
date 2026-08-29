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
    public var collectionId: String
    public var currentIndex: Int

    public init(
      mode: String = "prayer",
      title: String = "",
      subtitle: String = "",
      targetTimestamp: Double = 0.0,
      counterCurrent: Int = 0,
      counterTotal: Int = 0,
      zikrArabic: String = "",
      zikrTranslation: String = "",
      collectionId: String = "",
      currentIndex: Int = 0
    ) {
      self.mode = mode
      self.title = title
      self.subtitle = subtitle
      self.targetTimestamp = targetTimestamp
      self.counterCurrent = counterCurrent
      self.counterTotal = counterTotal
      self.zikrArabic = zikrArabic
      self.zikrTranslation = zikrTranslation
      self.collectionId = collectionId
      self.currentIndex = currentIndex
    }

    private enum CodingKeys: String, CodingKey {
      case mode, title, subtitle, targetTimestamp, counterCurrent, counterTotal
      case zikrArabic, zikrTranslation, collectionId, currentIndex
    }

    public init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      mode = try values.decodeIfPresent(String.self, forKey: .mode) ?? "prayer"
      title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
      subtitle = try values.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
      targetTimestamp = try values.decodeIfPresent(Double.self, forKey: .targetTimestamp) ?? 0
      counterCurrent = try values.decodeIfPresent(Int.self, forKey: .counterCurrent) ?? 0
      counterTotal = try values.decodeIfPresent(Int.self, forKey: .counterTotal) ?? 0
      zikrArabic = try values.decodeIfPresent(String.self, forKey: .zikrArabic) ?? ""
      zikrTranslation = try values.decodeIfPresent(String.self, forKey: .zikrTranslation) ?? ""
      collectionId = try values.decodeIfPresent(String.self, forKey: .collectionId) ?? ""
      currentIndex = try values.decodeIfPresent(Int.self, forKey: .currentIndex) ?? max(0, counterCurrent - 1)
    }
  }

  public var name: String

  public init(name: String = "JadwalSession") {
    self.name = name
  }
}
