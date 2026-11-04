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

    // MARK: Style guide

    struct RecipeProgress: Identifiable {
        var recipe: StylebookRecipeDTO
        /// Owned garment per required piece index.
        var owned: [Int: Garment]
        var requiredIndices: [Int]

        var id: String { recipe.id }
        var missingIndices: [Int] { requiredIndices.filter { owned[$0] == nil } }
        var ownedCount: Int { requiredIndices.count - missingIndices.count }
    }

    var hasStylebook: Bool { services.stylebook.hasStylebook }

    /// Recipes sorted by how close the closet is to completing them.
    func recipeProgress() -> [RecipeProgress] {
        guard let stylebook = services.stylebook.stylebook else { return [] }
        let garments = services.repository.garments(includeArchived: false)
        let byID = Dictionary(uniqueKeysWithValues: garments.map { ($0.id, $0) })
        let closet = garments.map(\.engineGarment)
        let matcher = RecipeMatcher()
        return stylebook.recipes.map { dto in
            let recipe = dto.engineRecipe
            let owned = matcher.ownedPieces(of: recipe, in: closet).compactMapValues { byID[$0.id] }
            let required = recipe.pieces.indices.filter { !recipe.pieces[$0].optional }
            return RecipeProgress(recipe: dto, owned: owned, requiredIndices: required)
        }
        .sorted { $0.missingIndices.count == $1.missingIndices.count ? $0.recipe.id < $1.recipe.id : $0.missingIndices.count < $1.missingIndices.count }
    }

    /// Adds the missing pieces of a recipe to the shopping list.
    func addMissingToWishlist(_ progress: RecipeProgress) {
        let closet = services.repository.garments(includeArchived: false).map(\.engineGarment)
        let preferences = services.repository.profile().stylePreferences
        var added: [String] = []
        for index in progress.missingIndices {
            let piece = progress.recipe.pieces[index].enginePiece
            guard let category = piece.categories.first else { continue }
            let item = HypotheticalItem(
                category: category, color: piece.colors.first ?? "", material: piece.materials.first ?? "",
                pattern: piece.patterns.first ?? .solid
            )
            let alreadyListed = services.repository.wishlist().contains { $0.status == .open && $0.searchQuery == item.searchQuery }
            guard !alreadyListed else { continue }
            let count = services.shop.unlockedCount(for: item, closet: closet, preferences: preferences)
            services.repository.insert(WishlistItem(item: item, unlockedOutfitCount: count))
            added.append(item.title)
        }
        message = added.isEmpty ? "These pieces are already on your shopping list." : "Added to your shopping list: \(added.joined(separator: ", "))."
    }
}
