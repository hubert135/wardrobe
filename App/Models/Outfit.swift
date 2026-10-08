import Foundation
import OutfitEngine
import SwiftData

/// Weather at the time an outfit was suggested or worn.
struct WeatherSnapshot: Codable, Hashable {
    var temperatureC: Double
    var feelsLikeC: Double
    var precipitationChance: Double
    var windKph: Double
    var conditionDescription: String
    var symbolName: String
    var locationName: String
    var fetchedAt: Date

    var engineWeather: WeatherContext {
        WeatherContext(temperatureC: temperatureC, feelsLikeC: feelsLikeC, precipitationChance: precipitationChance, windKph: windKph)
    }
}

/// A saved outfit: either worn (history) or favorited. Unsaved suggestions live in memory only.
@Model
final class Outfit {
    var id: UUID = UUID()
    var ownerID: String = "local"
    var title: String = ""
    var occasionRaw: String = Occasion.work.rawValue
    var styleRaw: String = Style.smartCasual.rawValue
    var seasonRaw: String = Season.autumn.rawValue
    /// JSON-encoded `WeatherSnapshot`.
    var weatherSnapshotData: Data?
    var reasoning: String = ""
    var createdAt: Date = Date()
    var wornOn: Date?
    var isFavorite: Bool = false
    /// Stable combination id from the engine, used to find an existing favorite for a suggestion.
    var combinationKey: String = ""

    @Relationship(deleteRule: .cascade, inverse: \OutfitSlot.outfit)
    var slots: [OutfitSlot]? = []

    init(title: String, occasion: Occasion, style: Style, season: Season, reasoning: String, combinationKey: String) {
        self.title = title
        self.occasionRaw = occasion.rawValue
        self.styleRaw = style.rawValue
        self.seasonRaw = season.rawValue
        self.reasoning = reasoning
        self.combinationKey = combinationKey
    }

    var occasion: Occasion { Occasion(rawValue: occasionRaw) ?? .work }
    var style: Style { Style(rawValue: styleRaw) ?? .smartCasual }
    var season: Season { Season(rawValue: seasonRaw) ?? .autumn }

    var weatherSnapshot: WeatherSnapshot? {
        get { weatherSnapshotData.flatMap { try? JSONDecoder().decode(WeatherSnapshot.self, from: $0) } }
        set { weatherSnapshotData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var orderedSlots: [OutfitSlot] {
        (slots ?? []).sorted { $0.slot < $1.slot }
    }

    var garments: [Garment] { orderedSlots.compactMap(\.garment) }
}

/// One position in an outfit. Either references an owned garment or describes a missing piece.
@Model
final class OutfitSlot {
    var id: UUID = UUID()
    var slotRaw: String = Slot.top.rawValue
    var garment: Garment?
    var outfit: Outfit?
    var isMissing: Bool = false
    // Missing-piece spec (used when `garment` is nil).
    var missingCategoryRaw: String?
    var missingColor: String?
    var missingCut: String?
    var missingFormality: Int?

    init(slot: Slot, garment: Garment?) {
        self.slotRaw = slot.rawValue
        self.garment = garment
    }

    init(slot: Slot, missing item: HypotheticalItem) {
        self.slotRaw = slot.rawValue
        self.isMissing = true
        self.missingCategoryRaw = item.category.rawValue
        self.missingColor = item.color
        self.missingCut = item.cut
        self.missingFormality = item.formality
    }

    var slot: Slot { Slot(rawValue: slotRaw) ?? .top }

    var missingItem: HypotheticalItem? {
        guard isMissing, let raw = missingCategoryRaw, let category = GarmentCategory(rawValue: raw) else { return nil }
        return HypotheticalItem(category: category, color: missingColor ?? "", cut: missingCut ?? "", formality: missingFormality)
    }
}
