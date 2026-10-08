import Foundation

/// Tunable constants for the rules. Defaults reflect the product spec.
public struct EngineConfig: Sendable, Hashable {
    /// Garments worn within this many days are skipped (unless explicitly chosen).
    public var recentWearExclusionDays: Int = 3
    /// Below this feels-like temperature an outfit needs a jacket or coat.
    public var outerwearRequiredBelowC: Double = 10
    /// Coats are too warm above this temperature.
    public var coatMaxC: Double = 15
    /// Jackets are too warm above this temperature.
    public var jacketMaxC: Double = 24
    /// Blazers are too warm above this temperature.
    public var blazerMaxC: Double = 28
    /// Sweaters and hoodies are too warm above this temperature.
    public var warmLayerMaxC: Double = 22
    /// Shorts only above this temperature.
    public var shortsMinC: Double = 20
    /// Precipitation chance (0...1) from which we treat the day as rainy.
    public var rainChanceThreshold: Double = 0.5
    /// Maximum difference between the most and least formal piece (accessories excluded).
    public var maxFormalitySpread: Int = 1
    /// Maximum number of distinct accent (non-neutral) colors in one outfit.
    public var maxAccentColors: Int = 2
    /// Below this closet size the app shows an empty state instead of weak outfits.
    public var minimumClosetSize: Int = 8
    /// Safety cap for candidate enumeration.
    public var maxCandidates: Int = 20_000

    public init() {}

    public static let `default` = EngineConfig()
}

/// Engine-side view of a garment: attributes only, no images or persistence.
public struct EngineGarment: Sendable, Hashable, Identifiable, Codable {
    public var id: UUID
    public var category: GarmentCategory
    public var subcategory: String
    public var primaryColor: String
    public var secondaryColor: String?
    public var pattern: Pattern
    public var material: String
    public var formality: Int
    /// Empty means "all seasons".
    public var seasons: Set<Season>
    public var brand: String
    public var wearCount: Int
    public var lastWornAt: Date?
    public var isArchived: Bool
    /// True for items the user does not own yet (builder "missing" pieces and gap analysis).
    public var isHypothetical: Bool

    public init(
        id: UUID = UUID(),
        category: GarmentCategory,
        subcategory: String = "",
        primaryColor: String,
        secondaryColor: String? = nil,
        pattern: Pattern = .solid,
        material: String = "",
        formality: Int? = nil,
        seasons: Set<Season> = [],
        brand: String = "",
        wearCount: Int = 0,
        lastWornAt: Date? = nil,
        isArchived: Bool = false,
        isHypothetical: Bool = false
    ) {
        self.id = id
        self.category = category
        self.subcategory = subcategory
        self.primaryColor = ColorPalette.normalize(primaryColor) ?? primaryColor.lowercased()
        self.secondaryColor = secondaryColor.flatMap { ColorPalette.normalize($0) ?? $0.lowercased() }
        self.pattern = pattern
        self.material = material
        self.formality = Formality.clamp(formality ?? category.defaultFormality)
        self.seasons = seasons
        self.brand = brand
        self.wearCount = wearCount
        self.lastWornAt = lastWornAt
        self.isArchived = isArchived
        self.isHypothetical = isHypothetical
    }

    public var slot: Slot? { category.slot }
    public var isNeutral: Bool { ColorPalette.isNeutral(primaryColor) }

    /// Suede (and similar) shoes should stay home on rainy days.
    public var isRainSensitive: Bool {
        let text = (material + " " + subcategory).lowercased()
        return text.contains("suede") || text.contains("nubuck") || text.contains("canvas")
    }

    /// Short human label, e.g. "navy chinos" or "white oxford shirt".
    public var shortLabel: String {
        let noun = subcategory.isEmpty ? category.displayName.lowercased() : subcategory.lowercased()
        return "\(primaryColor) \(noun)"
    }
}

public struct WeatherContext: Sendable, Hashable, Codable {
    public var temperatureC: Double
    public var feelsLikeC: Double
    /// 0...1
    public var precipitationChance: Double
    public var windKph: Double

    public init(temperatureC: Double, feelsLikeC: Double? = nil, precipitationChance: Double = 0, windKph: Double = 0) {
        self.temperatureC = temperatureC
        self.feelsLikeC = feelsLikeC ?? temperatureC
        self.precipitationChance = min(max(precipitationChance, 0), 1)
        self.windKph = max(windKph, 0)
    }
}

public struct StylePreferences: Sendable, Hashable, Codable {
    public var preferredStyles: [Style]
    public var favoriteColors: Set<String>
    public var avoidedColors: Set<String>

    public init(preferredStyles: [Style] = [.smartCasual], favoriteColors: Set<String> = [], avoidedColors: Set<String> = []) {
        self.preferredStyles = preferredStyles
        self.favoriteColors = Set(favoriteColors.compactMap { ColorPalette.normalize($0) })
        self.avoidedColors = Set(avoidedColors.compactMap { ColorPalette.normalize($0) })
    }

    public static let none = StylePreferences(preferredStyles: [])
}

public struct OutfitContext: Sendable, Hashable {
    public var occasion: Occasion?
    public var style: Style?
    public var season: Season?
    public var weather: WeatherContext?
    public var date: Date
    public var preferences: StylePreferences
    /// Garments that must appear in every outfit (builder starting points).
    public var anchorGarmentIDs: Set<UUID>
    /// Gap analysis counts combinations regardless of what was worn recently.
    public var ignoresRecentWear: Bool

    public init(
        occasion: Occasion? = nil,
        style: Style? = nil,
        season: Season? = nil,
        weather: WeatherContext? = nil,
        date: Date = Date(),
        preferences: StylePreferences = .none,
        anchorGarmentIDs: Set<UUID> = [],
        ignoresRecentWear: Bool = false
    ) {
        self.occasion = occasion
        self.style = style
        self.season = season
        self.weather = weather
        self.date = date
        self.preferences = preferences
        self.anchorGarmentIDs = anchorGarmentIDs
        self.ignoresRecentWear = ignoresRecentWear
    }

    /// Allowed formality: occasion range intersected with style range.
    /// If the two do not overlap, the style wins because it is the more explicit choice.
    public var formalityRange: ClosedRange<Int> {
        switch (occasion?.formalityRange, style?.formalityRange) {
        case let (o?, s?): Formality.intersect(o, s) ?? s
        case let (o?, nil): o
        case let (nil, s?): s
        case (nil, nil): Formality.range
        }
    }

    /// The formality the outfit should ideally average.
    public var targetFormality: Double {
        Double(formalityRange.lowerBound + formalityRange.upperBound) / 2
    }
}

/// A combination of garments that passed the deterministic rules.
public struct OutfitCandidate: Sendable, Hashable, Identifiable {
    public var pieces: [Slot: EngineGarment]

    public init(pieces: [Slot: EngineGarment]) { self.pieces = pieces }

    /// Stable id derived from the garment ids, so the same combination always has the same id.
    public var id: String { garmentIDs.map(\.uuidString).sorted().joined(separator: "+") }

    /// Garments in display order (outerwear, top, bottom, shoes, accessory).
    public var garments: [EngineGarment] { Slot.allCases.compactMap { pieces[$0] } }
    public var garmentIDs: [UUID] { garments.map(\.id) }
    public var coreGarments: [EngineGarment] { garments.filter { $0.slot != .accessory } }
    public var hypotheticalGarments: [EngineGarment] { garments.filter(\.isHypothetical) }

    public func sharedGarmentCount(with other: OutfitCandidate) -> Int {
        Set(garmentIDs).intersection(other.garmentIDs).count
    }
}

/// A not-yet-owned item described by attributes (builder "missing" pieces, gap analysis, wishlist).
public struct HypotheticalItem: Sendable, Hashable, Identifiable, Codable {
    public var id: UUID
    public var category: GarmentCategory
    public var color: String
    public var cut: String
    public var material: String
    public var pattern: Pattern
    public var formality: Int
    public var seasons: Set<Season>

    public init(
        id: UUID = UUID(),
        category: GarmentCategory,
        color: String,
        cut: String = "",
        material: String = "",
        pattern: Pattern = .solid,
        formality: Int? = nil,
        seasons: Set<Season> = []
    ) {
        self.id = id
        self.category = category
        self.color = ColorPalette.normalize(color) ?? color.lowercased()
        self.cut = cut
        self.material = material
        self.pattern = pattern
        self.formality = Formality.clamp(formality ?? category.defaultFormality)
        self.seasons = seasons
    }

    /// e.g. "Beige chinos" or "Navy blazer".
    public var title: String {
        let noun = category == .shoes && !cut.isEmpty ? cut.lowercased() : category.displayName.lowercased()
        return "\(color.prefix(1).uppercased())\(color.dropFirst()) \(noun)"
    }

    /// Search text for retailer links, e.g. "beige slim chinos cotton".
    public var searchQuery: String {
        let noun = category == .tShirt ? "t-shirt" : category.rawValue
        return [color, cut, cut.lowercased().contains(noun) ? "" : noun, material]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    public var asGarment: EngineGarment {
        EngineGarment(
            id: id, category: category, subcategory: cut, primaryColor: color, pattern: pattern,
            material: material, formality: formality, seasons: seasons, isHypothetical: true
        )
    }

    /// True if the closet already has something equivalent (same category and color).
    public func isOwned(in closet: [EngineGarment]) -> Bool {
        closet.contains { !$0.isArchived && $0.category == category && $0.primaryColor == color }
    }
}

/// A finished outfit ready for display: candidate + accessory + wording.
public struct EngineOutfit: Sendable, Hashable, Identifiable {
    public var id: String { candidate.id }
    public var candidate: OutfitCandidate
    public var title: String
    public var reasoning: String
    public var score: Double
    /// Specs for hypothetical pieces, keyed by slot.
    public var missing: [Slot: HypotheticalItem]

    public init(candidate: OutfitCandidate, title: String, reasoning: String, score: Double, missing: [Slot: HypotheticalItem] = [:]) {
        self.candidate = candidate
        self.title = title
        self.reasoning = reasoning
        self.score = score
        self.missing = missing
    }

    public var pieces: [Slot: EngineGarment] { candidate.pieces }
    public var garmentIDs: [UUID] { candidate.garmentIDs }
    /// Ids of pieces the user actually owns.
    public var ownedGarmentIDs: [UUID] { candidate.garments.filter { !$0.isHypothetical }.map(\.id) }
    public var hasMissingPieces: Bool { !missing.isEmpty }
}

public struct ScoredCandidate: Sendable, Hashable {
    public var candidate: OutfitCandidate
    public var score: Double

    public init(candidate: OutfitCandidate, score: Double) {
        self.candidate = candidate
        self.score = score
    }
}
