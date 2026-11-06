import Foundation

/// One piece of a style recipe, described by attributes (e.g. "olive parka" or "brown suede boots").
public struct RecipePiece: Sendable, Hashable, Codable {
    public var slot: Slot
    /// Any of these categories fits the piece.
    public var categories: [GarmentCategory]
    /// Palette color names; empty means any color.
    public var colors: [String]
    /// Required patterns; empty means any pattern.
    public var patterns: [Pattern]
    /// Preferred keywords looked up in the garment's material and type (e.g. "suede", "oxford"): a small bonus.
    public var materials: [String]
    /// Keywords that define the piece: at least one must appear ("turtleneck", "suit"). Empty: no requirement.
    public var requires: [String]
    /// The garment may not contain any of these (e.g. "sneaker" for a dress shoe).
    public var avoid: [String]
    /// Optional pieces (extra layers, accessories, coats for colder days) never block a match.
    public var optional: Bool

    public init(
        slot: Slot, categories: [GarmentCategory], colors: [String] = [], patterns: [Pattern] = [],
        materials: [String] = [], requires: [String] = [], avoid: [String] = [], optional: Bool = false
    ) {
        self.slot = slot
        self.categories = categories
        self.colors = colors.compactMap { ColorPalette.normalize($0) }
        self.patterns = patterns
        self.materials = materials.map { $0.lowercased() }
        self.requires = requires.map { $0.lowercased() }
        self.avoid = avoid.map { $0.lowercased() }
        self.optional = optional
    }

    private enum CodingKeys: String, CodingKey { case slot, categories, colors, patterns, materials, requires, avoid, optional }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            slot: try c.decode(Slot.self, forKey: .slot),
            categories: try c.decode([GarmentCategory].self, forKey: .categories),
            colors: try c.decodeIfPresent([String].self, forKey: .colors) ?? [],
            patterns: try c.decodeIfPresent([Pattern].self, forKey: .patterns) ?? [],
            materials: try c.decodeIfPresent([String].self, forKey: .materials) ?? [],
            requires: try c.decodeIfPresent([String].self, forKey: .requires) ?? [],
            avoid: try c.decodeIfPresent([String].self, forKey: .avoid) ?? [],
            optional: try c.decodeIfPresent(Bool.self, forKey: .optional) ?? false
        )
    }

    /// Whether the piece asks for a suit jacket or suit trousers.
    var isSuitPiece: Bool { (requires + materials).contains { $0.contains("suit") } }

    /// Short description, e.g. "Black or navy sweater (turtleneck)".
    public var displayName: String {
        let names = categories.map { $0.displayName.lowercased() }
        let kind = names.isEmpty ? "piece" : names.prefix(2).joined(separator: " or ")
        let color = colors.prefix(2).joined(separator: " or ")
        let base = color.isEmpty ? kind : color + " " + kind
        let detail = requires.first.map { " (" + $0.trimmingCharacters(in: .whitespaces) + ")" } ?? ""
        return base.prefix(1).uppercased() + String(base.dropFirst()) + detail
    }

    /// What to buy when the closet has nothing for this piece.
    public var hypotheticalItem: HypotheticalItem? {
        guard let category = categories.first else { return nil }
        return HypotheticalItem(
            category: category, color: colors.first ?? "navy",
            cut: requires.first?.trimmingCharacters(in: .whitespaces) ?? "",
            material: materials.first ?? "", pattern: patterns.first ?? .solid
        )
    }
}

/// A proven outfit formula, e.g. from a style guide: which pieces, in which colors and materials.
public struct StyleRecipe: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    public var occasions: [Occasion]
    public var styles: [Style]
    /// Empty means all seasons.
    public var seasons: Set<Season>
    public var pieces: [RecipePiece]
    /// The idea of the look; inferred when nil (see `effectiveLook`).
    public var look: Look?

    public init(
        id: String, title: String, summary: String = "", occasions: [Occasion] = [], styles: [Style] = [],
        seasons: Set<Season> = [], pieces: [RecipePiece], look: Look? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.occasions = occasions
        self.styles = styles
        self.seasons = seasons
        self.pieces = pieces
        self.look = look
    }

    public var requiredPieces: [RecipePiece] { pieces.filter { !$0.optional } }
}

public struct RecipeMatch: Sendable, Hashable {
    public var recipe: StyleRecipe
    /// 0...1: 1 means every required piece matches in category, color, pattern and material.
    public var quality: Double
}

/// Checks how well outfits and closets follow style recipes. Pure and deterministic.
public struct RecipeMatcher: Sendable {
    /// Below this quality an outfit is not presented as following a recipe.
    public var minimumQuality: Double = 0.75

    public init() {}

    /// nil when the garment cannot play this piece at all (wrong category, pattern or type, or a suit piece
    /// worn as a separate); otherwise 0.6 for the right category, up to 0.3 for color and 0.1 for material.
    public func score(_ piece: RecipePiece, garment: EngineGarment) -> Double? {
        guard piece.categories.contains(garment.category) else { return nil }
        if !piece.patterns.isEmpty, !piece.patterns.contains(garment.pattern) { return nil }
        let text = garment.searchText
        if piece.avoid.contains(where: { text.contains($0) }) { return nil }
        if !piece.requires.isEmpty, !piece.requires.contains(where: { text.contains($0) }) { return nil }
        if StyleKnowledge.shared.isSuitPiece(garment), !piece.isSuitPiece { return nil }
        var score = 0.6
        if piece.colors.isEmpty {
            score += 0.3
        } else if piece.colors.contains(garment.primaryColor) {
            score += 0.3
        } else if let secondary = garment.secondaryColor, piece.colors.contains(secondary) {
            score += 0.15
        }
        if piece.materials.isEmpty || piece.materials.contains(where: { text.contains($0) }) {
            score += 0.1
        }
        return score
    }

    /// Whether the recipe suits this occasion, style and season.
    public func applies(_ recipe: StyleRecipe, to context: OutfitContext) -> Bool {
        if let season = context.season, !recipe.seasons.isEmpty, !recipe.seasons.contains(season) { return false }
        let occasionFits = context.occasion.map { recipe.occasions.isEmpty || recipe.occasions.contains($0) } ?? true
        let styleFits = context.style.map { recipe.styles.isEmpty || recipe.styles.contains($0) } ?? true
        return occasionFits || styleFits
    }

    /// How well a finished outfit follows a recipe, or nil if a required piece is missing.
    public func match(_ candidate: OutfitCandidate, recipe: StyleRecipe) -> RecipeMatch? {
        let required = recipe.requiredPieces
        guard !required.isEmpty else { return nil }
        var total = 0.0
        for piece in required {
            guard let garment = candidate.pieces[piece.slot], let score = score(piece, garment: garment) else { return nil }
            total += score
        }
        return RecipeMatch(recipe: recipe, quality: total / Double(required.count))
    }

    /// The best-fitting recipe for an outfit in this context, if it is good enough.
    public func bestMatch(for candidate: OutfitCandidate, in context: OutfitContext) -> RecipeMatch? {
        context.recipes
            .filter { applies($0, to: context) }
            .compactMap { match(candidate, recipe: $0) }
            .filter { $0.quality >= minimumQuality }
            .max { $0.quality == $1.quality ? $0.recipe.id > $1.recipe.id : $0.quality < $1.quality }
    }

    /// For each required piece (by index in `recipe.pieces`), the user's best garment for it, if any.
    public func ownedPieces(of recipe: StyleRecipe, in closet: [EngineGarment]) -> [Int: EngineGarment] {
        var result: [Int: EngineGarment] = [:]
        var used = Set<UUID>()
        for (index, piece) in recipe.pieces.enumerated() where !piece.optional {
            var best: EngineGarment?
            var bestScore = 0.0
            for garment in closet where !garment.isArchived && !used.contains(garment.id) {
                // Needs the right category and color (0.9); ties go to the more worn favorite.
                guard let value = score(piece, garment: garment), value >= 0.9 else { continue }
                let isBetter = value > bestScore || (value == bestScore && garment.wearCount > (best?.wearCount ?? -1))
                if isBetter {
                    best = garment
                    bestScore = value
                }
            }
            if let best {
                result[index] = best
                used.insert(best.id)
            }
        }
        return result
    }
}
