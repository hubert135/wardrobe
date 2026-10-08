import UIKit

/// Normalizes a photo, removes its background on device and stores both versions.
struct PhotoProcessor {
    struct Stored {
        var original: String
        var cutout: String?
        /// The cutout if available, otherwise the normalized original. Used for recognition.
        var analysisImage: UIImage
    }

    let imageStore: ImageStore
    let remover: BackgroundRemoving

    func store(_ image: UIImage) async -> Stored? {
        let normalized = ImageProcessing.normalized(image, maxDimension: ImageProcessing.storageMaxDimension)
        guard let jpeg = normalized.jpegData(compressionQuality: 0.85),
              let original = try? imageStore.save(jpeg, fileExtension: "jpg") else { return nil }

        var cutoutName: String?
        var analysisImage = normalized
        if let cutout = await remover.removeBackground(from: normalized) {
            let stored = ImageProcessing.normalized(cutout, maxDimension: 1024)
            if let png = stored.pngData(), let name = try? imageStore.save(png, fileExtension: "png") {
                cutoutName = name
                analysisImage = cutout
            }
        }
        return Stored(original: original, cutout: cutoutName, analysisImage: analysisImage)
    }
}
