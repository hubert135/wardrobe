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
    /// Keywords looked up in the garment's material and type (e.g. "suede", "corduroy").
    public var materials: [String]
    /// Optional pieces (extra layers, accessories, coats for colder days) never block a match.
    public var optional: Bool

    public init(slot: Slot, categories: [GarmentCategory], colors: [String] = [], patterns: [Pattern] = [], materials: [String] = [], optional: Bool = false) {
        self.slot = slot
        self.categories = categories
        self.colors = colors.compactMap { ColorPalette.normalize($0) }
        self.patterns = patterns
        self.materials = materials.map { $0.lowercased() }
        self.optional = optional
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

    public init(id: String, title: String, summary: String = "", occasions: [Occasion] = [], styles: [Style] = [], seasons: Set<Season> = [], pieces: [RecipePiece]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.occasions = occasions
        self.styles = styles
        self.seasons = seasons
        self.pieces = pieces
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

    /// nil when the garment cannot play this piece at all (wrong category or pattern);
    /// otherwise 0.6 for the right category, up to 0.3 for color and 0.1 for material.
    public func score(_ piece: RecipePiece, garment: EngineGarment) -> Double? {
        guard piece.categories.contains(garment.category) else { return nil }
        if !piece.patterns.isEmpty, !piece.patterns.contains(garment.pattern) { return nil }
        var score = 0.6
        if piece.colors.isEmpty {
            score += 0.3
        } else if piece.colors.contains(garment.primaryColor) {
            score += 0.3
        } else if let secondary = garment.secondaryColor, piece.colors.contains(secondary) {
            score += 0.15
        }
        let text = (garment.material + " " + garment.subcategory).lowercased()
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
            let best = closet
                .filter { !$0.isArchived && !used.contains($0.id) }
                .compactMap { garment in score(piece, garment: garment).map { (garment, $0) } }
                .filter { $0.1 >= 0.9 } // right category and color
                .max { $0.1 == $1.1 ? $0.0.wearCount < $1.0.wearCount : $0.1 < $1.1 }
            if let best {
                result[index] = best.0
                used.insert(best.0.id)
            }
        }
        return result
    }
}
