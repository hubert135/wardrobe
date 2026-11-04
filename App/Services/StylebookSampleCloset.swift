import Foundation
import OutfitEngine
import SwiftUI

/// Builds a sample closet from the style guide's real products (photo, shop, price), so outfits
/// look like the e-book instead of drawn placeholders. Everything stays on the device.
@MainActor
enum StylebookSampleCloset {
    static let maximumGarments = 30

    /// Adds up to `maximumGarments` distinct products (one per category and color) and returns how many were added.
    static func load(into services: AppServices) async -> Int {
        guard let stylebook = services.stylebook.stylebook else { return 0 }
        var owned = Set(services.repository.garments(includeArchived: false).map { key($0.category, $0.primaryColor) })
        var added = 0

        for recipe in stylebook.recipes {
            for product in recipe.budgets["standard"]?.items ?? [] {
                guard added < maximumGarments,
                      let pieceIndex = product.pieceIndex, recipe.pieces.indices.contains(pieceIndex),
                      let imageName = product.image else { continue }
                let piece = recipe.pieces[pieceIndex].enginePiece
                // A sample garment needs a definite category and color.
                guard let category = piece.categories.first, let color = piece.colors.first,
                      owned.insert(key(category, color)).inserted else { continue }
                guard let file = await services.stylebook.imageFile(named: imageName),
                      let data = try? Data(contentsOf: file),
                      let saved = try? services.imageStore.save(data, fileExtension: "jpg", prefix: ProductPhotoQueue.filePrefix)
                else { continue }

                let material = piece.materials.first ?? ""
                let garment = Garment(
                    name: [color.capitalized, material, category.displayName.lowercased()].filter { !$0.isEmpty }.joined(separator: " "),
                    category: category,
                    subcategory: material,
                    primaryColor: color,
                    pattern: piece.patterns.first ?? .solid,
                    material: material,
                    formality: formality(for: category, styles: recipe.engineRecipe.styles),
                    brand: product.shop ?? "",
                    price: Double(product.price),
                    source: .manual,
                    status: .confirmed
                )
                garment.productImageFile = saved
                services.repository.insert(garment)
                added += 1
            }
        }
        return added
    }

    /// Removes the drawn sample garments (no real or product photo, sample names), keeping everything else.
    static func removeDrawnSamples(from services: AppServices) -> Int {
        #if DEBUG
        let sampleNames = Set(SeedData.sampleCloset.map(\.name))
        let drawn = services.repository.garments(includeArchived: true).filter {
            sampleNames.contains($0.name) && $0.originalImageFile == nil && $0.productImageFile == nil
        }
        for garment in drawn { services.repository.delete(garment) }
        return drawn.count
        #else
        return 0
        #endif
    }

    private static func key(_ category: GarmentCategory, _ color: String) -> String {
        "\(category.rawValue)|\(color)"
    }

    private static func formality(for category: GarmentCategory, styles: [Style]) -> Int {
        if styles == [.formal], category != .accessory { return 5 }
        if styles.contains(.sporty), !styles.contains(.smartCasual) { return max(1, category.defaultFormality - 1) }
        return category.defaultFormality
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
