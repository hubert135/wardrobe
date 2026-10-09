import Foundation
import OutfitEngine
import SwiftData

/// Persistence boundary for view models. Views may still use `@Query` for live lists;
/// all writes go through the repository.
@MainActor
protocol WardrobeRepository: AnyObject {
    func profile() -> UserProfile
    func garments(includeArchived: Bool) -> [Garment]
    func garment(id: UUID) -> Garment?
    func insert(_ garment: Garment)
    func delete(_ garment: Garment)
    func outfits() -> [Outfit]
    func favorite(combinationKey: String) -> Outfit?
    @discardableResult
    func saveOutfit(_ suggestion: OutfitSuggestion, wornOn: Date?, favorite: Bool) -> Outfit
    func delete(_ outfit: Outfit)
    /// Records wearing a saved (e.g. favorite) outfit again as a new history entry.
    @discardableResult
    func recordWear(of outfit: Outfit, on date: Date) -> Outfit
    func wishlist() -> [WishlistItem]
    func insert(_ item: WishlistItem)
    func delete(_ item: WishlistItem)
    func deleteEverything()
    func save()
}

@MainActor
final class SwiftDataWardrobeRepository: WardrobeRepository {
    let context: ModelContext
    private let imageStore: ImageStore

    init(context: ModelContext, imageStore: ImageStore) {
        self.context = context
        self.imageStore = imageStore
    }

    func profile() -> UserProfile {
        if let existing = try? context.fetch(FetchDescriptor<UserProfile>()).first { return existing }
        let profile = UserProfile()
        context.insert(profile)
        save()
        return profile
    }

    func garments(includeArchived: Bool = false) -> [Garment] {
        let all = (try? context.fetch(FetchDescriptor<Garment>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        return includeArchived ? all : all.filter { $0.status != .archived }
    }

    func garment(id: UUID) -> Garment? {
        var descriptor = FetchDescriptor<Garment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func insert(_ garment: Garment) {
        context.insert(garment)
        save()
    }

    func delete(_ garment: Garment) {
        for file in garment.allImageFiles { imageStore.delete(file) }
        context.delete(garment)
        save()
    }

    func outfits() -> [Outfit] {
        (try? context.fetch(FetchDescriptor<Outfit>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    func favorite(combinationKey: String) -> Outfit? {
        var descriptor = FetchDescriptor<Outfit>(predicate: #Predicate { $0.combinationKey == combinationKey && $0.isFavorite })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    func saveOutfit(_ suggestion: OutfitSuggestion, wornOn: Date?, favorite: Bool) -> Outfit {
        let outfit = Outfit(
            title: suggestion.outfit.title,
            occasion: suggestion.occasion,
            style: suggestion.style,
            season: suggestion.season,
            reasoning: suggestion.outfit.reasoning,
            combinationKey: suggestion.outfit.id
        )
        outfit.weatherSnapshot = suggestion.weather
        outfit.wornOn = wornOn
        outfit.isFavorite = favorite
        context.insert(outfit)

        var slots: [OutfitSlot] = []
        for (slot, piece) in suggestion.outfit.pieces {
            if let missing = suggestion.outfit.missing[slot] {
                slots.append(OutfitSlot(slot: slot, missing: missing))
            } else {
                slots.append(OutfitSlot(slot: slot, garment: garment(id: piece.id)))
            }
        }
        for slot in slots { context.insert(slot) }
        outfit.slots = slots

        if let wornOn {
            for garment in slots.compactMap(\.garment) {
                garment.wearCount += 1
                garment.lastWornAt = wornOn
                garment.touch()
            }
        }
        save()
        return outfit
    }

    func delete(_ outfit: Outfit) {
        context.delete(outfit)
        save()
    }

    @discardableResult
    func recordWear(of outfit: Outfit, on date: Date) -> Outfit {
        let copy = Outfit(
            title: outfit.title, occasion: outfit.occasion, style: outfit.style, season: outfit.season,
            reasoning: outfit.reasoning, combinationKey: outfit.combinationKey
        )
        copy.weatherSnapshot = outfit.weatherSnapshot
        copy.wornOn = date
        context.insert(copy)
        var slots: [OutfitSlot] = []
        for original in outfit.orderedSlots {
            guard let garment = original.garment else { continue }
            let slot = OutfitSlot(slot: original.slot, garment: garment)
            context.insert(slot)
            slots.append(slot)
            garment.wearCount += 1
            garment.lastWornAt = date
            garment.touch()
        }
        copy.slots = slots
        save()
        return copy
    }

    func wishlist() -> [WishlistItem] {
        (try? context.fetch(FetchDescriptor<WishlistItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    func insert(_ item: WishlistItem) {
        context.insert(item)
        save()
    }

    func delete(_ item: WishlistItem) {
        context.delete(item)
        save()
    }

    func deleteEverything() {
        try? context.delete(model: OutfitSlot.self)
        try? context.delete(model: Outfit.self)
        try? context.delete(model: Garment.self)
        try? context.delete(model: WishlistItem.self)
        try? context.delete(model: UserProfile.self)
        imageStore.deleteAll()
        save()
    }

    func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("SwiftData save failed: \(error)")
        }
    }
}
