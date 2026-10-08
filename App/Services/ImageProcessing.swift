import CoreImage
import UIKit
import Vision

enum ImageProcessing {
    /// Longest side for anything uploaded for analysis.
    static let uploadMaxDimension: CGFloat = 1600
    /// Hard cap for an upload after compression.
    static let uploadMaxBytes = 2_500_000
    /// Longest side for images stored on device.
    static let storageMaxDimension: CGFloat = 2048

    /// Redraws the image so its pixels are upright and at most `maxDimension` on the longest side.
    static func normalized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Composites a transparent cutout on a solid background (for JPEG upload).
    static func flattened(_ image: UIImage, background: UIColor = .white) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
    }

    /// JPEG for upload: resized to ~1600 px and compressed until it fits the byte cap.
    static func uploadJPEG(_ image: UIImage) -> Data? {
        let resized = normalized(flattened(image), maxDimension: uploadMaxDimension)
        var quality: CGFloat = 0.8
        while quality >= 0.3 {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= uploadMaxBytes { return data }
            quality -= 0.15
        }
        return nil
    }

    static func payload(_ jpeg: Data) -> ImagePayload {
        ImagePayload(mediaType: "image/jpeg", data: jpeg.base64EncodedString())
    }
}

protocol BackgroundRemoving {
    /// Returns a transparent cutout, or `nil` if the subject could not be isolated.
    func removeBackground(from image: UIImage) async -> UIImage?
}

/// On-device subject lifting with Vision. Falls back to `nil` (caller keeps the original photo),
/// which is also what happens in the Simulator where the request is not supported.
final class VisionBackgroundRemover: BackgroundRemoving {
    func removeBackground(from image: UIImage) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            Self.cutout(image)
        }.value
    }

    private static func cutout(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: buffer)
            guard let output = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
            return UIImage(cgImage: output)
        } catch {
            return nil
        }
    }
}
