import Foundation
import UIKit

protocol GarmentRecognizing {
    /// Recognizes one or more garments in a (cutout) photo.
    func recognize(_ image: UIImage) async throws -> [GarmentDraft]
}

final class AIGarmentRecognizer: GarmentRecognizing {
    private let api: WardrobeAPI

    init(api: WardrobeAPI) { self.api = api }

    func recognize(_ image: UIImage) async throws -> [GarmentDraft] {
        guard let jpeg = ImageProcessing.uploadJPEG(image) else { throw APIError.invalidResponse }
        let garments = try await api.analyzeGarment(image: ImageProcessing.payload(jpeg))
        return garments.map(GarmentDraftMapper.draft(from:))
    }
}

/// Where purchases come from. New sources (forwarded emails, mailbox integration) plug in here.
enum PurchaseSource {
    case text(String)
    case screenshot(UIImage)
}

protocol PurchaseImporter {
    func importPurchases(from source: PurchaseSource) async throws -> [GarmentDraft]
}

final class AIOrderImporter: PurchaseImporter {
    static let maxTextLength = 30_000
    private let api: WardrobeAPI

    init(api: WardrobeAPI) { self.api = api }

    func importPurchases(from source: PurchaseSource) async throws -> [GarmentDraft] {
        let items: [ParsedOrderItemDTO]
        switch source {
        case .text(let text):
            let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTextLength))
            items = try await api.parseOrder(text: trimmed, image: nil)
        case .screenshot(let image):
            guard let jpeg = ImageProcessing.uploadJPEG(image) else { throw APIError.invalidResponse }
            items = try await api.parseOrder(text: nil, image: ImageProcessing.payload(jpeg))
        }
        return items.map(GarmentDraftMapper.draft(from:))
    }
}

/// Downloads product images from order emails with strict limits. Failure is not an error:
/// the item keeps a placeholder and the user can attach a photo later.
struct ProductImageDownloader {
    var maxBytes = 5_000_000
    var timeout: TimeInterval = 10

    func download(_ url: URL) async -> UIImage? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  (http.mimeType ?? "").hasPrefix("image/"),
                  http.expectedContentLength <= Int64(maxBytes) else { return nil }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { return nil }
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
