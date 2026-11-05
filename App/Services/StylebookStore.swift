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
    var enginePiece: RecipePiece {
        RecipePiece(
            slot: Slot(rawValue: slot) ?? .accessory,
            categories: categories.compactMap(GarmentCategory.init(rawValue:)),
            colors: colors,
            patterns: (patterns ?? []).compactMap(Pattern.init(rawValue:)),
            materials: materials ?? [],
            optional: optional ?? false
        )
    }
}

extension RecipePiece {
    /// Short description, e.g. "Black or navy sweater (turtleneck)".
    var displayName: String {
        let names = categories.map { $0.displayName.lowercased() }
        let kind = names.isEmpty ? "piece" : names.prefix(2).joined(separator: " or ")
        let color = colors.prefix(2).joined(separator: " or ")
        let base = color.isEmpty ? kind : "\(color) \(kind)"
        let detail = requires.first.map { " (\($0.trimmingCharacters(in: .whitespaces)))" } ?? ""
        return base.prefix(1).uppercased() + base.dropFirst() + detail
    }

    /// What to buy when the closet has nothing for this piece.
    var hypotheticalItem: HypotheticalItem? {
        guard let category = categories.first else { return nil }
        return HypotheticalItem(
            category: category, color: colors.first ?? "navy",
            cut: requires.first?.trimmingCharacters(in: .whitespaces) ?? "",
            material: materials.first ?? "", pattern: patterns.first ?? .solid
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
