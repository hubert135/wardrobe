import Foundation

/// One way to wear a recipe with the user's clothes.
public struct RecipeFill: Sendable, Hashable {
    public var recipe: StyleRecipe
    public var candidate: OutfitCandidate
    /// 0...1: how closely the garments follow the recipe (category, color, material).
    public var quality: Double
    /// Pieces the user does not own yet (builder with "Include items to buy").
    public var missing: [Slot: HypotheticalItem]
}

/// Recipe-first outfit generation: each style-guide recipe is recreated with the user's own garments.
/// The recipe decides the style, so formality numbers are not used to filter here.
public struct RecipeOutfitBuilder: Sendable {
    public var rules: OutfitRules
    public var matcher = RecipeMatcher()
    /// Best garments considered per recipe piece.
    public var optionsPerPiece = 3
    /// Below this quality a fill is not shown as following the recipe.
    public var minimumQuality = 0.75

    public init(rules: OutfitRules = OutfitRules()) { self.rules = rules }

    // MARK: Which recipes

    /// Strict on style (the user's explicit choice) and season; occasion only ranks.
    public func applies(_ recipe: StyleRecipe, to context: OutfitContext) -> Bool {
        if let season = context.season, !recipe.seasons.isEmpty, !recipe.seasons.contains(season) { return false }
        if let style = context.style, !recipe.styles.isEmpty, !recipe.styles.contains(style) { return false }
        return true
    }

    /// Formality a garment may have to play a part in this recipe: the recipe's styles, one level of slack
    /// each way (so a sporty jogger never ends up in a formal or smart casual recipe).
    public func formalityWindow(for recipe: StyleRecipe) -> ClosedRange<Int> {
        let ranges = recipe.styles.map(\.formalityRange)
        guard let lower = ranges.map(\.lowerBound).min(), let upper = ranges.map(\.upperBound).max() else { return Formality.range }
        return Formality.clamp(lower - 1)...Formality.clamp(upper + 1)
    }

    public func fitsOccasion(_ recipe: StyleRecipe, _ context: OutfitContext) -> Bool {
        guard let occasion = context.occasion else { return true }
        return recipe.occasions.isEmpty || recipe.occasions.contains(occasion)
    }

    // MARK: Filling a recipe

    /// Ways to wear `recipe` with `closet`, best first. With `allowMissing`, one required piece
    /// the user does not own may be filled with a hypothetical item described by the recipe.
    public func fills(for recipe: StyleRecipe, closet: [EngineGarment], context: OutfitContext, allowMissing: Bool = false) -> [RecipeFill] {
        // Season, weather, recent wear and archive rules still apply; formality does not.
        var eligibilityContext = context
        eligibilityContext.occasion = nil
        eligibilityContext.style = nil
        let window = formalityWindow(for: recipe)
        let knowledge = StyleKnowledge.shared
        let eligible = closet.filter {
            rules.isEligible($0, in: eligibilityContext)
                && ($0.slot == .accessory || window.contains(knowledge.effectiveFormality(for: $0)))
                && !knowledge.isExcluded($0, fromAll: recipe.styles)
        }
        let anchors = eligible.filter { context.anchorGarmentIDs.contains($0.id) }

        var pieces: [(piece: RecipePiece, options: [(EngineGarment, Double)])] = []
        var missing: [Slot: HypotheticalItem] = [:]
        var anchorsUsed = Set<UUID>()
        for piece in recipe.requiredPieces {
            if pieces.contains(where: { $0.piece.slot == piece.slot }) { continue } // one garment per slot
            var options = eligible
                .filter { $0.slot == piece.slot }
                .compactMap { garment in matcher.score(piece, garment: garment).map { (garment, $0) } }
            let slotAnchors = anchors.filter { $0.slot == piece.slot }
            if !slotAnchors.isEmpty {
                options = options.filter { option in slotAnchors.contains { $0.id == option.0.id } }
                anchorsUsed.formUnion(options.map { $0.0.id })
            }
            options.sort { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                // Rotation: prefer what was worn less recently, then less often.
                let l = lhs.0.lastWornAt ?? .distantPast, r = rhs.0.lastWornAt ?? .distantPast
                if l != r { return l < r }
                if lhs.0.wearCount != rhs.0.wearCount { return lhs.0.wearCount < rhs.0.wearCount }
                return lhs.0.id.uuidString < rhs.0.id.uuidString
            }
            if options.isEmpty {
                // Too warm for the recipe's outerwear: wear it without.
                if piece.slot == .outerwear, context.weather != nil, !rules.requiresOuterwear(context) { continue }
                guard allowMissing, missing.isEmpty, slotAnchors.isEmpty, let item = hypothetical(for: piece) else { return [] }
                missing[piece.slot] = item
                options = [(item.asGarment, 0.9)]
            }
            pieces.append((piece, Array(options.prefix(optionsPerPiece))))
        }
        // Anchors that the recipe cannot use mean the recipe does not fit the request.
        let requiredAnchors = anchors.filter { $0.slot != .accessory }
        if requiredAnchors.contains(where: { !anchorsUsed.contains($0.id) }) { return [] }

        var fills: [RecipeFill] = []
        func combine(_ index: Int, _ chosen: [Slot: EngineGarment], _ total: Double) {
            if index == pieces.count {
                guard let candidate = complete(chosen, context: context, eligible: eligible) else { return }
                fills.append(RecipeFill(recipe: recipe, candidate: candidate, quality: total / Double(max(pieces.count, 1)), missing: missing))
                return
            }
            for (garment, score) in pieces[index].options {
                var next = chosen
                next[pieces[index].piece.slot] = garment
                combine(index + 1, next, total + score)
            }
        }
        combine(0, [:], 0)
        // Closest to the recipe first; among similar fills, the better color story wins.
        return fills
            .filter { $0.quality >= minimumQuality }
            .map { ($0, rank($0, knowledge: knowledge)) }
            .sorted { $0.1 == $1.1 ? $0.0.candidate.id < $1.0.candidate.id : $0.1 > $1.1 }
            .map(\.0)
    }

    private func rank(_ fill: RecipeFill, knowledge: StyleKnowledge) -> Double {
        let garments = fill.candidate.garments
        var value = fill.quality + 0.05 * knowledge.colorHarmony(garments)
        if knowledge.hasColorClash(garments) { value -= 0.1 }
        if knowledge.hasTextureContrast(garments) { value += 0.02 }
        return value
    }

    /// Adds weather outerwear when needed and checks pattern and color rules.
    private func complete(_ chosen: [Slot: EngineGarment], context: OutfitContext, eligible: [EngineGarment]) -> OutfitCandidate? {
        var pieces = chosen
        for slot in Slot.required where pieces[slot] == nil { return nil }
        if rules.requiresOuterwear(context), pieces[.outerwear]?.category.isWeatherOuterwear != true {
            // Cold day: add the most neutral warm layer the user has.
            let layers = eligible.filter { $0.category.isWeatherOuterwear }
                .sorted { ($0.isNeutral ? 0 : 1, $0.wearCount) < ($1.isNeutral ? 0 : 1, $1.wearCount) }
            guard let layer = layers.first(where: { rules.hasHarmoniousColors(Array(pieces.values) + [$0]) }) else { return nil }
            pieces[.outerwear] = layer
        }
        let candidate = OutfitCandidate(pieces: pieces)
        guard rules.hasCompatiblePatterns(candidate.coreGarments), rules.hasHarmoniousColors(candidate.garments),
              rules.hasConsistentSuit(candidate), !StyleKnowledge.shared.hasTextureClash(candidate)
        else { return nil }
        return candidate
    }

    private func hypothetical(for piece: RecipePiece) -> HypotheticalItem? {
        guard let category = piece.categories.first else { return nil }
        return HypotheticalItem(
            category: category, color: piece.colors.first ?? "navy", cut: piece.requires.first ?? "",
            material: piece.materials.first ?? "", pattern: piece.patterns.first ?? .solid
        )
    }

    // MARK: Choosing outfits

    /// The best recipe outfits for the context: one per recipe, visibly different, rotating away from
    /// recipes shown recently (`recentlyShown`, most recent last).
    public func suggestions(
        closet: [EngineGarment],
        context: OutfitContext,
        count: Int,
        recentlyShown: [String] = [],
        allowMissing: Bool = false
    ) -> [RecipeFill] {
        struct Option { var fills: [RecipeFill]; var score: Double }
        var options: [Option] = []
        for recipe in context.recipes where applies(recipe, to: context) {
            let fills = self.fills(for: recipe, closet: closet, context: context, allowMissing: allowMissing)
            guard let best = fills.first else { continue }
            var score = best.quality
            if fitsOccasion(recipe, context) { score += 0.25 }
            if !best.missing.isEmpty { score -= 0.3 }
            if let index = recentlyShown.lastIndex(of: recipe.id) {
                // Shown a moment ago: push far down; shown earlier: push down less.
                score -= 1.0 - Double(recentlyShown.count - 1 - index) * 0.1
            }
            options.append(Option(fills: Array(fills.prefix(4)), score: score))
        }
        options.sort { $0.score == $1.score ? $0.fills[0].recipe.id < $1.fills[0].recipe.id : $0.score > $1.score }

        var picked: [RecipeFill] = []
        for option in options where picked.count < count {
            // A recipe shown recently comes back with different garments when it has them.
            var variants = option.fills
            if variants.count > 1, recentlyShown.contains(variants[0].recipe.id) {
                variants.append(variants.removeFirst())
            }
            // The recipe's best fill that is not too similar to what is already picked.
            let fill = variants.first { fill in
                picked.allSatisfy { Set($0.candidate.coreGarments.map(\.id)).intersection(fill.candidate.coreGarments.map(\.id)).count <= 2 }
            }
            if let fill { picked.append(fill) }
        }
        return picked
    }
}
