import CryptoKit
import Foundation
import Observation
import OutfitEngine
import UIKit

/// User setting: show suggested outfits worn by a model.
enum OutfitModelSettings {
    static let enabledKey = "outfits.onModel"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
}

/// Photos of outfits worn by the app's house model (later: the user's own avatar). Each outfit is rendered
/// once by the server and kept on the phone, so scrolling back or reopening the app costs nothing.
@MainActor
@Observable
final class OutfitModelStore {
    enum Status: Equatable {
        case waiting, rendering, failed(String)
    }

    private(set) var statuses: [String: Status] = [:]
    /// Latest image file per outfit key.
    private(set) var files: [String: String] = [:]

    private let api: WardrobeAPI
    private let imageStore: ImageStore
    private let canUseAI: @MainActor () -> Bool
    private let directory: URL
    private var queue: [(key: String, tiles: [CollageTile], fresh: Bool)] = []
    private var running = 0
    /// Renders take about half a minute; two at a time keeps three suggestions quick without hitting limits.
    private let maxConcurrent = 2

    init(api: WardrobeAPI, imageStore: ImageStore, canUseAI: @escaping @MainActor () -> Bool, directory: URL? = nil) {
        self.api = api
        self.imageStore = imageStore
        self.canUseAI = canUseAI
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? support.appendingPathComponent("OutfitRenders", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: self.directory.path)) ?? [] where name.hasSuffix(".jpg") {
            guard let key = name.split(separator: "_").first.map(String.init) else { continue }
            if let existing = files[key], existing > name { continue }
            files[key] = name
        }
    }

    /// Whether outfits can be dressed at all (AI available).
    var isAvailable: Bool { canUseAI() }

    /// Stable id of what the model wears: same pieces with the same looks give the same key.
    static func key(for tiles: [CollageTile]) -> String? {
        let slots = Set(tiles.map(\.slot))
        guard slots.isSuperset(of: Slot.required) else { return nil }
        let text = tiles.sorted { $0.slot < $1.slot }.map { tile in
            let h = tile.hints
            return [tile.slot.rawValue, h.category, h.primaryColor, h.secondaryColor ?? "", h.subcategory ?? "", h.material ?? "", h.pattern ?? "", tile.imageFile ?? ""]
                .joined(separator: "|")
        }
        .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(("model-v1\n" + text).utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    func imageURL(for key: String) -> URL? {
        files[key].map { directory.appendingPathComponent($0) }
    }

    func status(for key: String) -> Status? { statuses[key] }

    /// Asks for the outfit on the model unless it is already there or on its way.
    func request(_ tiles: [CollageTile], fresh: Bool = false) {
        guard let key = Self.key(for: tiles) else { return }
        if !fresh, files[key] != nil { return }
        if let status = statuses[key], status == .waiting || status == .rendering { return }
        statuses[key] = .waiting
        queue.append((key, tiles, fresh))
        pump()
    }

    func deleteAll() {
        queue.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        files = [:]
        statuses = [:]
    }

    private func pump() {
        while running < maxConcurrent, !queue.isEmpty {
            let job = queue.removeFirst()
            running += 1
            Task {
                await render(job.key, tiles: job.tiles, fresh: job.fresh)
                running -= 1
                pump()
            }
        }
    }

    private func render(_ key: String, tiles: [CollageTile], fresh: Bool) async {
        guard canUseAI() else {
            statuses[key] = .failed("Outfits on a model aren't available right now.")
            return
        }
        statuses[key] = .rendering
        var items: [RenderOutfitItemDTO] = []
        for tile in tiles.sorted(by: { $0.slot < $1.slot }) {
            items.append(RenderOutfitItemDTO(slot: tile.slot.rawValue, garment: tile.hints, image: await payload(for: tile.imageFile)))
        }
        do {
            let result = try await api.renderOutfit(items: items, fresh: fresh)
            guard let data = Data(base64Encoded: result.data), UIImage(data: data) != nil else {
                statuses[key] = .failed("The photo could not be read. Try again.")
                return
            }
            let name = "\(key)_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            if let old = files[key] { try? FileManager.default.removeItem(at: directory.appendingPathComponent(old)) }
            files[key] = name
            statuses[key] = nil
        } catch {
            statuses[key] = .failed((error as? LocalizedError)?.errorDescription ?? "The model photo could not be created. Try again.")
        }
    }

    /// A small JPEG of the garment's photo, so the model wears exactly this piece.
    private func payload(for file: String?) async -> ImagePayload? {
        guard let file, let image = await ThumbnailLoader.image(at: imageStore.url(for: file), maxPixels: 640),
              let jpeg = ImageProcessing.flattened(image).jpegData(compressionQuality: 0.8)
        else { return nil }
        return ImageProcessing.payload(jpeg)
    }
}

extension Garment {
    /// Description for the image model.
    var renderHints: RenderGarmentHintsDTO {
        RenderGarmentHintsDTO(
            name: name.isEmpty ? nil : name,
            category: category.rawValue,
            subcategory: subcategory.isEmpty ? nil : subcategory,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            pattern: pattern.rawValue,
            material: material.isEmpty ? nil : material
        )
    }
}

extension HypotheticalItem {
    var renderHints: RenderGarmentHintsDTO {
        RenderGarmentHintsDTO(
            name: nil, category: category.rawValue, subcategory: cut.isEmpty ? nil : cut,
            primaryColor: color, secondaryColor: nil, pattern: pattern.rawValue, material: material.isEmpty ? nil : material
        )
    }
}

extension EngineGarment {
    var renderHints: RenderGarmentHintsDTO {
        RenderGarmentHintsDTO(
            name: nil, category: category.rawValue, subcategory: subcategory.isEmpty ? nil : subcategory,
            primaryColor: primaryColor, secondaryColor: secondaryColor, pattern: pattern.rawValue,
            material: material.isEmpty ? nil : material
        )
    }
}
