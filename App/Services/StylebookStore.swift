import Foundation
import Observation
import OutfitEngine

// Wire format of GET /v1/stylebook: outfit formulas learned from the user's own e-book
// (what to combine, in which colors and fabrics). Products, shops and prices never leave the server.

struct StylebookDTO: Codable, Equatable {
    var version: String
    var recipes: [StylebookRecipeDTO]
}

struct StylebookRecipeDTO: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var summary: String
    var occasions: [String]
    var styles: [String]
    var seasons: [String]
    var pieces: [StylebookPieceDTO]
}

struct StylebookPieceDTO: Codable, Equatable {
    var slot: String
    var categories: [String]
    var colors: [String]
    var patterns: [String]?
    var materials: [String]?
    var optional: Bool?
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
    /// Keywords that make a piece what it is (a silhouette, a key layer or a key fabric). In a style-guide formula
    /// they are required, so "high-waisted pleated trousers" are never filled with any pair of trousers.
    static let definingKeywords = [
        "pleat", "high-rise", "high-waisted", "wide", "cardigan", "shawl", "turtleneck", "roll", "velvet",
        "corduroy", "cord", "cable", "nordic", "breton", "stripe", "rugby", "vest", "gilet", "quilted", "parka",
        "waxed", "harrington", "overshirt", "double-breasted", "suit", "fatigue", "cargo", "chambray", "peacoat",
        "trench", "troyer", "zip", "windbreaker", "suede", "leather",
    ]

    var enginePiece: RecipePiece {
        let keywords = (materials ?? []).map { $0.lowercased() }
        let isOptional = optional ?? false
        let slot = Slot(rawValue: slot) ?? .accessory
        // Shoes and accessories stay flexible; they never define a look.
        let defining = isOptional || slot == .shoes || slot == .accessory
            ? [] : keywords.filter { keyword in Self.definingKeywords.contains { keyword.contains($0) } }
        return RecipePiece(
            slot: slot,
            categories: categories.compactMap(GarmentCategory.init(rawValue:)),
            colors: colors,
            patterns: (patterns ?? []).compactMap(Pattern.init(rawValue:)),
            materials: keywords,
            requires: defining,
            optional: isOptional
        )
    }
}

/// All outfit recipes the engine uses: the built-in library of classic, brand-free formulas plus the
/// formulas learned from the user's private style guide (fetched from their own server, cached for offline use).
@MainActor
@Observable
final class StylebookStore {
    private(set) var privateRecipes: [StyleRecipe] = []
    private(set) var isLoading = false

    private let api: WardrobeAPI
    private let fileURL: URL
    private var lastAttempt: Date?

    init(api: WardrobeAPI, fileURL: URL? = nil) {
        self.api = api
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? support.appendingPathComponent("stylebook.json")
        // Earlier versions downloaded the e-book's product photos; the app no longer uses them.
        try? FileManager.default.removeItem(at: support.appendingPathComponent("StylebookImages", isDirectory: true))
        if let data = try? Data(contentsOf: self.fileURL), let cached = try? JSONDecoder().decode(StylebookDTO.self, from: data) {
            apply(cached)
        }
    }

    /// Library first, then the private formulas.
    var recipes: [StyleRecipe] { RecipeLibrary.standard + privateRecipes }
    var hasStylebook: Bool { !privateRecipes.isEmpty }

    func isFromStyleGuide(_ recipe: StyleRecipe) -> Bool {
        privateRecipes.contains { $0.id == recipe.id }
    }

    /// Checks the server for a new version at most once an hour (or always with `force`).
    func refresh(force: Bool = false) async {
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 3600 { return }
        lastAttempt = Date()
        isLoading = true
        defer { isLoading = false }
        guard let fresh = try? await api.stylebook() else { return }
        apply(fresh)
        if let data = try? JSONEncoder().encode(fresh) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func deleteCache() {
        try? FileManager.default.removeItem(at: fileURL)
        privateRecipes = []
    }

    private func apply(_ stylebook: StylebookDTO) {
        privateRecipes = stylebook.recipes.map(\.engineRecipe)
    }
}
