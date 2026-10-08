import Foundation

public struct Gap: Sendable, Hashable, Identifiable {
    public var item: HypotheticalItem
    /// Number of new valid outfits the item would add to the current closet.
    public var unlockedOutfitCount: Int
    /// Short, factual reason built from the real combinations ("Works with 4 of your tops and 2 pairs of shoes").
    public var reason: String

    public var id: UUID { item.id }
}

/// Measures how many new outfits a hypothetical purchase would unlock, using the same rules
/// as outfit generation. The count is always computed here, never by the AI.
public struct GapAnalyzer: Sendable {
    public var engine: OutfitEngine

    public init(engine: OutfitEngine = OutfitEngine()) { self.engine = engine }

    /// Contexts that represent "a normal year" for this user: each preferred style in each season,
    /// with no weather and ignoring recent wear.
    public static func standardContexts(preferences: StylePreferences, date: Date = Date()) -> [OutfitContext] {
        let styles = preferences.preferredStyles.isEmpty ? [Style.smartCasual] : preferences.preferredStyles
        return styles.flatMap { style in
            Season.allCases.map { season in
                OutfitContext(style: style, season: season, date: date, preferences: preferences, ignoresRecentWear: true)
            }
        }
    }

    /// The new outfits (deduplicated across contexts) that contain `item`.
    public func newOutfits(adding item: HypotheticalItem, to closet: [EngineGarment], contexts: [OutfitContext]) -> [OutfitCandidate] {
        let hypothetical = item.asGarment
        var seen = Set<String>()
        var result: [OutfitCandidate] = []
        for context in contexts {
            let candidates = engine.builder.build(
                closet: closet, context: context, extras: [hypothetical], maxHypotheticals: 1, mustInclude: hypothetical.id
            )
            for candidate in candidates where seen.insert(candidate.id).inserted {
                result.append(candidate)
            }
        }
        return result
    }

    public func unlockedCount(adding item: HypotheticalItem, to closet: [EngineGarment], contexts: [OutfitContext]) -> Int {
        newOutfits(adding: item, to: closet, contexts: contexts).count
    }

    /// Gaps sorted by impact. Items the user already owns and items that unlock nothing are dropped.
    public func rank(closet: [EngineGarment], catalog: [HypotheticalItem] = StarterCatalog.items, contexts: [OutfitContext]) -> [Gap] {
        catalog
            .filter { !$0.isOwned(in: closet) }
            .compactMap { item -> Gap? in
                let outfits = newOutfits(adding: item, to: closet, contexts: contexts)
                guard !outfits.isEmpty else { return nil }
                return Gap(item: item, unlockedOutfitCount: outfits.count, reason: reason(for: item, outfits: outfits))
            }
            .sorted { $0.unlockedOutfitCount == $1.unlockedOutfitCount ? $0.item.title < $1.item.title : $0.unlockedOutfitCount > $1.unlockedOutfitCount }
    }

    func reason(for item: HypotheticalItem, outfits: [OutfitCandidate]) -> String {
        var partners: [Slot: Set<UUID>] = [:]
        for outfit in outfits {
            for garment in outfit.garments where !garment.isHypothetical {
                if let slot = garment.slot { partners[slot, default: []].insert(garment.id) }
            }
        }
        let phrases: [String] = [Slot.top, .bottom, .shoes, .outerwear].compactMap { slot in
            guard slot != item.category.slot, let count = partners[slot]?.count, count > 0 else { return nil }
            switch slot {
            case .top: return count == 1 ? "1 of your tops" : "\(count) of your tops"
            case .bottom: return count == 1 ? "1 pair of your trousers" : "\(count) of your bottoms"
            case .shoes: return count == 1 ? "1 pair of shoes" : "\(count) pairs of shoes"
            case .outerwear: return count == 1 ? "1 layer" : "\(count) layers"
            case .accessory: return nil
            }
        }
        guard !phrases.isEmpty else { return "Fills an empty spot in your closet." }
        let list = phrases.count > 1 ? phrases.dropLast().joined(separator: ", ") + " and " + phrases.last! : phrases[0]
        return "Works with \(list)."
    }
}

/// A compact menswear catalog of versatile pieces used for gap analysis and builder "missing" items.
public enum StarterCatalog {
    public static let items: [HypotheticalItem] = [
        HypotheticalItem(category: .shirt, color: "white", cut: "oxford", material: "cotton", formality: 4),
        HypotheticalItem(category: .shirt, color: "light blue", cut: "oxford", material: "cotton", formality: 4),
        HypotheticalItem(category: .shirt, color: "white", cut: "poplin dress", material: "cotton", formality: 5),
        HypotheticalItem(category: .tShirt, color: "white", cut: "crew neck", material: "cotton", formality: 2),
        HypotheticalItem(category: .tShirt, color: "navy", cut: "crew neck", material: "cotton", formality: 2),
        HypotheticalItem(category: .polo, color: "navy", cut: "knitted", material: "cotton", formality: 3),
        HypotheticalItem(category: .sweater, color: "navy", cut: "crew neck", material: "merino wool", formality: 3, seasons: [.autumn, .winter, .spring]),
        HypotheticalItem(category: .sweater, color: "grey", cut: "v-neck", material: "merino wool", formality: 3, seasons: [.autumn, .winter, .spring]),
        HypotheticalItem(category: .hoodie, color: "grey", cut: "zip", material: "cotton fleece", formality: 1),
        HypotheticalItem(category: .blazer, color: "navy", cut: "unstructured", material: "wool", formality: 4),
        HypotheticalItem(category: .blazer, color: "grey", cut: "single-breasted", material: "wool flannel", formality: 5, seasons: [.autumn, .winter]),
        HypotheticalItem(category: .jacket, color: "navy", cut: "harrington", material: "cotton", formality: 3, seasons: [.spring, .autumn]),
        HypotheticalItem(category: .jacket, color: "olive", cut: "field", material: "cotton", formality: 2, seasons: [.spring, .autumn]),
        HypotheticalItem(category: .jacket, color: "denim", cut: "trucker", material: "denim", formality: 2, seasons: [.spring, .autumn]),
        HypotheticalItem(category: .coat, color: "navy", cut: "overcoat", material: "wool", formality: 4, seasons: [.autumn, .winter]),
        HypotheticalItem(category: .coat, color: "tan", cut: "trench", material: "cotton gabardine", formality: 4, seasons: [.spring, .autumn]),
        HypotheticalItem(category: .chinos, color: "beige", cut: "slim", material: "cotton twill", formality: 3),
        HypotheticalItem(category: .chinos, color: "navy", cut: "slim", material: "cotton twill", formality: 3),
        HypotheticalItem(category: .chinos, color: "olive", cut: "slim", material: "cotton twill", formality: 3),
        HypotheticalItem(category: .trousers, color: "grey", cut: "tailored", material: "wool", formality: 4),
        HypotheticalItem(category: .trousers, color: "charcoal", cut: "tailored", material: "wool", formality: 5),
        HypotheticalItem(category: .jeans, color: "denim", cut: "slim dark", material: "denim", formality: 2),
        HypotheticalItem(category: .shorts, color: "beige", cut: "chino", material: "cotton", formality: 2, seasons: [.summer]),
        HypotheticalItem(category: .shoes, color: "white", cut: "leather sneakers", material: "leather", formality: 2),
        HypotheticalItem(category: .shoes, color: "brown", cut: "derby shoes", material: "leather", formality: 4),
        HypotheticalItem(category: .shoes, color: "black", cut: "oxford shoes", material: "leather", formality: 5),
        HypotheticalItem(category: .shoes, color: "brown", cut: "chelsea boots", material: "leather", formality: 3, seasons: [.autumn, .winter, .spring]),
        HypotheticalItem(category: .shoes, color: "brown", cut: "loafers", material: "leather", formality: 3, seasons: [.spring, .summer, .autumn]),
        HypotheticalItem(category: .accessory, color: "brown", cut: "leather belt", material: "leather", formality: 3),
        HypotheticalItem(category: .accessory, color: "navy", cut: "knit tie", material: "silk", formality: 4)
    ]
}
