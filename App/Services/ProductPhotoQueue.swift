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

/// Creates online-store style photos for garments in the background, one at a time.
/// Garments are saved first; their store photo appears when ready, so the user never waits.
@MainActor
@Observable
final class ProductPhotoQueue {
    nonisolated static let filePrefix = "product-"

    /// Garments waiting for or currently getting a store photo.
    private(set) var pending: [UUID] = []
    private(set) var current: UUID?
    /// Last error per garment, shown on the garment's detail page.
    private(set) var failures: [UUID: String] = [:]

    private let api: WardrobeAPI
    private let repository: WardrobeRepository
    private let imageStore: ImageStore
    private let canUseAI: @MainActor () -> Bool
    private var worker: Task<Void, Never>?

    init(api: WardrobeAPI, repository: WardrobeRepository, imageStore: ImageStore, canUseAI: @escaping @MainActor () -> Bool) {
        self.api = api
        self.repository = repository
        self.imageStore = imageStore
        self.canUseAI = canUseAI
    }

    func isWorking(on id: UUID) -> Bool { current == id || pending.contains(id) }

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
        guard worker == nil, !pending.isEmpty else { return }
        worker = Task { [weak self] in
            while let self, !self.pending.isEmpty {
                let id = self.pending.removeFirst()
                self.current = id
                await self.process(id)
                self.current = nil
            }
            self?.worker = nil
        }
    }

    private func process(_ id: UUID) async {
        guard canUseAI() else {
            failures[id] = "Sign in (Profile) to create store photos."
            return
        }
        guard let garment = repository.garment(id: id),
              let sourceFile = garment.sourceImageFile,
              let source = imageStore.image(for: sourceFile),
              let jpeg = ImageProcessing.uploadJPEG(source) else {
            failures[id] = "There is no photo of this garment to work from."
            return
        }
        // Only describe the garment when the details are trustworthy (recognized or checked by the user);
        // unrecognized photos carry default values that could make the model recolor the garment.
        let hintsAreReliable = garment.category != .other && (garment.status == .confirmed || (garment.confidence ?? 0) >= 0.5)
        let hints: RenderGarmentHintsDTO? = !hintsAreReliable ? nil : RenderGarmentHintsDTO(
            name: garment.name.isEmpty ? nil : garment.name,
            category: garment.category.rawValue,
            subcategory: garment.subcategory.isEmpty ? nil : garment.subcategory,
            primaryColor: garment.primaryColor,
            secondaryColor: garment.secondaryColor,
            pattern: garment.pattern.rawValue,
            material: garment.material.isEmpty ? nil : garment.material
        )

        do {
            let result = try await api.renderProductPhoto(image: ImageProcessing.payload(jpeg), garment: hints)
            guard let data = Data(base64Encoded: result.data), UIImage(data: data) != nil else {
                failures[id] = "The store photo could not be read. Try again."
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
            failures[id] = (error as? LocalizedError)?.errorDescription ?? "The store photo could not be created. Try again."
        }
    }
}
