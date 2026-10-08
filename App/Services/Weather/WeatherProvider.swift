import CoreLocation
import Foundation

/// Provider-neutral current conditions in metric units.
struct WeatherReading: Equatable {
    var temperatureC: Double
    var feelsLikeC: Double
    /// 0...1 for today.
    var precipitationChance: Double
    var windKph: Double
    var conditionDescription: String
    var symbolName: String
}

struct WeatherAttributionInfo: Equatable {
    var serviceName: String
    var legalPageURL: URL
}

protocol WeatherProvider {
    /// Mock data does not need the user's location (avoids permission prompts in the Simulator and tests).
    var needsLocation: Bool { get }
    func currentWeather(for location: CLLocation) async throws -> WeatherReading
    func attribution() async -> WeatherAttributionInfo?
}

/// Unit conversion and clamping shared by all providers (and unit-tested).
enum WeatherMapper {
    static func reading(
        temperature: Measurement<UnitTemperature>,
        apparentTemperature: Measurement<UnitTemperature>,
        precipitationChance: Double,
        windSpeed: Measurement<UnitSpeed>,
        conditionDescription: String,
        symbolName: String
    ) -> WeatherReading {
        WeatherReading(
            temperatureC: round1(temperature.converted(to: .celsius).value),
            feelsLikeC: round1(apparentTemperature.converted(to: .celsius).value),
            precipitationChance: min(max(precipitationChance, 0), 1),
            windKph: round1(max(windSpeed.converted(to: .kilometersPerHour).value, 0)),
            conditionDescription: conditionDescription,
            symbolName: symbolName.isEmpty ? "cloud.sun" : symbolName
        )
    }

    static func snapshot(from reading: WeatherReading, locationName: String, at date: Date = Date()) -> WeatherSnapshot {
        WeatherSnapshot(
            temperatureC: reading.temperatureC,
            feelsLikeC: reading.feelsLikeC,
            precipitationChance: reading.precipitationChance,
            windKph: reading.windKph,
            conditionDescription: reading.conditionDescription,
            symbolName: reading.symbolName,
            locationName: locationName,
            fetchedAt: date
        )
    }

    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}

/// Deterministic weather for the Simulator, previews and tests.
final class MockWeatherProvider: WeatherProvider {
    var reading: WeatherReading

    init(reading: WeatherReading = WeatherReading(
        temperatureC: 14, feelsLikeC: 12, precipitationChance: 0.2, windKph: 12,
        conditionDescription: "Partly Cloudy", symbolName: "cloud.sun"
    )) {
        self.reading = reading
    }

    var needsLocation: Bool { false }
    func currentWeather(for location: CLLocation) async throws -> WeatherReading { reading }
    func attribution() async -> WeatherAttributionInfo? { nil }
}
