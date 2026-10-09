import Foundation
import Observation
import OutfitEngine
import PhotosUI
import SwiftUI

/// Shared saving logic for all add flows: duplicate detection and insertion.
@MainActor
struct GarmentSaver {
    let services: AppServices

    /// Drafts that look like something already in the closet (or earlier in the same batch).
    func duplicates(in drafts: [GarmentDraft]) -> [GarmentDraft] {
        let closet = services.repository.garments(includeArchived: false)
        var keys = Set(closet.map { DuplicateDetector.key(category: $0.category, color: $0.primaryColor, brand: $0.brand) })
        var result: [GarmentDraft] = []
        for draft in drafts {
            let key = DuplicateDetector.key(category: draft.category, color: draft.primaryColor, brand: draft.brand)
            if keys.contains(key) { result.append(draft) }
            keys.insert(key)
        }
        return result
    }

    @discardableResult
    func save(_ drafts: [GarmentDraft], skipping skipped: Set<UUID> = []) -> Int {
        let owner = services.auth.appleUserID ?? "local"
        var count = 0
        var newPhotoGarments: [UUID] = []
        for draft in drafts {
            if skipped.contains(draft.id) {
                discardImages(of: draft)
                continue
            }
            let garment = draft.makeGarment(ownerID: owner)
            services.repository.insert(garment)
            if draft.source == .photo, garment.sourceImageFile != nil { newPhotoGarments.append(garment.id) }
            count += 1
        }
        // Store-style photos are created in the background after saving.
        services.productPhotos.enqueueNew(newPhotoGarments)
        return count
    }

    func discardImages(of draft: GarmentDraft) {
        for file in [draft.originalImageFile, draft.cutoutImageFile].compactMap({ $0 }) {
            services.imageStore.delete(file)
        }
    }
}

@MainActor
@Observable
final class PhotoImportViewModel {
    static let maxPhotos = 10

    struct Job: Identifiable {
        enum State: Equatable { case processing, recognized(Int), failed }
        let id = UUID()
        var thumbnail: UIImage
        var state: State = .processing
    }

    private(set) var jobs: [Job] = []
    var drafts: [GarmentDraft] = []
    private(set) var isProcessing = false
    var notice: String?

    private let services: AppServices

    init(services: AppServices) { self.services = services }

    func process(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items.prefix(Self.maxPhotos) {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        if items.count > Self.maxPhotos { notice = "Only the first \(Self.maxPhotos) photos were added." }
        await process(images)
    }

    func process(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }

        let processor = PhotoProcessor(imageStore: services.imageStore, remover: services.backgroundRemover)
        let canRecognize = services.auth.isSignedIn
        if !canRecognize { notice = "Sign in (Profile) to fill in details automatically. You can edit them by hand for now." }

        for image in images {
            let thumbnail = ImageProcessing.normalized(image, maxDimension: 300)
            jobs.append(Job(thumbnail: thumbnail))
            let jobIndex = jobs.count - 1

            guard let stored = await processor.store(image) else {
                jobs[jobIndex].state = .failed
                continue
            }

            var recognized: [GarmentDraft] = []
            if canRecognize {
                do {
                    recognized = try await services.recognizer.recognize(stored.analysisImage)
                } catch {
                    notice = "Couldn't recognize some photos automatically (\((error as? LocalizedError)?.errorDescription ?? "unknown error")). Fill in the details by hand."
                }
            }
            if recognized.isEmpty {
                var draft = GarmentDraft()
                draft.source = .photo
                draft.confidence = 0
                recognized = [draft]
            }

            for (index, recognizedDraft) in recognized.enumerated() {
                var draft = recognizedDraft
                if index == 0 {
                    draft.originalImageFile = stored.original
                    draft.cutoutImageFile = stored.cutout
                } else {
                    // Several garments in one photo: give each its own copy so deleting one keeps the others.
                    draft.originalImageFile = copy(stored.original)
                    draft.cutoutImageFile = stored.cutout.flatMap(copy)
                }
                drafts.append(draft)
            }
            jobs[jobIndex].state = canRecognize && recognized.first?.confidence != 0 ? .recognized(recognized.count) : .failed
        }
    }

    func remove(_ draft: GarmentDraft) {
        GarmentSaver(services: services).discardImages(of: draft)
        drafts.removeAll { $0.id == draft.id }
    }

    func discardAll() {
        let saver = GarmentSaver(services: services)
        for draft in drafts { saver.discardImages(of: draft) }
        drafts = []
        jobs = []
    }

    private func copy(_ file: String) -> String? {
        guard let data = services.imageStore.data(for: file) else { return nil }
        return try? services.imageStore.save(data, fileExtension: (file as NSString).pathExtension)
    }
}

@MainActor
@Observable
final class OrderImportViewModel {
    var text = ""
    var screenshot: UIImage?
    var drafts: [GarmentDraft] = []
    private(set) var isParsing = false
    private(set) var isDownloadingImages = false
    var errorMessage: String?

    private let services: AppServices

    init(services: AppServices) { self.services = services }

    var canParse: Bool {
        !isParsing && (screenshot != nil || text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20)
    }

    func load(_ pending: PendingImport) {
        switch pending.kind {
        case .text: text = pending.text ?? ""
        case .image: screenshot = PendingImportStore.shared.imageData(for: pending).flatMap(UIImage.init(data:))
        }
        PendingImportStore.shared.remove(pending)
    }

    func parse() async {
        guard canParse else { return }
        guard services.auth.isSignedIn else {
            errorMessage = "Sign in (Profile) to import orders. Reading orders uses AI on our server."
            return
        }
        errorMessage = nil
        isParsing = true
        defer { isParsing = false }
        do {
            let source: PurchaseSource = screenshot.map { .screenshot($0) } ?? .text(text)
            let parsed = try await services.purchaseImporter.importPurchases(from: source)
            guard !parsed.isEmpty else {
                errorMessage = "No clothing items were found in this order."
                return
            }
            drafts = parsed
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The order could not be read."
            return
        }
        await downloadImages()
    }

    /// Downloads product images with a size limit and timeout; failures leave a placeholder.
    private func downloadImages() async {
        isDownloadingImages = true
        defer { isDownloadingImages = false }
        let processor = PhotoProcessor(imageStore: services.imageStore, remover: services.backgroundRemover)
        for index in drafts.indices {
            guard let url = drafts[index].remoteImageURL,
                  let image = await services.imageDownloader.download(url),
                  let stored = await processor.store(image) else { continue }
            drafts[index].originalImageFile = stored.original
            drafts[index].cutoutImageFile = stored.cutout
        }
    }

    func remove(_ draft: GarmentDraft) {
        GarmentSaver(services: services).discardImages(of: draft)
        drafts.removeAll { $0.id == draft.id }
    }

    func reset() {
        let saver = GarmentSaver(services: services)
        for draft in drafts { saver.discardImages(of: draft) }
        drafts = []
        text = ""
        screenshot = nil
    }
}
