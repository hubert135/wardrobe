import OutfitEngine
import SwiftUI

struct TodayView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @State private var model: TodayViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    TodayContent(model: model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.openAdd() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add garment")
                }
            }
        }
        .task {
            if model == nil { model = TodayViewModel(services: services) }
            await model?.loadWeather()
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}

private struct TodayContent: View {
    @Bindable var model: TodayViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                WeatherCardView(
                    snapshot: model.weather?.snapshot,
                    isStale: model.weather?.isStale ?? false,
                    isLoading: model.isLoadingWeather,
                    attribution: model.attribution
                )
                if let error = model.weather?.errorMessage, model.weather?.snapshot == nil {
                    ErrorBanner(message: error) { Task { await model.loadWeather(force: true) } }
                }

                contextSelector

                Button {
                    Task { await model.suggest() }
                } label: {
                    Label("Suggest outfits", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.phase == .loading)
                .accessibilityIdentifier("today.suggest")

                VStack(alignment: .leading, spacing: Theme.spacing) {
                    results
                }
                .id("results")
            }
            .padding()
        }
        .onChange(of: model.phase) { _, phase in
            guard phase != .idle else { return }
            withAnimation { proxy.scrollTo("results", anchor: .top) }
        }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable { await model.refresh() }
        .sensoryFeedback(.success, trigger: model.wearFeedback)
        .sensoryFeedback(.impact(weight: .light), trigger: model.favoriteFeedback)
        .alert("Wardrobe", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.message ?? "")
        }
    }

    private var contextSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Occasion", selection: $model.occasion) {
                ForEach(Occasion.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("today.occasion")

            Picker("Style", selection: $model.style) {
                ForEach(Style.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .card()
    }

    @ViewBuilder
    private var results: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .loading:
            ForEach(0..<2, id: \.self) { _ in OutfitCardSkeleton() }
        case .notEnoughGarments(let usable, let uncategorized):
            let remaining = max(model.minimumClosetSize - usable, 0)
            if uncategorized > 0 {
                EmptyStateView(
                    symbol: "tag",
                    title: "Some garments need a category",
                    message: "\(uncategorized) of your garments \(uncategorized == 1 ? "has" : "have") no category yet (shirt, trousers, shoes…), so they can't be used in outfits. Open them in Closet → Needs review and tap Edit. You need \(remaining) more usable garment\(remaining == 1 ? "" : "s").",
                    actionTitle: "Open Closet",
                    action: { router.selectedTab = .closet }
                )
            } else {
                EmptyStateView(
                    symbol: "tshirt",
                    title: "Add a few more pieces",
                    message: "Add \(remaining) more garment\(remaining == 1 ? "" : "s") to unlock your first outfits. Good outfits need options.",
                    actionTitle: "Add garments",
                    action: { router.openAdd() }
                )
            }
        case .noMatches:
            EmptyStateView(
                symbol: "cloud.sun",
                title: "Nothing fits today",
                message: "No combination in your closet matches this occasion and weather. Try another style, or check Shop for what's missing."
            )
            UnlockLooksView(model: model)
        case .loaded:
            ForEach(model.suggestions) { suggestion in
                OutfitCard(
                    title: suggestion.outfit.title,
                    reasoning: suggestion.outfit.reasoning,
                    tiles: model.tiles(for: suggestion),
                    isFavorite: suggestion.isFavorite,
                    isWorn: suggestion.isWornToday,
                    subtitle: model.recipeLabel(for: suggestion.outfit.recipe),
                    modelMode: .auto,
                    onWear: { model.wear(suggestion) },
                    onFavorite: { model.toggleFavorite(suggestion) },
                    onSwap: { slot in withAnimation { model.swap(slot, in: suggestion) } }
                )
                .transition(.opacity)
            }
            UnlockLooksView(model: model)
        }
    }
}

/// Shown when the closet can't make three genuinely different outfits: one piece per extra look.
private struct UnlockLooksView: View {
    var model: TodayViewModel

    var body: some View {
        if !model.unlocks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.suggestions.isEmpty ? "One piece away from an outfit" : "Only \(model.suggestions.count) different outfit\(model.suggestions.count == 1 ? "" : "s") today")
                        .font(.headline)
                    Text("Rather than repeat the same look with other shoes, here is what would add a new one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.unlocks) { unlock in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "plus.circle.dashed")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(unlock.piece.displayName).font(.subheadline.bold())
                            Text("Unlocks: \(unlock.recipe.title) · \(unlock.recipe.effectiveLook.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(model.isOnShoppingList(unlock) ? "On list" : "Add to list") { model.addToShoppingList(unlock) }
                            .font(.caption.bold())
                            .buttonStyle(.bordered)
                            .disabled(model.isOnShoppingList(unlock))
                    }
                }
            }
            .padding()
            .card()
        }
    }
}
