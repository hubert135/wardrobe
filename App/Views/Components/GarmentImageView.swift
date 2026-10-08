import OutfitEngine
import SwiftUI
import UIKit

/// Loads garment images off the main thread with a small thumbnail cache.
enum ThumbnailLoader {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(at url: URL, maxPixels: CGFloat) async -> UIImage? {
        let key = "\(url.lastPathComponent)@\(Int(maxPixels))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            let scale = min(1, maxPixels / max(image.size.width, image.size.height, 1))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            return image.preparingThumbnail(of: size) ?? image
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    static func placeholder(category: GarmentCategory, color: String) -> UIImage {
        let key = "placeholder-\(category.rawValue)-\(color)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = PlaceholderImageRenderer.render(category: category, color: color, size: 240)
        cache.setObject(image, forKey: key)
        return image
    }
}

/// A garment cutout on the neutral canvas. Falls back to a drawn silhouette in the garment's color.
struct GarmentImageView: View {
    @Environment(AppServices.self) private var services

    var fileName: String?
    var category: GarmentCategory
    var color: String
    var maxPixels: CGFloat = 600
    var showsCanvas = true

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if showsCanvas { Theme.canvas }
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                Image(uiImage: ThumbnailLoader.placeholder(category: category, color: color))
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .opacity(0.85)
            }
        }
        .task(id: fileName) {
            guard let fileName else { image = nil; return }
            image = await ThumbnailLoader.image(at: services.imageStore.url(for: fileName), maxPixels: maxPixels)
        }
        .accessibilityHidden(true)
    }
}

extension GarmentImageView {
    init(garment: Garment, maxPixels: CGFloat = 600) {
        self.init(fileName: garment.displayImageFile, category: garment.category, color: garment.primaryColor, maxPixels: maxPixels)
    }
}
