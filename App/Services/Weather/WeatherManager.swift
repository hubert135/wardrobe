import CoreLocation
import Foundation

struct WeatherResult {
    var snapshot: WeatherSnapshot?
    /// True when the snapshot comes from the offline cache after a failed refresh.
    var isStale: Bool
    var errorMessage: String?
}

/// Persists the last forecast so it can be shown offline.
struct WeatherCache {
    private let defaults: UserDefaults
    private let key = "weather.lastSnapshot"
    private let keyLocation = "weather.lastLocationKey"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> (snapshot: WeatherSnapshot, locationKey: String)? {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: data) else { return nil }
        return (snapshot, defaults.string(forKey: keyLocation) ?? "")
    }

    func store(_ snapshot: WeatherSnapshot, locationKey: String) {
        defaults.set(try? JSONEncoder().encode(snapshot), forKey: key)
        defaults.set(locationKey, forKey: keyLocation)
    }
}

/// Orchestrates location (or city override), the provider and the offline cache.
@MainActor
final class WeatherManager {
    static let freshness: TimeInterval = 30 * 60

    let provider: WeatherProvider
    private let location: LocationService
    private let cache: WeatherCache

    init(provider: WeatherProvider, location: LocationService, cache: WeatherCache = WeatherCache()) {
        self.provider = provider
        self.location = location
        self.cache = cache
    }

    func current(cityOverride: String?, forceRefresh: Bool = false) async -> WeatherResult {
        let city = cityOverride?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        let locationKey = city.map { "city:\($0.lowercased())" } ?? "current"
        let cached = cache.load()

        if !forceRefresh, let cached, cached.locationKey == locationKey,
           Date().timeIntervalSince(cached.snapshot.fetchedAt) < Self.freshness {
            return WeatherResult(snapshot: cached.snapshot, isStale: false)
        }

        do {
            let place: CLLocation
            let name: String
            if !provider.needsLocation {
                place = CLLocation(latitude: 52.2297, longitude: 21.0122)
                name = city ?? "Sample city"
            } else if let city {
                place = try await location.location(forCity: city)
                name = city
            } else {
                place = try await location.currentLocation()
                name = await location.placeName(for: place)
            }
            let reading = try await provider.currentWeather(for: place)
            let snapshot = WeatherMapper.snapshot(from: reading, locationName: name)
            cache.store(snapshot, locationKey: locationKey)
            return WeatherResult(snapshot: snapshot, isStale: false)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Weather is unavailable right now."
            return WeatherResult(snapshot: cached?.snapshot, isStale: cached != nil, errorMessage: message)
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
