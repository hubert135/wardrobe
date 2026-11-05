import Foundation
import OutfitEngine

/// A sample closet of plain, brand-free basics ("white oxford shirt", "navy chinos") that can wear every
/// built-in outfit recipe. Store photos are drawn for them by the product photo queue.
@MainActor
enum SampleCloset {
    /// Marks sample garments so they can be replaced later without touching the user's own clothes.
    static let sampleOwner = "sample"

    static var itemCount: Int { GenericCapsule.items.count }

    /// Replaces earlier sample garments with the capsule. Store photos are queued when they are switched on.
    @discardableResult
    static func load(into services: AppServices) -> (added: Int, removed: Int) {
        let removed = removePreviousSamples(from: services)
        var added: [UUID] = []
        for item in GenericCapsule.items {
            let garment = Garment(
                name: item.name,
                category: item.category,
                subcategory: item.subcategory,
                primaryColor: item.color,
                secondaryColor: item.secondaryColor,
                pattern: item.pattern,
                material: item.material,
                formality: item.formality,
                seasons: Set(item.seasons),
                source: .manual,
                status: .confirmed
            )
            garment.ownerID = sampleOwner
            services.repository.insert(garment)
            added.append(garment.id)
        }
        services.repository.save()
        services.productPhotos.enqueueNew(added)
        return (added.count, removed)
    }

    /// Removes earlier sample garments (drawn ones and the style-guide product samples of older versions),
    /// never the user's own.
    static func removePreviousSamples(from services: AppServices) -> Int {
        #if DEBUG
        let drawnNames = Set(SeedData.sampleCloset.map(\.name))
        #else
        let drawnNames = Set<String>()
        #endif
        let samples = services.repository.garments(includeArchived: true).filter { garment in
            if garment.ownerID == sampleOwner { return true }
            let isDrawnSample = drawnNames.contains(garment.name) && garment.originalImageFile == nil && garment.productImageFile == nil
            // Product samples from before the marker existed: e-book photo, shop and price, no photo of the user's own.
            let isOldProductSample = garment.source == .manual && garment.originalImageFile == nil && garment.cutoutImageFile == nil
                && garment.productImageFile != nil && !garment.brand.isEmpty && garment.price != nil && garment.wearCount == 0
            return isDrawnSample || isOldProductSample
        }
        for garment in samples { services.repository.delete(garment) }
        return samples.count
    }
}
