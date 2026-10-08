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

                results
            }
            .padding()
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
        case .notEnoughGarments(let count):
            let remaining = max(model.minimumClosetSize - count, 0)
            EmptyStateView(
                symbol: "tshirt",
                title: "Add a few more pieces",
                message: "Add \(remaining) more garment\(remaining == 1 ? "" : "s") to unlock your first outfits. Good outfits need options.",
                actionTitle: "Add garments",
                action: { router.openAdd() }
            )
        case .noMatches:
            EmptyStateView(
                symbol: "cloud.sun",
                title: "Nothing fits today",
                message: "No combination in your closet matches this occasion and weather. Try another style, or check Shop for what's missing."
            )
        case .loaded:
            ForEach(model.suggestions) { suggestion in
                OutfitCard(
                    title: suggestion.outfit.title,
                    reasoning: suggestion.outfit.reasoning,
                    tiles: model.tiles(for: suggestion),
                    isFavorite: suggestion.isFavorite,
                    isWorn: suggestion.isWornToday,
                    onWear: { model.wear(suggestion) },
                    onFavorite: { model.toggleFavorite(suggestion) },
                    onSwap: { slot in withAnimation { model.swap(slot, in: suggestion) } }
                )
                .transition(.opacity)
            }
        }
    }
}
