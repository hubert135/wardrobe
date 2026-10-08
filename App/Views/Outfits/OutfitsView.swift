import OutfitEngine
import SwiftData
import SwiftUI

struct OutfitsView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $router.outfitsSegment) {
                    ForEach(OutfitsSegment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                switch router.outfitsSegment {
                case .favorites: FavoritesList()
                case .history: HistoryList()
                case .builder: BuilderView()
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Outfits")
        }
    }
}

private struct FavoritesList: View {
    @Environment(AppServices.self) private var services
    @Query(filter: #Predicate<Outfit> { $0.isFavorite }, sort: \Outfit.createdAt, order: .reverse) private var favorites: [Outfit]
    @State private var wearFeedback = 0
    @State private var message: String?

    var body: some View {
        if favorites.isEmpty {
            EmptyStateView(symbol: "heart", title: "No favorites yet", message: "Tap the heart on any outfit to keep it here.")
        } else {
            ScrollView {
                LazyVStack(spacing: Theme.spacing) {
                    ForEach(favorites) { outfit in
                        OutfitCard(
                            title: outfit.title,
                            reasoning: outfit.reasoning,
                            tiles: OutfitPresenter.tiles(for: outfit),
                            isFavorite: true,
                            subtitle: "\(outfit.occasion.displayName) · \(outfit.style.displayName)",
                            onWear: {
                                services.repository.recordWear(of: outfit, on: Date())
                                wearFeedback += 1
                                message = "Saved to your history."
                            },
                            onFavorite: { unfavorite(outfit) }
                        )
                    }
                }
                .padding()
            }
            .sensoryFeedback(.success, trigger: wearFeedback)
            .alert("Wardrobe", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
        }
    }

    private func unfavorite(_ outfit: Outfit) {
        if outfit.wornOn == nil {
            services.repository.delete(outfit)
        } else {
            outfit.isFavorite = false
            services.repository.save()
        }
    }
}

private struct HistoryList: View {
    @Environment(AppServices.self) private var services
    @Query(filter: #Predicate<Outfit> { $0.wornOn != nil }, sort: [SortDescriptor(\Outfit.wornOn, order: .reverse)]) private var history: [Outfit]

    var body: some View {
        if history.isEmpty {
            EmptyStateView(symbol: "calendar", title: "Nothing worn yet", message: "Tap \"I'm wearing this\" on an outfit and it appears here.")
        } else {
            List {
                ForEach(history) { outfit in
                    HStack(spacing: 12) {
                        OutfitCollageView(tiles: OutfitPresenter.tiles(for: outfit), height: 90)
                            .frame(width: 90)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(outfit.wornOn?.formatted(date: .complete, time: .omitted) ?? "")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(outfit.title).font(.subheadline.bold())
                            Text(outfit.reasoning).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { services.repository.delete(outfit) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct BuilderView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @State private var model: BuilderViewModel?

    var body: some View {
        Group {
            if let model {
                BuilderContent(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil { model = BuilderViewModel(services: services) }
            if let anchor = router.builderAnchorID, let model {
                model.anchorIDs = [anchor]
                router.builderAnchorID = nil
                model.run()
            }
        }
        .onChange(of: router.builderAnchorID) { _, anchor in
            guard let anchor, let model else { return }
            model.anchorIDs = [anchor]
            router.builderAnchorID = nil
            model.run()
        }
    }
}

private struct BuilderContent: View {
    @Bindable var model: BuilderViewModel
    @State private var isPickerPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Start from").font(.headline)
                        Spacer()
                        Button(model.anchorIDs.isEmpty ? "Choose pieces" : "Change") { isPickerPresented = true }
                    }
                    if model.anchors.isEmpty {
                        Text("Pick one or more garments, for example your navy trousers.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(model.anchors) { garment in
                                    GarmentImageView(garment: garment, maxPixels: 200)
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .accessibilityLabel(garment.displayName)
                                }
                            }
                        }
                    }
                    Picker("Occasion", selection: $model.occasion) {
                        ForEach(Occasion.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Style", selection: $model.style) {
                        ForEach(Style.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Season", selection: $model.season) {
                        ForEach(Season.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Include items to buy", isOn: $model.includeMissing)
                }
                .padding()
                .card()

                Button {
                    withAnimation { model.run() }
                } label: {
                    Label("Build outfits", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if model.hasRun && model.results.isEmpty {
                    EmptyStateView(
                        symbol: "square.stack.3d.up.slash",
                        title: "No outfits found",
                        message: model.includeMissing
                            ? "These pieces don't combine for this occasion and season."
                            : "Nothing in your closet matches yet. Turn on \"Include items to buy\" to see what's missing."
                    )
                }

                ForEach(model.results) { suggestion in
                    OutfitCard(
                        title: suggestion.outfit.title,
                        reasoning: suggestion.outfit.reasoning,
                        tiles: model.tiles(for: suggestion),
                        isFavorite: suggestion.isFavorite,
                        isWorn: suggestion.isWornToday,
                        onWear: { model.wear(suggestion) },
                        onFavorite: { model.toggleFavorite(suggestion) },
                        onAddMissing: { model.addToShoppingList($0) }
                    )
                }
            }
            .padding()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.favoriteFeedback)
        .sensoryFeedback(.success, trigger: model.wearFeedback)
        .sheet(isPresented: $isPickerPresented) {
            GarmentMultiPicker(selection: $model.anchorIDs)
        }
        .alert("Shopping list", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.message ?? "") }
    }
}

/// Grid to pick builder starting points.
struct GarmentMultiPicker: View {
    @Binding var selection: Set<UUID>
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Garment.categoryRaw) private var garments: [Garment]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(garments.filter { $0.status != .archived }) { garment in
                        Button {
                            if selection.contains(garment.id) { selection.remove(garment.id) } else { selection.insert(garment.id) }
                        } label: {
                            GarmentTile(garment: garment)
                                .overlay(alignment: .topLeading) {
                                    Image(systemName: selection.contains(garment.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selection.contains(garment.id) ? Theme.accent : .secondary)
                                        .background(Circle().fill(.background))
                                        .padding(6)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection.contains(garment.id) ? .isSelected : [])
                    }
                }
                .padding()
            }
            .navigationTitle("Starting pieces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Clear") { selection = [] } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
