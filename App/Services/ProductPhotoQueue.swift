import Foundation
import Observation
import UIKit

/// User setting: create store-style photos automatically for new photo garments.
enum ProductPhotoSettings {
    static let enabledKey = "productPhotos.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
}

/// Creates online-store style photos for garments in the background, two at a time.
/// Garments are saved first; their store photo appears when ready, so the user never waits.
@MainActor
@Observable
final class ProductPhotoQueue {
    nonisolated static let filePrefix = "product-"

    /// Garments waiting for a store photo.
    private(set) var pending: [UUID] = []
    /// Garments getting one right now.
    private(set) var active: Set<UUID> = []
    /// Last error per garment, shown on the garment's detail page.
    private(set) var failures: [UUID: String] = [:]

    private let api: WardrobeAPI
    private let repository: WardrobeRepository
    private let imageStore: ImageStore
    private let canUseAI: @MainActor () -> Bool
    /// Renders take about half a minute each; two in parallel halves the wait for a sample closet.
    private let maxConcurrent = 2

    init(api: WardrobeAPI, repository: WardrobeRepository, imageStore: ImageStore, canUseAI: @escaping @MainActor () -> Bool) {
        self.api = api
        self.repository = repository
        self.imageStore = imageStore
        self.canUseAI = canUseAI
    }

    func isWorking(on id: UUID) -> Bool { active.contains(id) || pending.contains(id) }

    /// Called after new photo garments are saved. Respects the user setting and sign-in.
    func enqueueNew(_ ids: [UUID]) {
        guard ProductPhotoSettings.isEnabled, canUseAI() else { return }
        enqueue(ids)
    }

    /// Explicit request from the user ("Create store photo" / "Regenerate").
    func enqueue(_ ids: [UUID]) {
        for id in ids where !isWorking(on: id) {
            failures[id] = nil
            pending.append(id)
        }
        startIfNeeded()
    }

    private func startIfNeeded() {
        while active.count < maxConcurrent, !pending.isEmpty {
            let id = pending.removeFirst()
            active.insert(id)
            Task {
                await process(id)
                active.remove(id)
                startIfNeeded()
            }
        }
    }

    /// Garments that can get a product photo: from their own photo, or from a known category and color.
    static func canCreatePhoto(for garment: Garment) -> Bool {
        garment.status != .archived && (garment.originalImageFile != nil || garment.category != .other)
    }

    private func process(_ id: UUID) async {
        guard canUseAI() else {
            failures[id] = "Product photos aren't available right now."
            return
        }
        guard let garment = repository.garment(id: id), Self.canCreatePhoto(for: garment) else {
            failures[id] = "Choose a category for this garment first."
            return
        }

        // With a real photo: edit that photo. Without one: draw the garment from its description.
        var payload: ImagePayload?
        if garment.originalImageFile != nil, let sourceFile = garment.sourceImageFile,
           let source = imageStore.image(for: sourceFile), let jpeg = ImageProcessing.uploadJPEG(source) {
            payload = ImageProcessing.payload(jpeg)
        }
        // Only describe the garment when the details are trustworthy (recognized or checked by the user);
        // unrecognized photos carry default values that could make the model recolor the garment.
        let hintsAreReliable = garment.category != .other
            && (payload == nil || garment.status == .confirmed || (garment.confidence ?? 0) >= 0.5)
        let hints: RenderGarmentHintsDTO? = hintsAreReliable ? garment.renderHints : nil
        guard payload != nil || hints != nil else {
            failures[id] = "Choose a category for this garment first."
            return
        }

        do {
            // A garment that already has a store photo is being regenerated: ask for a new picture.
            let result = try await api.renderProductPhoto(image: payload, garment: hints, fresh: garment.productImageFile != nil)
            guard let data = Data(base64Encoded: result.data), UIImage(data: data) != nil else {
                failures[id] = "The product photo could not be read. Try again."
                return
            }
            let name = try imageStore.save(data, fileExtension: "jpg", prefix: Self.filePrefix)
            // The garment may have been deleted while we were waiting.
            guard let garment = repository.garment(id: id) else {
                imageStore.delete(name)
                return
            }
            if let old = garment.productImageFile { imageStore.delete(old) }
            garment.productImageFile = name
            garment.prefersOriginalPhoto = false
            garment.touch()
            repository.save()
        } catch {
            failures[id] = (error as? LocalizedError)?.errorDescription ?? "The product photo could not be created. Try again."
        }
    }
}
