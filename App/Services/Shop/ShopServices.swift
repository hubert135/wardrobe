import Foundation
import OutfitEngine

enum PriceTier: String, CaseIterable, Identifiable {
    case budget, mid, premium
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .budget: "Budget"
        case .mid: "Mid-range"
        case .premium: "Investment"
        }
    }
}

/// A purchase direction described by attributes only. Never a product link.
struct PurchaseDirection: Identifiable, Hashable {
    var tier: PriceTier
    var attributes: String
    var priceRange: ClosedRange<Double>
    var currencyCode: String
    var query: String

    var id: String { tier.rawValue + query }
}

struct RetailerLink: Identifiable, Hashable {
    var retailer: String
    var url: URL
    var id: String { retailer }
}

/// Source of shopping links. Today: deterministic search URLs. Later: affiliate feeds.
protocol ProductProvider {
    func links(for query: String, maxPrice: Double?) -> [RetailerLink]
}

/// Builds retailer *search* URLs from query parameters. It never generates or guesses product URLs,
/// because AI-invented product links are unreliable.
struct SearchLinkProvider: ProductProvider {
    var regionCode: String = Locale.current.region?.identifier ?? "PL"

    func links(for query: String, maxPrice: Double?) -> [RetailerLink] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var links: [RetailerLink] = []

        let zalando: (host: String, path: String) = switch regionCode {
        case "DE", "AT": ("www.zalando.de", "/katalog/")
        case "GB": ("www.zalando.co.uk", "/catalogue/")
        case "FR": ("www.zalando.fr", "/catalogue/")
        default: ("www.zalando.pl", "/katalog/")
        }
        if let url = Self.url(host: zalando.host, path: zalando.path, items: [URLQueryItem(name: "q", value: query)]) {
            links.append(RetailerLink(retailer: "Zalando", url: url))
        }

        if let url = Self.url(host: "www.google.com", path: "/search", items: [
            URLQueryItem(name: "tbm", value: "shop"),
            URLQueryItem(name: "q", value: query)
        ]) {
            links.append(RetailerLink(retailer: "Google Shopping", url: url))
        }

        var allegroItems = [URLQueryItem(name: "string", value: query)]
        if let maxPrice { allegroItems.append(URLQueryItem(name: "price_to", value: String(Int(maxPrice.rounded())))) }
        if let url = Self.url(host: "allegro.pl", path: "/listing", items: allegroItems) {
            links.append(RetailerLink(retailer: "Allegro", url: url))
        }
        return links
    }

    static func url(host: String, path: String, items: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = items
        return components.url
    }
}

/// Deterministic price tiers and attribute descriptions per category.
enum PurchaseDirectionCatalog {
    /// Typical upper price per tier in EUR.
    private static let basePrices: [GarmentCategory: (Double, Double, Double)] = [
        .shirt: (35, 80, 180), .tShirt: (15, 40, 80), .polo: (25, 70, 140), .sweater: (40, 100, 250),
        .hoodie: (30, 80, 160), .blazer: (100, 250, 600), .jacket: (60, 160, 400), .coat: (120, 300, 700),
        .trousers: (40, 100, 220), .jeans: (40, 100, 200), .chinos: (35, 90, 180), .shorts: (25, 55, 110),
        .shoes: (60, 160, 380), .accessory: (15, 45, 120), .other: (30, 80, 160)
    ]

    /// Rough EUR conversion so tiers make sense in the user's currency. Unknown currencies use EUR values.
    static let eurRates: [String: Double] = ["EUR": 1, "PLN": 4.3, "USD": 1.1, "GBP": 0.86, "CHF": 0.95, "SEK": 11.5, "CZK": 25, "DKK": 7.45, "NOK": 11.5]

    static func directions(for item: HypotheticalItem, currencyCode: String, brand: String? = nil) -> [PurchaseDirection] {
        let rate = eurRates[currencyCode] ?? 1
        let prices = basePrices[item.category] ?? (30, 80, 160)
        let material = item.material.isEmpty ? "cotton" : item.material
        let noun = item.category == .shoes && !item.cut.isEmpty ? item.cut : "\(item.cut) \(item.category.displayName.lowercased())".trimmingCharacters(in: .whitespaces)
        let baseQuery = [brand, item.searchQuery].compactMap { $0?.nilIfEmpty }.joined(separator: " ")

        func round(_ value: Double) -> Double { (value * rate / 5).rounded() * 5 }

        return [
            PurchaseDirection(
                tier: .budget,
                attributes: "\(item.color.capitalized) \(noun) in a \(material) blend, regular fit, high-street brands",
                priceRange: 0...round(prices.0), currencyCode: currencyCode, query: baseQuery
            ),
            PurchaseDirection(
                tier: .mid,
                attributes: "\(item.color.capitalized) \(noun) in \(material), tailored fit and better construction",
                priceRange: round(prices.0)...round(prices.1), currencyCode: currencyCode, query: baseQuery
            ),
            PurchaseDirection(
                tier: .premium,
                attributes: "\(item.color.capitalized) \(noun) in premium \(material), refined finish, made to last",
                priceRange: round(prices.1)...round(prices.2), currencyCode: currencyCode, query: baseQuery + " premium"
            )
        ]
    }

    /// Directions whose price range starts within the budget.
    static func filter(_ directions: [PurchaseDirection], budget: Double?) -> [PurchaseDirection] {
        guard let budget, budget > 0 else { return directions }
        return directions.filter { $0.priceRange.lowerBound <= budget }
    }
}

/// Ranks closet gaps by how many new outfits they unlock (computed by the engine, never by the AI).
@MainActor
final class ShopService {
    let analyzer: GapAnalyzer
    let products: ProductProvider

    init(analyzer: GapAnalyzer = GapAnalyzer(), products: ProductProvider = SearchLinkProvider()) {
        self.analyzer = analyzer
        self.products = products
    }

    func gaps(closet: [EngineGarment], preferences: StylePreferences) async -> [Gap] {
        let analyzer = self.analyzer
        return await Task.detached(priority: .userInitiated) {
            let contexts = GapAnalyzer.standardContexts(preferences: preferences)
            return analyzer.rank(closet: closet, contexts: contexts)
        }.value
    }

    func unlockedCount(for item: HypotheticalItem, closet: [EngineGarment], preferences: StylePreferences) -> Int {
        analyzer.unlockedCount(adding: item, to: closet, contexts: GapAnalyzer.standardContexts(preferences: preferences))
    }
}
