import Foundation

/// Facade over the deterministic outfit pipeline. Pure: no UI, no network, no persistence.
public struct OutfitEngine: Sendable {
    public var config: EngineConfig
    public var rules: OutfitRules
    public var builder: CandidateBuilder
    public var scorer: LocalScorer
    public var accessories: AccessoryMatcher
    public var writer: ReasoningWriter

    public init(config: EngineConfig = .default) {
        self.config = config
        let rules = OutfitRules(config: config)
        self.rules = rules
        self.builder = CandidateBuilder(rules: rules)
        self.scorer = LocalScorer(rules: rules)
        self.accessories = AccessoryMatcher(rules: rules)
        self.writer = ReasoningWriter(rules: rules)
    }

    /// Whether the closet is big enough to produce meaningful outfits.
    public func hasEnoughGarments(_ closet: [EngineGarment]) -> Bool {
        closet.filter { !$0.isArchived && $0.slot != nil }.count >= config.minimumClosetSize
    }

    /// Valid candidates sorted by local score, limited to a shortlist suitable for AI ranking.
    public func shortlist(closet: [EngineGarment], context: OutfitContext, limit: Int = 30) -> [ScoredCandidate] {
        let candidates = builder.build(closet: closet, context: context)
        let ranked = scorer.rank(candidates, in: context)
        // Keep variety in the shortlist so the AI has real choices.
        return scorer.selectDiverse(ranked, count: min(limit, ranked.count))
    }

    /// Fully offline suggestions: deterministic candidates, local scoring, template wording.
    public func suggest(closet: [EngineGarment], context: OutfitContext, count: Int = 3) -> [EngineOutfit] {
        let candidates = builder.build(closet: closet, context: context)
        let picked = scorer.selectDiverse(scorer.rank(candidates, in: context), count: count)
        return picked.map { finalize($0.candidate, score: $0.score, closet: closet, context: context) }
    }

    /// Adds an accessory and wording. Pass `title`/`reasoning` from the AI to override the templates.
    public func finalize(
        _ candidate: OutfitCandidate,
        score: Double? = nil,
        closet: [EngineGarment],
        context: OutfitContext,
        title: String? = nil,
        reasoning: String? = nil,
        missing: [Slot: HypotheticalItem] = [:]
    ) -> EngineOutfit {
        let full = accessories.attach(to: candidate, from: closet, context: context)
        return EngineOutfit(
            candidate: full,
            title: title ?? writer.title(for: full),
            reasoning: reasoning ?? writer.reasoning(for: full, in: context),
            score: score ?? scorer.score(full, in: context),
            missing: missing
        )
    }

    /// Garments that could replace the piece in `slot` while keeping the outfit valid, best first.
    public func alternatives(for slot: Slot, in outfit: EngineOutfit, closet: [EngineGarment], context: OutfitContext) -> [EngineGarment] {
        let current = outfit.pieces[slot]
        let options = closet.filter { $0.slot == slot && $0.id != current?.id && rules.isEligible($0, in: context) }
        let scored: [(EngineGarment, Double)] = options.compactMap { garment in
            var pieces = outfit.pieces
            pieces[slot] = garment
            let candidate = OutfitCandidate(pieces: pieces)
            if slot == .accessory {
                guard rules.hasHarmoniousColors(candidate.garments), rules.hasCompatiblePatterns(candidate.garments) else { return nil }
            } else {
                guard rules.isValid(candidate, in: context) else { return nil }
            }
            return (garment, scorer.score(candidate, in: context))
        }
        return scored.sorted { $0.1 == $1.1 ? $0.0.id.uuidString < $1.0.id.uuidString : $0.1 > $1.1 }.map(\.0)
    }

    /// Replaces one piece with the best alternative. Returns `nil` if there is none.
    public func swap(_ slot: Slot, in outfit: EngineOutfit, closet: [EngineGarment], context: OutfitContext) -> EngineOutfit? {
        guard let replacement = alternatives(for: slot, in: outfit, closet: closet, context: context).first else { return nil }
        var pieces = outfit.pieces
        pieces[slot] = replacement
        let candidate = OutfitCandidate(pieces: pieces)
        var missing = outfit.missing
        missing[slot] = nil
        return EngineOutfit(
            candidate: candidate,
            title: writer.title(for: candidate),
            reasoning: writer.reasoning(for: candidate, in: context),
            score: scorer.score(candidate, in: context),
            missing: missing
        )
    }

    /// Outfit builder. Anchors come from `context.anchorGarmentIDs`.
    /// With `includeMissing`, outfits may contain one piece from `catalog` that the user does not own yet.
    public func build(
        closet: [EngineGarment],
        context: OutfitContext,
        includeMissing: Bool,
        catalog: [HypotheticalItem] = StarterCatalog.items,
        count: Int = 5
    ) -> [EngineOutfit] {
        let missingItems = includeMissing ? catalog.filter { !$0.isOwned(in: closet) } : []
        let extras = missingItems.map(\.asGarment)
        let candidates = builder.build(closet: closet, context: context, extras: extras, maxHypotheticals: includeMissing ? 1 : 0)
        let picked = scorer.selectDiverse(scorer.rank(candidates, in: context), count: count)
        let itemsByID = Dictionary(uniqueKeysWithValues: missingItems.map { ($0.id, $0) })

        return picked.map { scored in
            var missing: [Slot: HypotheticalItem] = [:]
            for garment in scored.candidate.hypotheticalGarments {
                if let slot = garment.slot, let item = itemsByID[garment.id] { missing[slot] = item }
            }
            return finalize(scored.candidate, score: scored.score, closet: closet, context: context, missing: missing)
        }
    }
}
