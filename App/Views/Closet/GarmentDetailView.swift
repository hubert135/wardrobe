import OutfitEngine
import PhotosUI
import SwiftData
import SwiftUI

struct GarmentDetailView: View {
    let garmentID: UUID

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [Garment]
    @State private var draft = GarmentDraft()
    @State private var isEditing = false
    @State private var isDeleteConfirmationPresented = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isProcessingPhoto = false

    init(garmentID: UUID) {
        self.garmentID = garmentID
        _matches = Query(filter: #Predicate<Garment> { $0.id == garmentID })
    }

    private var garment: Garment? { matches.first }

    var body: some View {
        Group {
            if let garment {
                content(garment)
            } else {
                ContentUnavailableView("Garment not found", systemImage: "questionmark.square.dashed")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ garment: Garment) -> some View {
        Form {
            Section {
                GarmentImageView(garment: garment, maxPixels: 1200)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .listRowInsets(EdgeInsets())
                    .overlay(alignment: .bottomTrailing) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(garment.displayImageFile == nil ? "Add photo" : "Replace photo", systemImage: "camera")
                                .font(.caption.bold())
                                .padding(8)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .padding(10)
                    }
                    .overlay {
                        if isProcessingPhoto { ProgressView().controlSize(.large) }
                    }
            }

            if garment.status == .pendingReview {
                Section {
                    Button {
                        garment.status = .confirmed
                        garment.touch()
                        services.repository.save()
                    } label: {
                        Label("Looks right, confirm", systemImage: "checkmark.seal")
                    }
                } footer: {
                    Text("The details were filled in automatically. Confirm or fix them so outfits are accurate.")
                }
            }

            if isEditing {
                GarmentFormSections(draft: $draft, currencyCode: services.repository.profile().currencyCode)
            } else {
                summary(garment)
            }

            Section("Usage") {
                LabeledContent("Worn", value: "\(garment.wearCount) time\(garment.wearCount == 1 ? "" : "s")")
                if let last = garment.lastWornAt {
                    LabeledContent("Last worn", value: last.formatted(date: .abbreviated, time: .omitted))
                }
                if let costPerWear = garment.costPerWear {
                    LabeledContent("Cost per wear", value: costPerWear.currency(services.repository.profile().currencyCode))
                }
                Button {
                    router.buildOutfits(with: garment.id)
                } label: {
                    Label("Build outfits with this", systemImage: "wand.and.stars")
                }
            }

            let outfits = (garment.outfitSlots ?? []).compactMap(\.outfit)
            if !outfits.isEmpty {
                Section("In outfits") {
                    ForEach(outfits.sorted { ($0.wornOn ?? $0.createdAt) > ($1.wornOn ?? $1.createdAt) }) { outfit in
                        VStack(alignment: .leading) {
                            Text(outfit.title).font(.subheadline)
                            Text(outfit.wornOn.map { "Worn \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Favorite")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                if garment.status == .archived {
                    Button("Restore to closet") { setStatus(.confirmed, on: garment) }
                } else {
                    Button("Archive") { setStatus(.archived, on: garment) }
                }
                Button("Delete", role: .destructive) { isDeleteConfirmationPresented = true }
            } footer: {
                Text("Archived items stay in your history but are never suggested.")
            }
        }
        .paperBackground()
        .navigationTitle(garment.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        draft.apply(to: garment)
                        if garment.status == .pendingReview { garment.status = .confirmed }
                        services.repository.save()
                    } else {
                        draft = GarmentDraft(garment: garment)
                    }
                    isEditing.toggle()
                }
            }
        }
        .confirmationDialog("Delete \(garment.displayName)?", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                services.repository.delete(garment)
                dismiss()
            }
        } message: {
            Text("The photo and the garment are removed from this device. This can't be undone.")
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await attachPhoto(item, to: garment) }
        }
    }

    private func summary(_ garment: Garment) -> some View {
        Section("Details") {
            LabeledContent("Category", value: garment.category.displayName)
            if !garment.subcategory.isEmpty { LabeledContent("Type", value: garment.subcategory) }
            LabeledContent("Color") {
                HStack {
                    Circle().fill(Color.garment(garment.primaryColor)).frame(width: 14, height: 14)
                    Text(garment.primaryColor.capitalized + (garment.secondaryColor.map { " / \($0)" } ?? ""))
                }
            }
            LabeledContent("Pattern", value: garment.pattern.displayName)
            if !garment.material.isEmpty { LabeledContent("Material", value: garment.material) }
            LabeledContent("Formality", value: "\(garment.formality) · \(Formality.label(garment.formality))")
            LabeledContent("Seasons", value: garment.seasons.isEmpty ? "All year" : Season.allCases.filter(garment.seasons.contains).map(\.displayName).joined(separator: ", "))
            if !garment.brand.isEmpty { LabeledContent("Brand", value: garment.brand) }
            if !garment.size.isEmpty { LabeledContent("Size", value: garment.size) }
            if let price = garment.price { LabeledContent("Price", value: price.currency(services.repository.profile().currencyCode)) }
            if let date = garment.purchaseDate { LabeledContent("Bought", value: date.formatted(date: .abbreviated, time: .omitted)) }
        }
    }

    private func setStatus(_ status: GarmentStatus, on garment: Garment) {
        garment.status = status
        garment.touch()
        services.repository.save()
    }

    private func attachPhoto(_ item: PhotosPickerItem, to garment: Garment) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false; photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let processor = PhotoProcessor(imageStore: services.imageStore, remover: services.backgroundRemover)
        guard let stored = await processor.store(image) else { return }
        for file in [garment.originalImageFile, garment.cutoutImageFile].compactMap({ $0 }) { services.imageStore.delete(file) }
        garment.originalImageFile = stored.original
        garment.cutoutImageFile = stored.cutout
        garment.touch()
        services.repository.save()
    }
}
