import Foundation

/// Enumerates valid core outfits (outerwear, top, bottom, shoes). Accessories are matched afterwards
/// by `AccessoryMatcher` so they do not multiply the search space.
public struct CandidateBuilder: Sendable {
    public var rules: OutfitRules

    public init(rules: OutfitRules = OutfitRules()) { self.rules = rules }

    /// - Parameters:
    ///   - closet: owned garments.
    ///   - extras: hypothetical garments that may be mixed in.
    ///   - maxHypotheticals: how many hypothetical pieces one candidate may contain.
    ///   - mustInclude: if set, only candidates containing this garment id are returned.
    public func build(
        closet: [EngineGarment],
        context: OutfitContext,
        extras: [EngineGarment] = [],
        maxHypotheticals: Int = 0,
        mustInclude: UUID? = nil
    ) -> [OutfitCandidate] {
        let pool = (closet + extras).filter { rules.isEligible($0, in: context) }
        var bySlot: [Slot: [EngineGarment]] = [:]
        for garment in pool {
            guard let slot = garment.slot, slot != .accessory else { continue }
            bySlot[slot, default: []].append(garment)
        }

        // Anchors pin their slot to themselves.
        let anchors = pool.filter { context.anchorGarmentIDs.contains($0.id) && $0.slot != .accessory }
        let requestedCoreAnchors = (closet + extras).filter {
            context.anchorGarmentIDs.contains($0.id) && $0.slot != nil && $0.slot != .accessory
        }
        if anchors.count < requestedCoreAnchors.count {
            // An anchor was filtered out by the rules, so nothing can satisfy the request.
            return []
        }
        for anchor in anchors {
            guard let slot = anchor.slot, slot != .accessory else { continue }
            bySlot[slot] = anchors.filter { $0.slot == slot }
        }

        let tops = sorted(bySlot[.top] ?? [])
        let bottoms = sorted(bySlot[.bottom] ?? [])
        let shoes = sorted(bySlot[.shoes] ?? [])
        let outerOptions: [EngineGarment?] = {
            let outer = sorted(bySlot[.outerwear] ?? [])
            if rules.requiresOuterwear(context) { return outer.filter { $0.category.isWeatherOuterwear }.map { Optional($0) } }
            if context.anchorGarmentIDs.contains(where: { id in outer.contains { $0.id == id } }) { return outer.map { Optional($0) } }
            return [nil] + outer.map { Optional($0) }
        }()

        var result: [OutfitCandidate] = []
        let cap = rules.config.maxCandidates

        for top in tops {
            for bottom in bottoms {
                // Cheap pruning before the inner loops.
                guard abs(top.formality - bottom.formality) <= rules.config.maxFormalitySpread else { continue }
                for shoe in shoes {
                    for outer in outerOptions {
                        var pieces: [Slot: EngineGarment] = [.top: top, .bottom: bottom, .shoes: shoe]
                        if let outer { pieces[.outerwear] = outer }
                        let candidate = OutfitCandidate(pieces: pieces)
                        if candidate.hypotheticalGarments.count > maxHypotheticals { continue }
                        if let mustInclude, !candidate.garmentIDs.contains(mustInclude) { continue }
                        guard rules.isValid(candidate, in: context) else { continue }
                        result.append(candidate)
                        if result.count >= cap { return result }
                    }
                }
            }
        }
        return result
    }

    /// Deterministic order keeps results stable between runs.
    private func sorted(_ garments: [EngineGarment]) -> [EngineGarment] {
        garments.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

/// Picks an optional accessory that fits an outfit without breaking its rules.
public struct AccessoryMatcher: Sendable {
    public var rules: OutfitRules

    public init(rules: OutfitRules = OutfitRules()) { self.rules = rules }

    public func bestAccessory(for candidate: OutfitCandidate, from closet: [EngineGarment], context: OutfitContext) -> EngineGarment? {
        let core = candidate.coreGarments
        guard !core.isEmpty else { return nil }
        let average = Double(core.map(\.formality).reduce(0, +)) / Double(core.count)
        let options = closet.filter { garment in
            garment.slot == .accessory
                && rules.isEligible(garment, in: context)
                && abs(Double(garment.formality) - average) <= 1.0
                && rules.hasHarmoniousColors(candidate.garments + [garment])
                && rules.hasCompatiblePatterns(core + [garment])
        }
        let pinned = options.filter { context.anchorGarmentIDs.contains($0.id) }
        if let anchor = pinned.first { return anchor }
        return options.min { lhs, rhs in
            let l = abs(Double(lhs.formality) - average), r = abs(Double(rhs.formality) - average)
            return l == r ? lhs.wearCount < rhs.wearCount : l < r
        }
    }

    public func attach(to candidate: OutfitCandidate, from closet: [EngineGarment], context: OutfitContext) -> OutfitCandidate {
        guard candidate.pieces[.accessory] == nil,
              let accessory = bestAccessory(for: candidate, from: closet, context: context) else { return candidate }
        var pieces = candidate.pieces
        pieces[.accessory] = accessory
        return OutfitCandidate(pieces: pieces)
    }
}
