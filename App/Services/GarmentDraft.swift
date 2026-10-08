import Foundation
import OutfitEngine

/// Editable, not-yet-saved garment produced by the photo, order and manual flows.
struct GarmentDraft: Identifiable, Hashable {
    static let reviewConfidenceThreshold = 0.7

    var id = UUID()
    var name: String = ""
    var category: GarmentCategory = .other
    var subcategory: String = ""
    var primaryColor: String = "black"
    var secondaryColor: String?
    var pattern: Pattern = .solid
    var material: String = ""
    var formality: Int = 3
    var seasons: Set<Season> = []
    var brand: String = ""
    var size: String = ""
    var price: Double?
    var purchaseDate: Date?
    var source: GarmentSource = .manual
    var confidence: Double?
    var originalImageFile: String?
    var cutoutImageFile: String?
    /// Product image to download for order imports.
    var remoteImageURL: URL?
    /// Set once the user changes any field in the review UI.
    var wasEdited = false

    var displayName: String {
        name.isEmpty ? "\(primaryColor.capitalized) \(subcategory.isEmpty ? category.displayName.lowercased() : subcategory)" : name
    }

    var isLowConfidence: Bool { (confidence ?? 1) < Self.reviewConfidenceThreshold }

    /// Status rules: order imports always need review; recognized photos need review when the AI was unsure
    /// and the user did not touch the card; manual entries are confirmed.
    var resolvedStatus: GarmentStatus {
        switch source {
        case .order: .pendingReview
        case .photo: isLowConfidence && !wasEdited ? .pendingReview : .confirmed
        case .manual: .confirmed
        }
    }

    func makeGarment(ownerID: String = "local") -> Garment {
        let garment = Garment(
            name: name, category: category, subcategory: subcategory, primaryColor: primaryColor,
            secondaryColor: secondaryColor, pattern: pattern, material: material, formality: formality,
            seasons: seasons, brand: brand, size: size, price: price, purchaseDate: purchaseDate,
            source: source, status: resolvedStatus, confidence: confidence
        )
        garment.ownerID = ownerID
        garment.originalImageFile = originalImageFile
        garment.cutoutImageFile = cutoutImageFile
        return garment
    }

    /// Copies editable fields back onto an existing garment (detail screen edits).
    func apply(to garment: Garment) {
        garment.name = name
        garment.category = category
        garment.subcategory = subcategory
        garment.primaryColor = primaryColor
        garment.secondaryColor = secondaryColor
        garment.pattern = pattern
        garment.material = material
        garment.formality = Formality.clamp(formality)
        garment.seasons = seasons
        garment.brand = brand
        garment.size = size
        garment.price = price
        garment.purchaseDate = purchaseDate
        garment.touch()
    }

    init() {}

    init(garment: Garment) {
        id = garment.id
        name = garment.name
        category = garment.category
        subcategory = garment.subcategory
        primaryColor = garment.primaryColor
        secondaryColor = garment.secondaryColor
        pattern = garment.pattern
        material = garment.material
        formality = garment.formality
        seasons = garment.seasons
        brand = garment.brand
        size = garment.size
        price = garment.price
        purchaseDate = garment.purchaseDate
        source = garment.source
        confidence = garment.confidence
        originalImageFile = garment.originalImageFile
        cutoutImageFile = garment.cutoutImageFile
    }
}

/// Maps backend DTOs to drafts, normalizing and clamping anything the AI got slightly wrong.
enum GarmentDraftMapper {
    static func draft(from dto: AnalyzedGarmentDTO) -> GarmentDraft {
        var draft = GarmentDraft()
        draft.source = .photo
        draft.category = category(from: dto.category, fallbackText: dto.name + " " + dto.subcategory)
        draft.subcategory = dto.subcategory.trimmingCharacters(in: .whitespaces)
        draft.name = dto.name.trimmingCharacters(in: .whitespaces)
        draft.primaryColor = ColorPalette.normalize(dto.primaryColor) ?? ManualEntryInference.color(in: dto.name) ?? "grey"
        draft.secondaryColor = ColorPalette.normalize(dto.secondaryColor)
        draft.pattern = Pattern(rawValue: dto.pattern.lowercased()) ?? .solid
        draft.material = dto.material?.trimmingCharacters(in: .whitespaces) ?? ""
        draft.formality = Formality.clamp(dto.formality)
        draft.seasons = Set(dto.seasons.compactMap { Season(rawValue: $0.lowercased()) })
        draft.brand = dto.brand ?? ""
        draft.confidence = min(max(dto.confidence, 0), 1)
        return draft
    }

    static func draft(from item: ParsedOrderItemDTO) -> GarmentDraft {
        var draft = GarmentDraft()
        draft.source = .order
        draft.name = item.name.trimmingCharacters(in: .whitespaces)
        draft.category = category(from: item.category, fallbackText: item.name)
        draft.primaryColor = ColorPalette.normalize(item.color) ?? ManualEntryInference.color(in: item.name) ?? "grey"
        draft.formality = draft.category.defaultFormality
        draft.brand = item.brand ?? ""
        draft.size = item.size ?? ""
        draft.price = item.price.flatMap { $0 >= 0 ? $0 : nil }
        draft.purchaseDate = item.purchaseDate.flatMap(parseDate)
        if let raw = item.imageUrl, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            draft.remoteImageURL = url
        }
        return draft
    }

    static func category(from raw: String, fallbackText: String) -> GarmentCategory {
        let key = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if let category = GarmentCategory(rawValue: key), category != .other { return category }
        if key == "tshirt" || key == "t_shirt" { return .tShirt }
        return ManualEntryInference.category(in: fallbackText) ?? .other
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(text.prefix(10)))
    }
}

/// Guesses attributes from a free-text name ("Beige slim chinos" -> chinos, beige).
enum ManualEntryInference {
    private static let rules: [(keywords: [String], category: GarmentCategory)] = [
        (["t-shirt", "t shirt", "tshirt", "tee"], .tShirt),
        (["polo"], .polo),
        (["hoodie", "sweatshirt"], .hoodie),
        (["sweater", "jumper", "cardigan", "knit", "pullover"], .sweater),
        (["shirt"], .shirt),
        (["blazer", "sport coat", "suit jacket", "sports jacket"], .blazer),
        (["overcoat", "trench", "parka", "coat"], .coat),
        (["jacket", "bomber", "harrington", "gilet"], .jacket),
        (["chino"], .chinos),
        (["jeans", "denim pants"], .jeans),
        (["shorts"], .shorts),
        (["trousers", "pants", "slacks"], .trousers),
        (["shoes", "sneakers", "trainers", "boots", "loafers", "derby", "derbies", "brogues", "oxfords", "moccasins"], .shoes),
        (["belt", "watch", "tie", "scarf", "cap", "hat", "bag", "sunglasses", "gloves", "pocket square"], .accessory)
    ]

    static func category(in text: String) -> GarmentCategory? {
        let lower = text.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
        func matches(_ keyword: String) -> Bool {
            // Multi-word or hyphenated keywords match as phrases; single words match word prefixes
            // ("chino" matches "chinos", but "tee" does not match "steel").
            keyword.contains(where: { !$0.isLetter }) ? lower.contains(keyword) : words.contains { $0.hasPrefix(keyword) }
        }
        for rule in rules where rule.keywords.contains(where: matches) {
            return rule.category
        }
        return nil
    }

    static func color(in text: String) -> String? {
        ColorPalette.normalize(text)
    }

    /// Fills category, color and formality from the name when the user has not set them yet.
    static func apply(to draft: inout GarmentDraft) {
        if let category = category(in: draft.name) {
            draft.category = category
            draft.formality = category.defaultFormality
        }
        if let color = color(in: draft.name) { draft.primaryColor = color }
    }
}

enum DuplicateDetector {
    static func key(category: GarmentCategory, color: String, brand: String) -> String {
        "\(category.rawValue)|\(color.lowercased())|\(brand.trimmingCharacters(in: .whitespaces).lowercased())"
    }

    /// Likely duplicates: same category, same primary color and same brand (an empty brand matches an empty brand).
    static func duplicates(of draft: GarmentDraft, in closet: [Garment]) -> [Garment] {
        let brand = draft.brand.trimmingCharacters(in: .whitespaces).lowercased()
        return closet.filter { garment in
            garment.status != .archived
                && garment.id != draft.id
                && garment.category == draft.category
                && garment.primaryColor == draft.primaryColor
                && garment.brand.trimmingCharacters(in: .whitespaces).lowercased() == brand
        }
    }
}
