import Foundation
import Observation
import OutfitEngine

@MainActor
@Observable
final class TodayViewModel {
    enum Phase: Equatable { case idle, loading, loaded, notEnoughGarments(count: Int), noMatches }

    var occasion: Occasion = .work
    var style: Style = .smartCasual
    private(set) var phase: Phase = .idle
    private(set) var suggestions: [OutfitSuggestion] = []
    private(set) var weather: WeatherResult?
    private(set) var isLoadingWeather = false
    private(set) var attribution: WeatherAttributionInfo?
    var message: String?
    /// Incremented on key actions to trigger haptics in the view.
    private(set) var wearFeedback = 0
    private(set) var favoriteFeedback = 0

    private let services: AppServices
    private var garmentsByID: [UUID: Garment] = [:]

    init(services: AppServices) {
        self.services = services
        let profile = services.repository.profile()
        occasion = profile.occasion(for: Date())
        style = profile.lastStyle
    }

    var minimumClosetSize: Int { services.outfits.engine.config.minimumClosetSize }
    var userName: String { services.repository.profile().name }

    func loadWeather(force: Bool = false) async {
        isLoadingWeather = true
        defer { isLoadingWeather = false }
        let profile = services.repository.profile()
        weather = await services.weather.current(cityOverride: profile.cityOverride, forceRefresh: force)
        if attribution == nil { attribution = await services.weather.provider.attribution() }
    }

    func refresh() async {
        await loadWeather(force: true)
        if !suggestions.isEmpty { await suggest() }
    }

    func suggest() async {
        let repository = services.repository
        let profile = repository.profile()
        profile.remember(occasion: occasion, style: style, on: Date())
        repository.save()

        let garments = repository.garments(includeArchived: false)
        garmentsByID = Dictionary(uniqueKeysWithValues: garments.map { ($0.id, $0) })
        let closet = garments.map(\.engineGarment)
        guard services.outfits.engine.hasEnoughGarments(closet) else {
            suggestions = []
            phase = .notEnoughGarments(count: closet.count)
            return
        }

        phase = .loading
        if weather == nil { await loadWeather() }
        let context = makeContext(profile: profile)
        let (outfits, origin) = await services.outfits.suggestions(closet: closet, context: context, count: 3)
        suggestions = outfits.map { outfit in
            OutfitSuggestion(
                outfit: outfit, occasion: occasion, style: style, season: context.season ?? .autumn,
                weather: weather?.snapshot, origin: origin,
                isFavorite: repository.favorite(combinationKey: outfit.id) != nil,
                isWornToday: false
            )
        }
        phase = suggestions.isEmpty ? .noMatches : .loaded
    }

    func tiles(for suggestion: OutfitSuggestion) -> [CollageTile] {
        OutfitPresenter.tiles(for: suggestion.outfit, garments: garmentsByID)
    }

    func wear(_ suggestion: OutfitSuggestion) {
        guard let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
        services.repository.saveOutfit(suggestion, wornOn: Date(), favorite: false)
        suggestions[index].isWornToday = true
        wearFeedback += 1
        message = "Saved to your history. Have a good day!"
    }

    func toggleFavorite(_ suggestion: OutfitSuggestion) {
        guard let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
        let repository = services.repository
        if let existing = repository.favorite(combinationKey: suggestion.outfit.id) {
            if existing.wornOn == nil { repository.delete(existing) } else { existing.isFavorite = false; repository.save() }
            suggestions[index].isFavorite = false
        } else {
            repository.saveOutfit(suggestion, wornOn: nil, favorite: true)
            suggestions[index].isFavorite = true
        }
        favoriteFeedback += 1
    }

    func swap(_ slot: Slot, in suggestion: OutfitSuggestion) {
        guard let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
        let closet = garmentsByID.values.map(\.engineGarment)
        let context = makeContext(profile: services.repository.profile())
        guard let swapped = services.outfits.engine.swap(slot, in: suggestion.outfit, closet: closet, context: context) else {
            message = "No other \(slot.displayName.lowercased()) fits this outfit right now."
            return
        }
        suggestions[index].outfit = swapped
        suggestions[index].origin = .local
        suggestions[index].isWornToday = false
        suggestions[index].isFavorite = services.repository.favorite(combinationKey: swapped.id) != nil
    }

    private func makeContext(profile: UserProfile) -> OutfitContext {
        let now = Date()
        return OutfitContext(
            occasion: occasion,
            style: style,
            season: Season.from(date: now),
            weather: weather?.snapshot?.engineWeather,
            date: now,
            preferences: profile.stylePreferences
        )
    }
}
