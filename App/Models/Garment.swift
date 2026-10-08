import Foundation
import OutfitEngine
import SwiftData

enum GarmentStatus: String, Codable, CaseIterable, Identifiable {
    case confirmed, pendingReview, archived
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .confirmed: "Confirmed"
        case .pendingReview: "Needs review"
        case .archived: "Archived"
        }
    }
}

enum GarmentSource: String, Codable, CaseIterable {
    case photo, order, manual
}

/// A piece of clothing the user owns.
///
/// CloudKit-ready by construction: every attribute has a default or is optional, there are no unique
/// constraints, and relationships are optional. Enums are stored as raw strings so the schema stays
/// stable and SwiftData predicates can filter on them.
@Model
final class Garment {
    var id: UUID = UUID()
    /// Owner account. "local" until the user signs in; enables multiple users/devices later.
    var ownerID: String = "local"
    var name: String = ""
    var categoryRaw: String = GarmentCategory.other.rawValue
    var subcategory: String = ""
    var primaryColor: String = "black"
    var secondaryColor: String?
    var patternRaw: String = Pattern.solid.rawValue
    var material: String = ""
    var formality: Int = 3
    var seasonsRaw: [String] = []
    var brand: String = ""
    var size: String = ""
    var price: Double?
    var purchaseDate: Date?
    var sourceRaw: String = GarmentSource.manual.rawValue
    var originalImageFile: String?
    var cutoutImageFile: String?
    var statusRaw: String = GarmentStatus.confirmed.rawValue
    var wearCount: Int = 0
    var lastWornAt: Date?
    /// AI recognition confidence (0...1), if the garment came from recognition.
    var confidence: Double?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \OutfitSlot.garment)
    var outfitSlots: [OutfitSlot]? = []

    init(
        name: String,
        category: GarmentCategory,
        subcategory: String = "",
        primaryColor: String,
        secondaryColor: String? = nil,
        pattern: Pattern = .solid,
        material: String = "",
        formality: Int? = nil,
        seasons: Set<Season> = [],
        brand: String = "",
        size: String = "",
        price: Double? = nil,
        purchaseDate: Date? = nil,
        source: GarmentSource = .manual,
        status: GarmentStatus = .confirmed,
        confidence: Double? = nil
    ) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.subcategory = subcategory
        self.primaryColor = ColorPalette.normalize(primaryColor) ?? primaryColor.lowercased()
        self.secondaryColor = secondaryColor.flatMap { ColorPalette.normalize($0) }
        self.patternRaw = pattern.rawValue
        self.material = material
        self.formality = Formality.clamp(formality ?? category.defaultFormality)
        self.seasonsRaw = seasons.map(\.rawValue).sorted()
        self.brand = brand
        self.size = size
        self.price = price
        self.purchaseDate = purchaseDate
        self.sourceRaw = source.rawValue
        self.statusRaw = status.rawValue
        self.confidence = confidence
    }

    var category: GarmentCategory {
        get { GarmentCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var pattern: Pattern {
        get { Pattern(rawValue: patternRaw) ?? .solid }
        set { patternRaw = newValue.rawValue }
    }

    var seasons: Set<Season> {
        get { Set(seasonsRaw.compactMap(Season.init(rawValue:))) }
        set { seasonsRaw = newValue.map(\.rawValue).sorted() }
    }

    var source: GarmentSource {
        get { GarmentSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var status: GarmentStatus {
        get { GarmentStatus(rawValue: statusRaw) ?? .confirmed }
        set { statusRaw = newValue.rawValue }
    }

    var displayName: String {
        if !name.isEmpty { return name }
        let noun = subcategory.isEmpty ? category.displayName.lowercased() : subcategory
        return "\(primaryColor.capitalized) \(noun)"
    }

    /// Price divided by wear count; `nil` without a price.
    var costPerWear: Double? {
        guard let price else { return nil }
        return price / Double(max(wearCount, 1))
    }

    /// Image to show: the cutout if background removal worked, otherwise the original photo.
    var displayImageFile: String? { cutoutImageFile ?? originalImageFile }

    var engineGarment: EngineGarment {
        EngineGarment(
            id: id, category: category, subcategory: subcategory, primaryColor: primaryColor,
            secondaryColor: secondaryColor, pattern: pattern, material: material, formality: formality,
            seasons: seasons, brand: brand, wearCount: wearCount, lastWornAt: lastWornAt,
            isArchived: status == .archived
        )
    }

    func touch() { updatedAt = Date() }
}
