import OutfitEngine
import PhotosUI
import SwiftUI

enum AddTab: String, CaseIterable, Identifiable {
    case photos = "Photos"
    case order = "Order"
    case manual = "Manual"
    var id: String { rawValue }
}

struct AddGarmentSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var tab: AddTab
    @State private var photoModel: PhotoImportViewModel?
    @State private var orderModel: OrderImportViewModel?

    init(initialTab: AddTab) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Source", selection: $tab) {
                    ForEach(AddTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    switch tab {
                    case .photos:
                        if let photoModel { PhotoImportView(model: photoModel, onDone: { dismiss() }) }
                    case .order:
                        if let orderModel { OrderImportView(model: orderModel, onDone: { dismiss() }) }
                    case .manual:
                        ManualEntryView(onDone: { dismiss() })
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .navigationTitle("Add to closet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        photoModel?.discardAll()
                        orderModel?.reset()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(!(photoModel?.drafts.isEmpty ?? true) || !(orderModel?.drafts.isEmpty ?? true))
        .task {
            if photoModel == nil { photoModel = PhotoImportViewModel(services: services) }
            if orderModel == nil { orderModel = OrderImportViewModel(services: services) }
            if let pending = router.pendingImport, let orderModel {
                orderModel.load(pending)
                router.pendingImport = nil
                tab = .order
                await orderModel.parse()
            }
        }
    }
}

// MARK: Photos

struct PhotoImportView: View {
    @Bindable var model: PhotoImportViewModel
    var onDone: () -> Void
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isCameraPresented = false

    var body: some View {
        if model.drafts.isEmpty && !model.isProcessing {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "camera.on.rectangle")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.accent)
                Text("Photograph clothes on a plain background. Backgrounds are removed on your iPhone, then the details are filled in for you.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                PhotosPicker(selection: $pickerItems, maxSelectionCount: PhotoImportViewModel.maxPhotos, matching: .images) {
                    Label("Choose up to \(PhotoImportViewModel.maxPhotos) photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                if CameraView.isAvailable {
                    Button {
                        isCameraPresented = true
                    } label: {
                        Label("Take a photo", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                if let notice = model.notice {
                    Text(notice).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding()
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    await model.process(items)
                    pickerItems = []
                }
            }
            .fullScreenCover(isPresented: $isCameraPresented) {
                CameraView { image in
                    Task { await model.process([image]) }
                }
                .ignoresSafeArea()
            }
        } else {
            DraftReviewView(
                drafts: $model.drafts,
                isWorking: model.isProcessing,
                workingText: "Removing backgrounds and recognizing garments…",
                notice: model.notice,
                onRemove: { model.remove($0) },
                onDone: onDone
            )
        }
    }
}

// MARK: Order

struct OrderImportView: View {
    @Bindable var model: OrderImportViewModel
    var onDone: () -> Void
    @State private var screenshotItem: PhotosPickerItem?

    var body: some View {
        if model.drafts.isEmpty {
            Form {
                Section {
                    TextEditor(text: $model.text)
                        .frame(minHeight: 180)
                        .overlay(alignment: .topLeading) {
                            if model.text.isEmpty {
                                Text("Paste the text of an order confirmation email…")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                    PhotosPicker(selection: $screenshotItem, matching: .screenshots) {
                        Label(model.screenshot == nil ? "Or choose an order screenshot" : "Screenshot selected", systemImage: "photo")
                    }
                    if let screenshot = model.screenshot {
                        HStack {
                            Image(uiImage: screenshot).resizable().scaledToFit().frame(height: 120)
                            Spacer()
                            Button("Remove", role: .destructive) { model.screenshot = nil }
                        }
                    }
                } footer: {
                    Text("Tip: from Mail, use Share → Add to Wardrobe. Items are added as \"Needs review\".")
                }

                if let error = model.errorMessage {
                    Section { ErrorBanner(message: error) { Task { await model.parse() } } }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                Section {
                    Button {
                        Task { await model.parse() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.isParsing { ProgressView() } else { Text("Find items").bold() }
                            Spacer()
                        }
                    }
                    .disabled(!model.canParse)
                }
            }
            .onChange(of: screenshotItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { model.screenshot = UIImage(data: data) }
                    screenshotItem = nil
                }
            }
        } else {
            DraftReviewView(
                drafts: $model.drafts,
                isWorking: model.isDownloadingImages,
                workingText: "Downloading product images…",
                notice: "Imported items are marked \"Needs review\". Add a photo later if an image is missing.",
                onRemove: { model.remove($0) },
                onDone: onDone
            )
        }
    }
}

// MARK: Review

struct DraftReviewView: View {
    @Environment(AppServices.self) private var services
    @Binding var drafts: [GarmentDraft]
    var isWorking: Bool
    var workingText: String
    var notice: String?
    var onRemove: (GarmentDraft) -> Void
    var onDone: () -> Void

    @State private var editing: GarmentDraft?
    @State private var duplicates: [GarmentDraft] = []
    @State private var savedFeedback = 0

    var body: some View {
        List {
            if isWorking {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(workingText).font(.subheadline)
                    }
                }
            }
            if let notice {
                Section { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("\(drafts.count) item\(drafts.count == 1 ? "" : "s")") {
                ForEach($drafts) { $draft in
                    DraftCard(draft: $draft) { editing = draft }
                        .swipeActions {
                            Button("Remove", role: .destructive) { onRemove(draft) }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                confirmAll()
            } label: {
                Text("Confirm all").bold().frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .padding()
            .background(.bar)
            .disabled(drafts.isEmpty || isWorking)
            .accessibilityIdentifier("review.confirmAll")
        }
        .sheet(item: $editing) { draft in
            DraftEditSheet(draft: draft) { updated in
                if let index = drafts.firstIndex(where: { $0.id == updated.id }) { drafts[index] = updated }
            }
        }
        .alert("Possible duplicates", isPresented: Binding(get: { !duplicates.isEmpty }, set: { if !$0 { duplicates = [] } })) {
            Button("Add anyway") { save(skipping: []) }
            Button("Skip duplicates") { save(skipping: Set(duplicates.map(\.id))) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You may already own: " + duplicates.map(\.displayName).joined(separator: ", ") + ".")
        }
        .sensoryFeedback(.success, trigger: savedFeedback)
    }

    private func confirmAll() {
        let found = GarmentSaver(services: services).duplicates(in: drafts)
        if found.isEmpty { save(skipping: []) } else { duplicates = found }
    }

    private func save(skipping skipped: Set<UUID>) {
        GarmentSaver(services: services).save(drafts, skipping: skipped)
        drafts = []
        savedFeedback += 1
        onDone()
    }
}

/// Compact card with quick edits for the most important fields.
struct DraftCard: View {
    @Binding var draft: GarmentDraft
    var onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GarmentImageView(fileName: draft.cutoutImageFile ?? draft.originalImageFile, category: draft.category, color: draft.primaryColor, maxPixels: 300)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                TextField("Name", text: edited(\.name))
                    .font(.headline)
                HStack {
                    Menu {
                        Picker("Category", selection: edited(\.category)) {
                            ForEach(GarmentCategory.allCases) { Text($0.displayName).tag($0) }
                        }
                    } label: {
                        Label(draft.category.displayName, systemImage: "tag").font(.caption)
                    }
                    Menu {
                        Picker("Color", selection: edited(\.primaryColor)) {
                            ForEach(ColorPalette.all) { Text($0.displayName).tag($0.name) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(Color.garment(draft.primaryColor)).frame(width: 10, height: 10)
                            Text(draft.primaryColor.capitalized).font(.caption)
                        }
                    }
                }
                Stepper(value: edited(\.formality), in: Formality.range) {
                    Text("Formality \(draft.formality) · \(Formality.label(draft.formality))").font(.caption)
                }
                HStack {
                    if draft.resolvedStatus == .pendingReview {
                        Label("Needs review", systemImage: "exclamationmark.circle").font(.caption2).foregroundStyle(.orange)
                    } else if let confidence = draft.confidence {
                        Text("\(Int(confidence * 100))% sure").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit all", action: onEdit).font(.caption.bold()).buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Binding that also marks the draft as edited by the user.
    private func edited<Value>(_ keyPath: WritableKeyPath<GarmentDraft, Value>) -> Binding<Value> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = $0; draft.wasEdited = true }
        )
    }
}

struct DraftEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: GarmentDraft
    var onSave: (GarmentDraft) -> Void

    var body: some View {
        NavigationStack {
            Form {
                GarmentFormSections(draft: $draft)
            }
            .navigationTitle("Edit garment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.wasEdited = true
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: Manual

struct ManualEntryView: View {
    @Environment(AppServices.self) private var services
    var onDone: () -> Void
    @State private var draft = GarmentDraft()
    @State private var userPickedCategory = false
    @State private var duplicateWarning = false
    @State private var savedFeedback = 0

    var body: some View {
        Form {
            GarmentFormSections(draft: $draft, currencyCode: services.repository.profile().currencyCode)
            Section {
                Button {
                    save(force: false)
                } label: {
                    HStack { Spacer(); Text("Add to closet").bold(); Spacer() }
                }
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { save(force: false) }
                    .bold()
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("manual.save")
            }
        }
        .onChange(of: draft.name) { _, _ in
            guard !userPickedCategory else { return }
            ManualEntryInference.apply(to: &draft)
        }
        .onChange(of: draft.category) { old, new in
            // Only a change the user makes (not inference) stops further guessing.
            if old != new, ManualEntryInference.category(in: draft.name) != new { userPickedCategory = true }
        }
        .alert("Possible duplicate", isPresented: $duplicateWarning) {
            Button("Add anyway") { save(force: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You already have a \(draft.primaryColor) \(draft.category.displayName.lowercased())\(draft.brand.isEmpty ? "" : " from \(draft.brand)").")
        }
        .sensoryFeedback(.success, trigger: savedFeedback)
    }

    private func save(force: Bool) {
        draft.source = .manual
        let saver = GarmentSaver(services: services)
        if !force, !saver.duplicates(in: [draft]).isEmpty {
            duplicateWarning = true
            return
        }
        saver.save([draft])
        savedFeedback += 1
        onDone()
    }
}
