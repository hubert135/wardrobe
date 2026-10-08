import Foundation

/// GDPR export: everything the app stores about the user, as JSON. Images are referenced by file name.
@MainActor
enum DataExporter {
    struct Export: Codable {
        var exportedAt: Date
        var profile: ProfileExport
        var garments: [GarmentExport]
        var outfits: [OutfitExport]
        var wishlist: [WishlistExport]
    }

    struct ProfileExport: Codable {
        var name: String
        var cityOverride: String?
        var preferredStyles: [String]
        var favoriteColors: [String]
        var avoidedColors: [String]
        var favoriteBrands: [String]
        var defaultBudget: Double?
        var currencyCode: String
        var notificationsEnabled: Bool
        var notificationTime: String
    }

    struct GarmentExport: Codable {
        var id: UUID
        var name: String
        var category: String
        var subcategory: String
        var primaryColor: String
        var secondaryColor: String?
        var pattern: String
        var material: String
        var formality: Int
        var seasons: [String]
        var brand: String
        var size: String
        var price: Double?
        var purchaseDate: Date?
        var source: String
        var status: String
        var wearCount: Int
        var lastWornAt: Date?
        var createdAt: Date
        var originalImageFile: String?
        var cutoutImageFile: String?
    }

    struct OutfitExport: Codable {
        var id: UUID
        var title: String
        var occasion: String
        var style: String
        var season: String
        var reasoning: String
        var createdAt: Date
        var wornOn: Date?
        var isFavorite: Bool
        var garmentIds: [UUID]
        var missingPieces: [String]
        var weather: WeatherSnapshot?
    }

    struct WishlistExport: Codable {
        var description: String
        var category: String
        var color: String
        var searchQuery: String
        var unlockedOutfitCount: Int
        var status: String
        var createdAt: Date
    }

    static func export(repository: WardrobeRepository) throws -> URL {
        let profile = repository.profile()
        let export = Export(
            exportedAt: Date(),
            profile: ProfileExport(
                name: profile.name, cityOverride: profile.cityOverride, preferredStyles: profile.preferredStylesRaw,
                favoriteColors: profile.favoriteColors, avoidedColors: profile.avoidedColors,
                favoriteBrands: profile.favoriteBrands, defaultBudget: profile.defaultBudget,
                currencyCode: profile.currencyCode, notificationsEnabled: profile.notificationsEnabled,
                notificationTime: String(format: "%02d:%02d", profile.notificationHour, profile.notificationMinute)
            ),
            garments: repository.garments(includeArchived: true).map {
                GarmentExport(
                    id: $0.id, name: $0.name, category: $0.categoryRaw, subcategory: $0.subcategory,
                    primaryColor: $0.primaryColor, secondaryColor: $0.secondaryColor, pattern: $0.patternRaw,
                    material: $0.material, formality: $0.formality, seasons: $0.seasonsRaw, brand: $0.brand,
                    size: $0.size, price: $0.price, purchaseDate: $0.purchaseDate, source: $0.sourceRaw,
                    status: $0.statusRaw, wearCount: $0.wearCount, lastWornAt: $0.lastWornAt, createdAt: $0.createdAt,
                    originalImageFile: $0.originalImageFile, cutoutImageFile: $0.cutoutImageFile
                )
            },
            outfits: repository.outfits().map { outfit in
                OutfitExport(
                    id: outfit.id, title: outfit.title, occasion: outfit.occasionRaw, style: outfit.styleRaw,
                    season: outfit.seasonRaw, reasoning: outfit.reasoning, createdAt: outfit.createdAt,
                    wornOn: outfit.wornOn, isFavorite: outfit.isFavorite,
                    garmentIds: outfit.garments.map(\.id),
                    missingPieces: outfit.orderedSlots.compactMap { $0.missingItem?.title },
                    weather: outfit.weatherSnapshot
                )
            },
            wishlist: repository.wishlist().map {
                WishlistExport(
                    description: $0.itemDescription, category: $0.categoryRaw, color: $0.color,
                    searchQuery: $0.searchQuery, unlockedOutfitCount: $0.unlockedOutfitCount,
                    status: $0.statusRaw, createdAt: $0.createdAt
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wardrobe-export-\(formatter.string(from: Date())).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
