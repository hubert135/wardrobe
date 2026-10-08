import Foundation
@testable import OutfitEngine

enum Fixtures {
    static let monday: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 5; components.hour = 8
        return Calendar.current.date(from: components)!
    }()

    static func garment(
        _ category: GarmentCategory,
        _ color: String,
        formality: Int? = nil,
        pattern: Pattern = .solid,
        material: String = "",
        subcategory: String = "",
        seasons: Set<Season> = [],
        lastWornAt: Date? = nil,
        archived: Bool = false
    ) -> EngineGarment {
        EngineGarment(
            category: category, subcategory: subcategory, primaryColor: color, pattern: pattern,
            material: material, formality: formality, seasons: seasons, lastWornAt: lastWornAt, isArchived: archived
        )
    }

    /// A small smart-casual closet with predictable combinations.
    static func smartCasualCloset() -> [EngineGarment] {
        [
            garment(.shirt, "white", formality: 3),
            garment(.shirt, "light blue", formality: 3),
            garment(.polo, "navy", formality: 3),
            garment(.chinos, "beige", formality: 3),
            garment(.trousers, "grey", formality: 4),
            garment(.shoes, "brown", formality: 4, material: "leather", subcategory: "derby shoes"),
            garment(.shoes, "white", formality: 3, material: "leather", subcategory: "sneakers"),
            garment(.blazer, "navy", formality: 4),
            garment(.jacket, "olive", formality: 3, subcategory: "field jacket"),
            garment(.accessory, "brown", formality: 3, subcategory: "belt")
        ]
    }

    static func context(
        occasion: Occasion? = .work,
        style: Style? = .smartCasual,
        season: Season? = .autumn,
        weather: WeatherContext? = WeatherContext(temperatureC: 16),
        anchors: Set<UUID> = []
    ) -> OutfitContext {
        OutfitContext(occasion: occasion, style: style, season: season, weather: weather, date: monday, anchorGarmentIDs: anchors)
    }
}
