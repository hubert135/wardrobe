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
        candidates
            .map { ScoredCandidate(candidate: $0, score: score($0, in: context)) }
            .sorted { $0.score == $1.score ? $0.candidate.id < $1.candidate.id : $0.score > $1.score }
    }

    /// Greedy selection of high-scoring but visibly different outfits: each round picks the candidate
    /// with the best score after a penalty for every garment it shares beyond one with an earlier pick.
    public func selectDiverse(_ ranked: [ScoredCandidate], count: Int, overlapPenalty: Double = 1.0) -> [ScoredCandidate] {
        guard count > 0 else { return [] }
        var picked: [ScoredCandidate] = []
        var remaining = ranked
        while picked.count < count, !remaining.isEmpty {
            var bestIndex = 0
            var bestValue = -Double.infinity
            for (index, item) in remaining.enumerated() {
                let overlap = picked.map { $0.candidate.sharedGarmentCount(with: item.candidate) }.max() ?? 0
                let value = item.score - overlapPenalty * Double(max(0, overlap - 1))
                if value > bestValue {
                    bestValue = value
                    bestIndex = index
                }
            }
            picked.append(remaining.remove(at: bestIndex))
        }
        return picked
    }
}
