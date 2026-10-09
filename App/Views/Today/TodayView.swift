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
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.openAdd() } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .accessibilityLabel("Add garment")
                }
            }
        }
        .task {
            if model == nil { model = TodayViewModel(services: services) }
            await model?.loadWeather()
        }
    }
}

private struct TodayContent: View {
    @Bindable var model: TodayViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    eyebrow: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)),
                    title: "Today's look",
                    subtitle: greeting
                )

                WeatherCardView(
                    snapshot: model.weather?.snapshot,
                    isStale: model.weather?.isStale ?? false,
                    isLoading: model.isLoadingWeather,
                    attribution: model.attribution
                )
                if let error = model.weather?.errorMessage, model.weather?.snapshot == nil {
                    ErrorBanner(message: error) { Task { await model.loadWeather(force: true) } }
                }

                VStack(alignment: .leading, spacing: 12) {
                    EyebrowText("Occasion")
                    ChipRow(options: Occasion.allCases, selection: $model.occasion, title: \.displayName)
                        .accessibilityIdentifier("today.occasion")
                    EyebrowText("Style")
                        .padding(.top, 6)
                    ChipRow(options: Style.allCases, selection: $model.style, title: \.displayName)
                }

                Button {
                    Task { await model.suggest() }
                } label: {
                    Label(model.suggestions.isEmpty ? "Suggest outfits" : "Suggest again", systemImage: "sparkles")
                }
                .buttonStyle(.primary)
                .disabled(model.phase == .loading)
                .accessibilityIdentifier("today.suggest")

                results
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 32)
        }
        .refreshable { await model.refresh() }
        .sensoryFeedback(.success, trigger: model.wearFeedback)
        .sensoryFeedback(.impact(weight: .light), trigger: model.favoriteFeedback)
        .alert("Wardrobe", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.message ?? "")
        }
    }

    private var greeting: String {
        let part: String = switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        let name = model.userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? part + "." : "\(part), \(name)."
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
                symbol: "hanger",
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
            VStack(alignment: .leading, spacing: 8) {
                EyebrowText("\(model.suggestions.count) looks for \(model.occasion.displayName.lowercased())")
            }
            ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                OutfitCard(
                    title: suggestion.outfit.title,
                    reasoning: suggestion.outfit.reasoning,
                    tiles: model.tiles(for: suggestion),
                    isFavorite: suggestion.isFavorite,
                    isWorn: suggestion.isWornToday,
                    badge: String(format: "Look %02d", index + 1),
                    onWear: { withAnimation(.spring) { model.wear(suggestion) } },
                    onFavorite: { model.toggleFavorite(suggestion) },
                    onSwap: { slot in withAnimation(.snappy) { model.swap(slot, in: suggestion) } }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}
