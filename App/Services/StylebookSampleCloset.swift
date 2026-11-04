import Foundation
import OutfitEngine
import SwiftUI

/// Builds a sample closet from the style guide's real products (photo, shop, price), so outfits
/// look like the e-book instead of drawn placeholders. Everything stays on the device.
@MainActor
enum StylebookSampleCloset {
    static let maximumGarments = 40
    /// Marks sample garments so they can be replaced later without touching the user's own clothes.
    static let sampleOwner = "sample"

    /// Adds a capsule closet of real products covering formal, smart casual and casual recipes
    /// (one garment per category and color) and returns how many were added.
    static func load(into services: AppServices) async -> Int {
        guard let stylebook = services.stylebook.stylebook else { return 0 }
        var owned = Set(services.repository.garments(includeArchived: false).map { key($0.category, $0.primaryColor) })
        var added = 0

        for recipe in balancedOrder(stylebook.recipes) {
            let engineRecipe = recipe.engineRecipe
            for (index, piece) in engineRecipe.pieces.enumerated() where !piece.optional && piece.slot != .accessory {
                guard added < maximumGarments,
                      let category = piece.categories.first, let color = piece.colors.first,
                      !owned.contains(key(category, color)),
                      let product = product(for: index, in: recipe), let imageName = product.image,
                      let file = await services.stylebook.imageFile(named: imageName),
                      let data = try? Data(contentsOf: file),
                      let saved = try? services.imageStore.save(data, fileExtension: "jpg", prefix: ProductPhotoQueue.filePrefix)
                else { continue }
                owned.insert(key(category, color))

                let material = piece.materials.first ?? ""
                let garment = Garment(
                    name: [color.capitalized, material, category.displayName.lowercased()].filter { !$0.isEmpty }.joined(separator: " "),
                    category: category,
                    subcategory: material,
                    primaryColor: color,
                    pattern: piece.patterns.first ?? .solid,
                    material: material,
                    formality: formality(for: category, styles: engineRecipe.styles, materials: piece.materials),
                    brand: product.shop ?? "",
                    price: Double(product.price),
                    source: .manual,
                    status: .confirmed
                )
                garment.productImageFile = saved
                garment.ownerID = sampleOwner
                services.repository.insert(garment)
                added += 1
            }
        }
        return added
    }

    /// Formal, smart casual and casual recipes interleaved, so the capsule is not all from one style.
    private static func balancedOrder(_ recipes: [StylebookRecipeDTO]) -> [StylebookRecipeDTO] {
        let formal = recipes.filter { $0.styles.contains("formal") }
        let smart = recipes.filter { $0.styles.contains("smart_casual") && !$0.styles.contains("formal") }
        let casual = recipes.filter { !$0.styles.contains("smart_casual") && !$0.styles.contains("formal") }
        var order: [StylebookRecipeDTO] = []
        for index in 0..<max(formal.count, smart.count, casual.count) {
            for group in [formal, smart, casual] where index < group.count { order.append(group[index]) }
        }
        return order
    }

    /// The e-book product for a recipe piece, preferring the standard budget.
    private static func product(for pieceIndex: Int, in recipe: StylebookRecipeDTO) -> StylebookProductDTO? {
        for budget in ["standard", "budget", "premium"] {
            if let item = recipe.budgets[budget]?.items.first(where: { $0.pieceIndex == pieceIndex && $0.image != nil }) {
                return item
            }
        }
        return nil
    }

    /// Removes earlier sample garments (drawn ones and product samples from older versions), never the user's own.
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

    private static func key(_ category: GarmentCategory, _ color: String) -> String {
        "\(category.rawValue)|\(color)"
    }

    /// The formality a product has in its recipe: the most formal style the recipe is written for.
    /// Sportswear (hoodies, joggers, jersey, fleece) is always sporty.
    private static func formality(for category: GarmentCategory, styles: [Style], materials: [String]) -> Int {
        guard category != .accessory else { return 3 }
        let sporty = ["jogger", "jersey", "sweat", "fleece"]
        if category == .hoodie || materials.contains(where: { material in sporty.contains { material.contains($0) } }) { return 1 }
        if styles.contains(.formal) { return styles.contains(.smartCasual) ? 4 : 5 }
        if styles.contains(.smartCasual) {
            return [.shirt, .blazer, .trousers, .coat].contains(category) ? 4 : 3
        }
        if styles.contains(.casual) { return [.hoodie, .tShirt, .shorts].contains(category) ? 2 : 3 }
        return 2
    }
}

/// A product photo from the style guide, downloaded from the user's server once and cached.
struct StylebookProductImage: View {
    @Environment(AppServices.self) private var services
    var name: String?
    var maxPixels: CGFloat = 300
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(uiImage: image).resizable().scaledToFit().padding(3)
            } else {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            }
        }
        .task(id: name) {
            guard let name, let url = await services.stylebook.imageFile(named: name) else { return }
            image = await ThumbnailLoader.image(at: url, maxPixels: maxPixels)
        }
        .accessibilityHidden(true)
    }
}
