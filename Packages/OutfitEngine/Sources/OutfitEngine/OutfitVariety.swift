import Foundation

/// The idea behind a look. Suggestions in one set should come from different ideas where the closet allows.
public enum Look: String, Codable, CaseIterable, Sendable, Identifiable {
    case business, office, evening
    case smartWeekend = "smart_weekend"
    case relaxed, rugged, outdoor, athleisure, active, travel

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .business: "Business"
        case .office: "Office"
        case .evening: "Evening"
        case .smartWeekend: "Smart weekend"
        case .relaxed: "Relaxed weekend"
        case .rugged: "Rugged"
        case .outdoor: "Outdoor"
        case .athleisure: "City sporty"
        case .active: "Active"
        case .travel: "Travel"
        }
    }

    /// For recipes without an explicit look (e.g. style-guide formulas): from styles, occasions and key pieces.
    static func infer(for recipe: StyleRecipe) -> Look {
        let text = recipe.pieces.flatMap { $0.materials + $0.requires }.joined(separator: " ")
        let styles = Set(recipe.styles)
        let first = recipe.occasions.first
        let has = { (words: [String]) in words.contains { text.contains($0) } }
        if styles.contains(.formal) {
            if has(["suit"]) || first == .businessMeeting { return .business }
            return first == .dinner || first == .event || has(["velvet", "turtleneck"]) ? .evening : .office
        }
        if styles.contains(.sporty) {
            return has(["trail", "technical", "windbreaker", "cargo", "fleece"]) ? .outdoor : .athleisure
        }
        if styles.contains(.smartCasual) && !styles.contains(.casual) {
            return first == .dinner || first == .event ? .evening : .office
        }
        if styles.contains(.smartCasual) { return .smartWeekend }
        return has(["parka", "waxed", "workwear", "flannel", "fatigue", "overshirt", "boot"]) ? .rugged : .relaxed
    }
}

extension StyleRecipe {
    /// The recipe's look, explicit or inferred.
    public var effectiveLook: Look { look ?? Look.infer(for: self) }
}

/// What makes two outfits different. Shoes and accessories never count.
public enum VarietyDimension: String, CaseIterable, Sendable {
    /// The trousers, jeans, chinos or shorts.
    case bottom
    /// The top, or the layer worn over it as part of the look (a blazer, a cardigan-like jacket).
    case upper
    /// The shape: wide high-waisted vs slim vs tailored legs, a chunky top or not.
    case silhouette
    /// The idea of the look: office, evening, relaxed weekend...
    case look
}

/// The parts of an outfit that decide whether it is a different outfit.
public struct OutfitSignature: Sendable, Hashable {
    public var bottom: String?
    public var top: String?
    /// Outer layer that is part of the look (not a coat added only for the cold).
    public var layer: String?
    public var silhouette: String
    public var look: Look?

    public init(candidate: OutfitCandidate, recipe: StyleRecipe?, knowledge: StyleKnowledge = .shared) {
        func identity(_ garment: EngineGarment?) -> String? {
            guard let garment else { return nil }
            return garment.isHypothetical
                ? "new:\(garment.category.rawValue)|\(garment.primaryColor)|\(garment.subcategory)"
                : garment.id.uuidString
        }
        bottom = identity(candidate.pieces[.bottom])
        top = identity(candidate.pieces[.top])
        let outer = candidate.pieces[.outerwear]
        let layerIsPartOfLook = recipe.map { recipe in recipe.requiredPieces.contains { $0.slot == .outerwear } } ?? (outer?.category == .blazer)
        layer = layerIsPartOfLook ? identity(outer) : nil
        silhouette = knowledge.silhouette(of: candidate)
        look = recipe?.effectiveLook
    }

    public func differences(from other: OutfitSignature) -> Set<VarietyDimension> {
        var result = Set<VarietyDimension>()
        if bottom != other.bottom { result.insert(.bottom) }
        // With a jacket that is part of the look, the jacket is what you see; without one, the top.
        if layer != other.layer || (layer == nil && top != other.top) { result.insert(.upper) }
        if silhouette != other.silhouette { result.insert(.silhouette) }
        if let look, let otherLook = other.look, look != otherLook { result.insert(.look) }
        return result
    }
}

/// The rule for one set of suggestions: every two outfits differ in at least `minimumDifferences` of
/// bottom, top/layer, silhouette and look, and never share the bottom together with the top or the jacket.
/// Shoes and accessories never make an outfit different.
public struct OutfitVariety: Sendable {
    public var minimumDifferences: Int

    public init(minimumDifferences: Int = 2) { self.minimumDifferences = minimumDifferences }

    /// Daily suggestions: three genuinely different outfits.
    public static let suggestions = OutfitVariety(minimumDifferences: 2)
    /// Builder with chosen pieces: the pinned piece is the same in every outfit, so one difference is enough.
    public static let builder = OutfitVariety(minimumDifferences: 1)

    public func areDistinct(_ a: OutfitSignature, _ b: OutfitSignature) -> Bool {
        // Same trousers with the same top, or with the same jacket (a suit with another shirt), is the same outfit.
        if a.bottom == b.bottom && (a.top == b.top || (a.layer != nil && a.layer == b.layer)) { return false }
        return a.differences(from: b).count >= minimumDifferences
    }

    public func areDistinct(_ a: EngineOutfit, _ b: EngineOutfit) -> Bool {
        areDistinct(a.signature, b.signature)
    }

    public func isDistinctSet(_ outfits: [EngineOutfit]) -> Bool {
        for i in outfits.indices {
            for j in outfits.indices where j > i && !areDistinct(outfits[i], outfits[j]) { return false }
        }
        return true
    }

    /// Keeps outfits in order, dropping any that is too close to one already kept.
    public func distinct(_ outfits: [EngineOutfit], limit: Int = .max) -> [EngineOutfit] {
        var kept: [EngineOutfit] = []
        for outfit in outfits where kept.count < limit && kept.allSatisfy({ areDistinct($0, outfit) }) {
            kept.append(outfit)
        }
        return kept
    }
}

extension EngineOutfit {
    public var signature: OutfitSignature { OutfitSignature(candidate: candidate, recipe: recipe) }
}

/// One missing piece that would unlock another, genuinely different look.
public struct UnlockSuggestion: Sendable, Hashable, Identifiable {
    public var recipe: StyleRecipe
    public var piece: RecipePiece
    public var item: HypotheticalItem
    public var id: String { recipe.id + "|" + item.searchQuery }
}

/// Suggestions for one request, plus what to buy when the closet cannot fill the set honestly.
public struct SuggestionSet: Sendable {
    public var outfits: [EngineOutfit]
    public var unlocks: [UnlockSuggestion]

    public init(outfits: [EngineOutfit], unlocks: [UnlockSuggestion] = []) {
        self.outfits = outfits
        self.unlocks = unlocks
    }
}
