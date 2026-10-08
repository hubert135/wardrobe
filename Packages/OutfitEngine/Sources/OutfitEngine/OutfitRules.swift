import Foundation

/// Why a garment was filtered out. Useful for debugging and for explaining empty results.
public enum ExclusionReason: String, Sendable, Hashable {
    case archived, noSlot, season, formality, recentlyWorn, tooWarm, tooCold, rain
}

/// Deterministic outfit rules: garment eligibility and outfit validity.
public struct OutfitRules: Sendable {
    public var config: EngineConfig

    public init(config: EngineConfig = .default) { self.config = config }

    // MARK: Weather

    public func isRainy(_ weather: WeatherContext?) -> Bool {
        guard let weather else { return false }
        return weather.precipitationChance >= config.rainChanceThreshold
    }

    public func requiresOuterwear(_ context: OutfitContext) -> Bool {
        guard let weather = context.weather else { return false }
        return weather.feelsLikeC < config.outerwearRequiredBelowC
    }

    // MARK: Garment level

    /// Returns `nil` if the garment may be used in this context, otherwise the first failing rule.
    public func exclusionReason(for garment: EngineGarment, in context: OutfitContext) -> ExclusionReason? {
        if garment.isArchived { return .archived }
        guard let slot = garment.slot else { return .noSlot }

        if let season = context.season, !garment.seasons.isEmpty, !garment.seasons.contains(season) {
            return .season
        }

        // Accessories are flexible and are matched to the outfit later.
        if slot != .accessory, !context.formalityRange.contains(garment.formality) {
            return .formality
        }

        if garment.category == .shorts, let occasion = context.occasion, !occasion.allowsShorts {
            return .formality
        }

        if !context.ignoresRecentWear,
           !garment.isHypothetical,
           !context.anchorGarmentIDs.contains(garment.id),
           let lastWorn = garment.lastWornAt,
           let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: lastWorn), to: Calendar.current.startOfDay(for: context.date)).day,
           days < config.recentWearExclusionDays {
            return .recentlyWorn
        }

        if let weather = context.weather {
            let t = weather.feelsLikeC
            switch garment.category {
            case .coat where t > config.coatMaxC: return .tooWarm
            case .jacket where t > config.jacketMaxC: return .tooWarm
            case .blazer where t > config.blazerMaxC: return .tooWarm
            case .sweater where t > config.warmLayerMaxC, .hoodie where t > config.warmLayerMaxC: return .tooWarm
            case .shorts where t < config.shortsMinC: return .tooCold
            default: break
            }
            if garment.category == .shoes, isRainy(weather), garment.isRainSensitive {
                return .rain
            }
        }
        return nil
    }

    public func isEligible(_ garment: EngineGarment, in context: OutfitContext) -> Bool {
        exclusionReason(for: garment, in: context) == nil
    }

    // MARK: Outfit level

    public func isValid(_ candidate: OutfitCandidate, in context: OutfitContext) -> Bool {
        let pieces = candidate.pieces
        for slot in Slot.required where pieces[slot] == nil { return false }

        if requiresOuterwear(context) {
            guard let outer = pieces[.outerwear], outer.category.isWeatherOuterwear else { return false }
        }

        let core = candidate.coreGarments
        if !hasAcceptableFormalitySpread(core) { return false }
        if !hasCompatiblePatterns(core) { return false }
        if !hasHarmoniousColors(candidate.garments) { return false }

        // Shorts never go under a blazer or a coat.
        if pieces[.bottom]?.category == .shorts,
           let outer = pieces[.outerwear]?.category, outer == .blazer || outer == .coat {
            return false
        }
        // A hoodie under a blazer is a fashion statement, not a default.
        if pieces[.top]?.category == .hoodie, pieces[.outerwear]?.category == .blazer { return false }

        return true
    }

    public func hasAcceptableFormalitySpread(_ garments: [EngineGarment]) -> Bool {
        let values = garments.map(\.formality)
        guard let lo = values.min(), let hi = values.max() else { return true }
        return hi - lo <= config.maxFormalitySpread
    }

    /// At most one patterned piece, or two if one of them is subtle (stripes) and they differ.
    public func hasCompatiblePatterns(_ garments: [EngineGarment]) -> Bool {
        let patterned = garments.map(\.pattern).filter { $0 != .solid }
        switch patterned.count {
        case 0, 1: return true
        case 2: return patterned[0] != patterned[1] && patterned.contains(where: \.isSubtle)
        default: return false
        }
    }

    /// Neutral base with at most `maxAccentColors` distinct accent colors.
    public func hasHarmoniousColors(_ garments: [EngineGarment]) -> Bool {
        accentColors(in: garments).count <= config.maxAccentColors
    }

    public func accentColors(in garments: [EngineGarment]) -> Set<String> {
        Set(garments.map(\.primaryColor).filter { !ColorPalette.isNeutral($0) })
    }
}
