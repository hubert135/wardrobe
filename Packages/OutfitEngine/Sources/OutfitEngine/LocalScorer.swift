import Foundation

/// Offline ranking used when the AI ranking is unavailable, and to pre-sort candidates
/// before they are sent to the AI.
public struct LocalScorer: Sendable {
    public var rules: OutfitRules

    public init(rules: OutfitRules = OutfitRules()) { self.rules = rules }

    public func score(_ candidate: OutfitCandidate, in context: OutfitContext) -> Double {
        let garments = candidate.garments
        let core = candidate.coreGarments
        var score = 0.0

        // Color harmony: a calm neutral base reads as intentional.
        switch rules.accentColors(in: garments).count {
        case 0: score += 1.5
        case 1: score += 2.0 // one point of color is the sweet spot
        default: score += 0.5
        }

        // Formality close to the target for this occasion/style.
        let average = Double(core.map(\.formality).reduce(0, +)) / Double(max(core.count, 1))
        score -= abs(average - context.targetFormality)

        // Classic menswear pairings.
        score += pairingBonus(candidate)

        // Personal preferences.
        let colors = Set(garments.flatMap { [$0.primaryColor] + ($0.secondaryColor.map { [$0] } ?? []) })
        score += 0.4 * Double(colors.intersection(context.preferences.favoriteColors).count)
        score -= 5.0 * Double(colors.intersection(context.preferences.avoidedColors).count)

        // Weather comfort.
        if let weather = context.weather {
            let t = weather.feelsLikeC
            let hasOuter = candidate.pieces[.outerwear] != nil
            if (10..<17).contains(t) && hasOuter { score += 0.5 }
            if t >= 22 && hasOuter && candidate.pieces[.outerwear]?.category != .blazer { score -= 0.5 }
            if rules.isRainy(weather), candidate.pieces[.outerwear]?.category.isWeatherOuterwear == true { score += 0.3 }
        }

        // Rotation: prefer pieces that have not been worn for a while.
        for garment in core where !garment.isHypothetical {
            if let last = garment.lastWornAt {
                let days = max(0, context.date.timeIntervalSince(last) / 86_400)
                score += min(days, 14) / 14 * 0.3
            } else {
                score += 0.2
            }
        }

        // Owned outfits are preferred over ones that need a purchase.
        score -= 0.4 * Double(candidate.hypotheticalGarments.count)

        // Proven combinations from the user's style guide.
        if let match = RecipeMatcher().bestMatch(for: candidate, in: context) {
            score += 2.5 * match.quality
        }
        return score
    }

    public func pairingBonus(_ candidate: OutfitCandidate) -> Double {
        let top = candidate.pieces[.top]?.primaryColor
        let bottom = candidate.pieces[.bottom]?.primaryColor
        let shoes = candidate.pieces[.shoes]?.primaryColor
        let outer = candidate.pieces[.outerwear]?.primaryColor
        var bonus = 0.0

        let upper = [top, outer].compactMap { $0 }
        if let bottom {
            if upper.contains("navy") && ["beige", "grey", "khaki", "cream", "tan", "white"].contains(bottom) { bonus += 0.6 }
            if bottom == "navy" && upper.contains(where: { ["white", "light blue", "cream", "grey"].contains($0) }) { bonus += 0.4 }
            if bottom == "denim" && upper.contains(where: { ["white", "navy", "grey", "olive", "light blue"].contains($0) }) { bonus += 0.4 }
            if upper.contains(bottom) && candidate.pieces[.outerwear]?.category != .blazer { bonus -= 0.3 } // tonal mismatch risk
        }
        if let shoes {
            if ["brown", "tan"].contains(shoes) && [bottom, outer].contains(where: { ["navy", "beige", "grey", "denim", "olive", "khaki"].contains($0 ?? "") }) { bonus += 0.4 }
            if shoes == "black" && ["grey", "charcoal", "black", "navy"].contains(bottom ?? "") { bonus += 0.3 }
            if shoes == "black" && ["beige", "khaki", "tan"].contains(bottom ?? "") { bonus -= 0.3 }
        }
        return bonus
    }

    public func rank(_ candidates: [OutfitCandidate], in context: OutfitContext) -> [ScoredCandidate] {
        // Check which recipes apply once, not for every candidate.
        var scoringContext = context
        let matcher = RecipeMatcher()
        scoringContext.recipes = context.recipes.filter { matcher.applies($0, to: context) }
        // Ids are computed once per candidate (building them inside the sort was very slow on big closets).
        let keyed = candidates.map { (ScoredCandidate(candidate: $0, score: score($0, in: scoringContext)), $0.id) }
        return keyed
            .sorted { $0.0.score == $1.0.score ? $0.1 < $1.1 : $0.0.score > $1.0.score }
            .map(\.0)
    }

    /// Greedy selection of high-scoring but visibly different outfits: each round picks the candidate
    /// with the best score after a penalty for every garment it shares beyond one with an earlier pick.
    /// Only the best `poolLimit` candidates are considered, and overlaps are updated incrementally,
    /// so this stays fast even with thousands of candidates.
    public func selectDiverse(_ ranked: [ScoredCandidate], count: Int, overlapPenalty: Double = 1.0, poolLimit: Int = 400) -> [ScoredCandidate] {
        guard count > 0, !ranked.isEmpty else { return [] }
        let pool = Array(ranked.prefix(max(poolLimit, count)))
        let garmentSets = pool.map { Set($0.candidate.garmentIDs) }
        var maxOverlap = [Int](repeating: 0, count: pool.count)
        var taken = [Bool](repeating: false, count: pool.count)
        var picked: [ScoredCandidate] = []

        while picked.count < min(count, pool.count) {
            var bestIndex = -1
            var bestValue = -Double.infinity
            for index in pool.indices where !taken[index] {
                let value = pool[index].score - overlapPenalty * Double(max(0, maxOverlap[index] - 1))
                if value > bestValue {
                    bestValue = value
                    bestIndex = index
                }
            }
            guard bestIndex >= 0 else { break }
            taken[bestIndex] = true
            picked.append(pool[bestIndex])
            for index in pool.indices where !taken[index] {
                maxOverlap[index] = max(maxOverlap[index], garmentSets[index].intersection(garmentSets[bestIndex]).count)
            }
        }
        return picked
    }
}
