import Foundation
import Observation
import OutfitEngine

// Wire format of GET /v1/stylebook (built by tools/stylebook from the user's own e-book).

struct StylebookDTO: Codable, Equatable {
    var version: String
    var source: String?
    var recipes: [StylebookRecipeDTO]
    var alternatives: [StylebookAlternativeDTO]?
}

struct StylebookRecipeDTO: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var summary: String
    var description: String
    var occasions: [String]
    var styles: [String]
    var seasons: [String]
    var pieces: [StylebookPieceDTO]
    /// "standard", "budget" (lower price) and "premium".
    var budgets: [String: StylebookBudgetDTO]
}

struct StylebookPieceDTO: Codable, Equatable {
    var slot: String
    var categories: [String]
    var colors: [String]
    var patterns: [String]?
    var materials: [String]
    var labels: [String]?
    var optional: Bool?
}

struct StylebookBudgetDTO: Codable, Equatable {
    var total: Int?
    var items: [StylebookProductDTO]
}

struct StylebookProductDTO: Codable, Equatable, Hashable {
    /// Piece label from the e-book, e.g. "KURTKA".
    var label: String
    var price: Int
    var currency: String?
    var shop: String?
    var url: String?
    /// Index into the recipe's pieces.
    var pieceIndex: Int?
    var brand: String?
    /// File name of the product photo on the user's server.
    var image: String?
}

struct StylebookAlternativeDTO: Codable, Equatable {
    var title: String
    var options: [StylebookProductDTO]
}

enum StylebookBudget: String, CaseIterable, Identifiable {
    case budget, standard, premium
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .budget: "Lower price"
        case .standard: "Standard"
        case .premium: "Premium"
        }
    }
}

extension StylebookRecipeDTO {
    /// Engine form of the recipe.
    var engineRecipe: StyleRecipe {
        StyleRecipe(
            id: id,
            title: title,
            summary: summary,
            occasions: occasions.compactMap(Occasion.init(rawValue:)),
            styles: styles.compactMap(Style.init(rawValue:)),
            seasons: Set(seasons.compactMap(Season.init(rawValue:))),
            pieces: pieces.map(\.enginePiece)
        )
    }
}

extension StylebookPieceDTO {
    var enginePiece: RecipePiece {
        RecipePiece(
            slot: Slot(rawValue: slot) ?? .accessory,
            categories: categories.compactMap(GarmentCategory.init(rawValue:)),
            colors: colors,
            patterns: (patterns ?? []).compactMap(Pattern.init(rawValue:)),
            materials: materials,
            optional: optional ?? false
        )
    }

    /// Short English description, e.g. "olive coat or jacket".
    var displayName: String {
        let names = categories.compactMap(GarmentCategory.init(rawValue:)).map { $0.displayName.lowercased() }
        let kind = names.isEmpty ? "piece" : names.prefix(2).joined(separator: " or ")
        let color = colors.prefix(2).joined(separator: "/")
        return color.isEmpty ? kind.capitalized : "\(color.capitalized) \(kind)"
    }
}

/// The user's private style guide: fetched from their own server, cached on the phone so it also works offline.
@MainActor
@Observable
final class StylebookStore {
    private(set) var stylebook: StylebookDTO?
    private(set) var recipes: [StyleRecipe] = []
    private(set) var isLoading = false

    private let api: WardrobeAPI
    private let fileURL: URL
    private let imagesDirectory: URL
    private var lastAttempt: Date?

    init(api: WardrobeAPI, fileURL: URL? = nil) {
        self.api = api
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? support.appendingPathComponent("stylebook.json")
        self.imagesDirectory = support.appendingPathComponent("StylebookImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: self.fileURL), let cached = try? JSONDecoder().decode(StylebookDTO.self, from: data) {
            apply(cached)
        }
    }

    var hasStylebook: Bool { stylebook != nil }

    func recipe(id: String) -> StylebookRecipeDTO? {
        stylebook?.recipes.first { $0.id == id }
    }

    /// Checks the server for a new version at most once an hour (or always with `force`).
    func refresh(force: Bool = false) async {
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 3600 { return }
        lastAttempt = Date()
        isLoading = true
        defer { isLoading = false }
        guard let fresh = try? await api.stylebook(), fresh.version != stylebook?.version else { return }
        apply(fresh)
        if let data = try? JSONEncoder().encode(fresh) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Local copy of a product photo, downloaded from the user's server the first time it is needed.
    func imageFile(named name: String) async -> URL? {
        guard name.range(of: #"^[a-z0-9-]{1,80}\.jpg$"#, options: .regularExpression) != nil else { return nil }
        let url = imagesDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let data = try? await api.stylebookImage(named: name), !data.isEmpty else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }

    func deleteCache() {
        try? FileManager.default.removeItem(at: imagesDirectory)
        try? FileManager.default.removeItem(at: fileURL)
        stylebook = nil
        recipes = []
    }

    private func apply(_ stylebook: StylebookDTO) {
        self.stylebook = stylebook
        recipes = stylebook.recipes.map(\.engineRecipe)
    }
}
