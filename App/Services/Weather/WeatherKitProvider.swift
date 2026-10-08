import CoreLocation
import Foundation
import WeatherKit

/// Apple WeatherKit (same data as the iPhone Weather app). Requires the WeatherKit capability
/// on a paid developer team; see README "Enabling WeatherKit".
final class WeatherKitProvider: WeatherProvider {
    private let service = WeatherService.shared

    var needsLocation: Bool { true }

    func currentWeather(for location: CLLocation) async throws -> WeatherReading {
        let (current, daily) = try await service.weather(for: location, including: .current, .daily)
        return WeatherMapper.reading(
            temperature: current.temperature,
            apparentTemperature: current.apparentTemperature,
            precipitationChance: daily.forecast.first?.precipitationChance ?? 0,
            windSpeed: current.wind.speed,
            conditionDescription: current.condition.description,
            symbolName: current.symbolName
        )
    }

    /// Apple requires showing the Weather attribution next to WeatherKit data.
    func attribution() async -> WeatherAttributionInfo? {
        guard let attribution = try? await service.attribution else { return nil }
        return WeatherAttributionInfo(serviceName: attribution.serviceName, legalPageURL: attribution.legalPageURL)
    }
}
