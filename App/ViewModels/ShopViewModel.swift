import Foundation
import Observation
import OutfitEngine

@MainActor
@Observable
final class ShopViewModel {
    private(set) var gaps: [Gap] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var maxBudget: Double?
    /// Favorite brand to include in search queries (nil = any brand).
    var brand: String?
    var message: String?

    private let services: AppServices
    private var fingerprint = ""

    init(services: AppServices) {
        self.services = services
        maxBudget = services.repository.profile().defaultBudget
    }

    var currencyCode: String { services.repository.profile().currencyCode }
    var favoriteBrands: [String] { services.repository.profile().favoriteBrands }
    var closetCount: Int { services.repository.garments(includeArchived: false).count }

    /// Recomputes gaps only when the closet or preferences changed.
    func load(force: Bool = false) async {
        let garments = services.repository.garments(includeArchived: false)
        let preferences = services.repository.profile().stylePreferences
        let newFingerprint = garments.map { "\($0.id)\($0.updatedAt.timeIntervalSince1970)" }.joined() + "\(preferences.hashValue)"
        guard force || newFingerprint != fingerprint else { return }
        fingerprint = newFingerprint
        isLoading = true
        gaps = await services.shop.gaps(closet: garments.map(\.engineGarment), preferences: preferences)
        isLoading = false
        hasLoaded = true
    }

    func directions(for gap: Gap) -> [PurchaseDirection] {
        let all = PurchaseDirectionCatalog.directions(for: gap.item, currencyCode: currencyCode, brand: brand)
        return PurchaseDirectionCatalog.filter(all, budget: maxBudget)
    }

    func links(for direction: PurchaseDirection) -> [RetailerLink] {
        let cap = maxBudget.map { min($0, direction.priceRange.upperBound) } ?? direction.priceRange.upperBound
        return services.shop.products.links(for: direction.query, maxPrice: cap)
    }

    func isOnWishlist(_ gap: Gap) -> Bool {
        services.repository.wishlist().contains { $0.status == .open && $0.searchQuery == gap.item.searchQuery }
    }

    func addToWishlist(_ gap: Gap) {
        guard !isOnWishlist(gap) else { return }
        services.repository.insert(WishlistItem(item: gap.item, unlockedOutfitCount: gap.unlockedOutfitCount))
        message = "\(gap.item.title) added to your shopping list."
    }

    func links(for item: WishlistItem) -> [RetailerLink] {
        services.shop.products.links(for: item.searchQuery, maxPrice: maxBudget)
    }

    /// Marks the item bought and adds a matching garment to the closet.
    func markBought(_ item: WishlistItem, addToCloset: Bool) {
        item.status = .bought
        if addToCloset {
            let spec = item.hypotheticalItem
            var draft = GarmentDraft()
            draft.name = item.itemDescription
            draft.category = spec.category
            draft.subcategory = spec.cut
            draft.primaryColor = spec.color
            draft.formality = spec.formality
            draft.source = .manual
            draft.purchaseDate = Date()
            GarmentSaver(services: services).save([draft])
            message = "\(item.itemDescription) is in your closet. Add a photo from its detail page."
        }
        services.repository.save()
    }

    func delete(_ item: WishlistItem) {
        services.repository.delete(item)
    }
}
