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
                // Too warm for the recipe's outerwear: wear it without. Otherwise a missing jacket is missing:
                // a track-jacket look without the track jacket is just a T-shirt and jeans.
                if piece.slot == .outerwear, let weather = context.weather, isTooWarm(for: piece, feelsLike: weather.feelsLikeC) { continue }
                guard allowMissing, missing.isEmpty, slotAnchors.isEmpty, let item = piece.hypotheticalItem else { return [] }
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
        // Closest to the recipe first; among equally close fills, the better color story wins.
        struct Ranked { var fill: RecipeFill; var quality: Double; var story: Double; var id: String }
        var ranked: [Ranked] = []
        for fill in fills where fill.quality >= minimumQuality {
            ranked.append(Ranked(fill: fill, quality: (fill.quality * 100).rounded(), story: colorStory(fill, knowledge: knowledge), id: fill.candidate.id))
        }
        ranked.sort { (a: Ranked, b: Ranked) -> Bool in
            if a.quality != b.quality { return a.quality > b.quality }
            if a.story != b.story { return a.story > b.story }
            return a.id < b.id
        }
        return ranked.map { $0.fill }
    }

    private func colorStory(_ fill: RecipeFill, knowledge: StyleKnowledge) -> Double {
        let garments = fill.candidate.garments
        var value = knowledge.colorHarmony(garments)
        if knowledge.hasColorClash(garments) { value -= 2 }
        if knowledge.hasTextureContrast(garments) { value += 0.4 }
        return value
    }

    /// Whether every kind of outerwear the piece allows is too warm for the day.
    private func isTooWarm(for piece: RecipePiece, feelsLike t: Double) -> Bool {
        let config = rules.config
        return piece.categories.allSatisfy { category in
            switch category {
            case .coat: t > config.coatMaxC
            case .jacket: t > config.jacketMaxC
            case .blazer: t > config.blazerMaxC
            default: false
            }
        }
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

    // MARK: Choosing outfits

    /// Ways of wearing one template considered when building a set.
    public var variantsPerRecipe = 8

    private struct Option {
        var recipe: StyleRecipe
        var variants: [(fill: RecipeFill, signature: OutfitSignature)]
        var score: Double
    }

    /// The best set of genuinely different recipe outfits: each from a different template, every two of them
    /// different by `variety` (bottom, top or layer, silhouette, look), preferring templates with a look not yet
    /// in the set and rotating away from recipes shown recently (`recentlyShown`, most recent last).
    /// A candidate too close to the set is rejected and the next way of wearing the template, or the next
    /// template, is tried. Returns fewer than `count` rather than near-duplicates.
    public func suggestions(
        closet: [EngineGarment],
        context: OutfitContext,
        count: Int,
        recentlyShown: [String] = [],
        allowMissing: Bool = false,
        variety: OutfitVariety = .suggestions
    ) -> [RecipeFill] {
        selection(closet: closet, context: context, count: count, recentlyShown: recentlyShown, allowMissing: allowMissing, variety: variety).fills
    }

    /// `suggestions` plus, when the closet cannot fill `count` honestly, single pieces that would add another look.
    public func selection(
        closet: [EngineGarment],
        context: OutfitContext,
        count: Int,
        recentlyShown: [String] = [],
        allowMissing: Bool = false,
        variety: OutfitVariety = .suggestions
    ) -> (fills: [RecipeFill], unlocks: [UnlockSuggestion]) {
        let day = Calendar(identifier: .gregorian).ordinality(of: .day, in: .year, for: context.date) ?? 0
        var options: [Option] = []
        var applicable: [StyleRecipe] = []
        for recipe in context.recipes where applies(recipe, to: context) {
            applicable.append(recipe)
            let fills = self.fills(for: recipe, closet: closet, context: context, allowMissing: allowMissing)
            guard let best = fills.first else { continue }
            var score = best.quality
            // The occasion comes first: a new idea never beats an outfit made for the day.
            if fitsOccasion(recipe, context) { score += 0.6 }
            if !best.missing.isEmpty { score -= 0.3 }
            if let index = recentlyShown.lastIndex(of: recipe.id) {
                // Shown a moment ago: push far down; shown earlier: push down less.
                score -= 1.0 - Double(recentlyShown.count - 1 - index) * 0.1
            }
            // Equally good templates take turns from day to day instead of always appearing in the same order.
            score += Self.rotation(recipe.id, day: day)
            var variants = fills.prefix(variantsPerRecipe).map { (fill: $0, signature: OutfitSignature(candidate: $0.candidate, recipe: recipe)) }
            // A recipe shown recently comes back with different garments when it has them.
            if variants.count > 1, recentlyShown.contains(recipe.id) { variants.append(variants.removeFirst()) }
            options.append(Option(recipe: recipe, variants: variants, score: score))
        }

        var picked: [(fill: RecipeFill, signature: OutfitSignature)] = []
        var usedLooks = Set<Look>()
        while picked.count < count {
            var best: (option: Int, variant: Int, value: Double, id: String)?
            for (index, option) in options.enumerated() {
                // Variants too close to an outfit already in the set are rejected; of the rest, the one that
                // differs most from the set wins (a little quality is traded for a clearly different outfit).
                var chosen: (variant: Int, value: Double)?
                for (position, candidate) in option.variants.enumerated() {
                    var fewestDifferences = VarietyDimension.allCases.count
                    var acceptable = true
                    for earlier in picked {
                        guard variety.areDistinct(earlier.signature, candidate.signature) else { acceptable = false; break }
                        fewestDifferences = min(fewestDifferences, earlier.signature.differences(from: candidate.signature).count)
                    }
                    guard acceptable else { continue }
                    let value = candidate.fill.quality + 0.05 * Double(fewestDifferences) - 0.01 * Double(position)
                    if chosen == nil || value > chosen!.value { chosen = (position, value) }
                }
                guard let variantChoice = chosen, let firstQuality = option.variants.first?.fill.quality else { continue }
                let variant = variantChoice.variant
                var value = option.score - firstQuality + variantChoice.value
                // Among outfits for the occasion, a new idea beats one more version of an idea already in the set.
                if !usedLooks.contains(option.recipe.effectiveLook) { value += 0.3 }
                if let current = best, value < current.value || (value == current.value && option.recipe.id > current.id) { continue }
                best = (index, variant, value, option.recipe.id)
            }
            guard let choice = best else { break }
            let option = options.remove(at: choice.option)
            picked.append(option.variants[choice.variant])
            usedLooks.insert(option.recipe.effectiveLook)
        }

        let fills = picked.map { $0.fill }
        guard fills.count < count, !allowMissing else { return (fills, []) }
        let pickedIDs = Set(fills.map(\.recipe.id))
        let unlocks = unlockSuggestions(
            recipes: applicable.filter { !pickedIDs.contains($0.id) }, picked: picked.map { $0.signature },
            closet: closet, context: context, limit: min(2, count - fills.count), variety: variety
        )
        return (fills, unlocks)
    }

    /// Templates the closet misses exactly one piece for, whose outfit would be different from the set.
    private func unlockSuggestions(
        recipes: [StyleRecipe], picked: [OutfitSignature], closet: [EngineGarment], context: OutfitContext,
        limit: Int, variety: OutfitVariety
    ) -> [UnlockSuggestion] {
        var set = picked
        var result: [UnlockSuggestion] = []
        var items = Set<String>()
        let ordered = recipes.sorted { a, b in
            let fa = fitsOccasion(a, context), fb = fitsOccasion(b, context)
            return fa != fb ? fa : a.id < b.id
        }
        for recipe in ordered where result.count < limit {
            for fill in fills(for: recipe, closet: closet, context: context, allowMissing: true) where !fill.missing.isEmpty {
                let signature = OutfitSignature(candidate: fill.candidate, recipe: recipe)
                guard set.allSatisfy({ variety.areDistinct($0, signature) }),
                      let missing = fill.missing.first,
                      let piece = recipe.requiredPieces.first(where: { $0.slot == missing.key }),
                      items.insert(missing.value.searchQuery).inserted
                else { continue }
                result.append(UnlockSuggestion(recipe: recipe, piece: piece, item: missing.value))
                set.append(signature)
                break
            }
        }
        return result
    }

    /// A small, stable per-day offset (0...0.08) so ties between equally good templates rotate daily.
    static func rotation(_ id: String, day: Int) -> Double {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in "\(id)#\(day)".utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return Double(hash % 1000) / 1000 * 0.08
    }
}
