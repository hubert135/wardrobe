import Foundation
import Observation
import OutfitEngine

@MainActor
@Observable
final class BuilderViewModel {
    var anchorIDs: Set<UUID> = []
    var occasion: Occasion = .work
    var style: Style = .smartCasual
    var season: Season = Season.from(date: Date())
    var includeMissing = false
    private(set) var results: [OutfitSuggestion] = []
    private(set) var hasRun = false
    var message: String?
    private(set) var favoriteFeedback = 0
    private(set) var wearFeedback = 0

    private let services: AppServices
    private var garmentsByID: [UUID: Garment] = [:]

    init(services: AppServices) {
        self.services = services
        let profile = services.repository.profile()
        occasion = profile.occasion(for: Date())
        style = profile.lastStyle
    }

    var anchors: [Garment] {
        anchorIDs.compactMap { services.repository.garment(id: $0) }.sorted { $0.category.slot ?? .accessory < $1.category.slot ?? .accessory }
    }

    func run() {
        let garments = services.repository.garments(includeArchived: false)
        garmentsByID = Dictionary(uniqueKeysWithValues: garments.map { ($0.id, $0) })
        let profile = services.repository.profile()
        let context = OutfitContext(
            occasion: occasion, style: style, season: season, weather: nil, date: Date(),
            preferences: profile.stylePreferences, anchorGarmentIDs: anchorIDs
        )
        let outfits = services.outfits.build(closet: garments.map(\.engineGarment), context: context, includeMissing: includeMissing, count: 5)
        results = outfits.map {
            OutfitSuggestion(
                outfit: $0, occasion: occasion, style: style, season: season, weather: nil, origin: .local,
                isFavorite: services.repository.favorite(combinationKey: $0.id) != nil
            )
        }
        hasRun = true
    }

    func tiles(for suggestion: OutfitSuggestion) -> [CollageTile] {
        OutfitPresenter.tiles(for: suggestion.outfit, garments: garmentsByID)
    }

    func toggleFavorite(_ suggestion: OutfitSuggestion) {
        guard let index = results.firstIndex(where: { $0.id == suggestion.id }) else { return }
        let repository = services.repository
        if let existing = repository.favorite(combinationKey: suggestion.outfit.id) {
            if existing.wornOn == nil { repository.delete(existing) } else { existing.isFavorite = false; repository.save() }
            results[index].isFavorite = false
        } else {
            repository.saveOutfit(suggestion, wornOn: nil, favorite: true)
            results[index].isFavorite = true
        }
        favoriteFeedback += 1
    }

    func wear(_ suggestion: OutfitSuggestion) {
        guard let index = results.firstIndex(where: { $0.id == suggestion.id }), !suggestion.outfit.hasMissingPieces else { return }
        services.repository.saveOutfit(suggestion, wornOn: Date(), favorite: false)
        results[index].isWornToday = true
        wearFeedback += 1
    }

    func addToShoppingList(_ item: HypotheticalItem) {
        let repository = services.repository
        if repository.wishlist().contains(where: { $0.status == .open && $0.searchQuery == item.searchQuery }) {
            message = "\(item.title) is already on your shopping list."
            return
        }
        let closet = garmentsByID.values.map(\.engineGarment)
        let count = services.shop.unlockedCount(for: item, closet: closet, preferences: repository.profile().stylePreferences)
        repository.insert(WishlistItem(item: item, unlockedOutfitCount: count))
        message = "\(item.title) added to your shopping list."
    }
}
