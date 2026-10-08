import CoreLocation
import OutfitEngine
import XCTest
@testable import Wardrobe

final class WeatherMappingTests: XCTestCase {
    func testConvertsUnitsToMetric() {
        let reading = WeatherMapper.reading(
            temperature: Measurement(value: 50, unit: .fahrenheit),
            apparentTemperature: Measurement(value: 41, unit: .fahrenheit),
            precipitationChance: 0.35,
            windSpeed: Measurement(value: 5, unit: .metersPerSecond),
            conditionDescription: "Cloudy",
            symbolName: "cloud"
        )
        XCTAssertEqual(reading.temperatureC, 10, accuracy: 0.05)
        XCTAssertEqual(reading.feelsLikeC, 5, accuracy: 0.05)
        XCTAssertEqual(reading.windKph, 18, accuracy: 0.05)
        XCTAssertEqual(reading.precipitationChance, 0.35)
    }

    func testClampsOutOfRangeValues() {
        let reading = WeatherMapper.reading(
            temperature: Measurement(value: 20, unit: .celsius),
            apparentTemperature: Measurement(value: 20, unit: .celsius),
            precipitationChance: 1.7,
            windSpeed: Measurement(value: -3, unit: .kilometersPerHour),
            conditionDescription: "Clear",
            symbolName: ""
        )
        XCTAssertEqual(reading.precipitationChance, 1)
        XCTAssertEqual(reading.windKph, 0)
        XCTAssertEqual(reading.symbolName, "cloud.sun", "Empty symbol falls back to a default")
    }

    func testSnapshotDrivesEngineWeather() {
        let reading = WeatherReading(temperatureC: 8, feelsLikeC: 5, precipitationChance: 0.7, windKph: 20, conditionDescription: "Rain", symbolName: "cloud.rain")
        let snapshot = WeatherMapper.snapshot(from: reading, locationName: "Warsaw")
        let engine = snapshot.engineWeather
        XCTAssertEqual(engine.feelsLikeC, 5)
        XCTAssertTrue(OutfitRules().isRainy(engine))
        XCTAssertTrue(OutfitRules().requiresOuterwear(OutfitContext(weather: engine)))
    }

    func testMockProviderNeedsNoLocation() async throws {
        let provider = MockWeatherProvider()
        XCTAssertFalse(provider.needsLocation)
        let reading = try await provider.currentWeather(for: CLLocation(latitude: 0, longitude: 0))
        XCTAssertEqual(reading.temperatureC, 14)
    }
}

final class ShopTests: XCTestCase {
    func testSearchLinksAreDeterministicSearchURLs() {
        let provider = SearchLinkProvider(regionCode: "PL")
        let links = provider.links(for: "beige slim chinos", maxPrice: 199.6)
        XCTAssertEqual(links.map(\.retailer), ["Zalando", "Google Shopping", "Allegro"])
        XCTAssertEqual(links[0].url.absoluteString, "https://www.zalando.pl/katalog/?q=beige%20slim%20chinos")
        XCTAssertEqual(links[1].url.absoluteString, "https://www.google.com/search?tbm=shop&q=beige%20slim%20chinos")
        XCTAssertEqual(links[2].url.absoluteString, "https://allegro.pl/listing?string=beige%20slim%20chinos&price_to=200")
        XCTAssertEqual(provider.links(for: "beige slim chinos", maxPrice: 199.6), links)
    }

    func testRegionChangesZalandoDomain() {
        XCTAssertEqual(SearchLinkProvider(regionCode: "DE").links(for: "chinos", maxPrice: nil)[0].url.host, "www.zalando.de")
        XCTAssertEqual(SearchLinkProvider(regionCode: "GB").links(for: "chinos", maxPrice: nil)[0].url.host, "www.zalando.co.uk")
    }

    func testEmptyQueryProducesNoLinks() {
        XCTAssertTrue(SearchLinkProvider().links(for: "  ", maxPrice: nil).isEmpty)
    }

    func testPurchaseDirectionsHaveThreeTiersAndRespectBudget() {
        let item = HypotheticalItem(category: .chinos, color: "beige", cut: "slim", material: "cotton twill")
        let directions = PurchaseDirectionCatalog.directions(for: item, currencyCode: "EUR")
        XCTAssertEqual(directions.map(\.tier), [.budget, .mid, .premium])
        XCTAssertTrue(directions.allSatisfy { $0.attributes.lowercased().contains("beige") })
        XCTAssertEqual(PurchaseDirectionCatalog.filter(directions, budget: 50).map(\.tier), [.budget, .mid])
        XCTAssertEqual(PurchaseDirectionCatalog.filter(directions, budget: nil).count, 3)

        let pln = PurchaseDirectionCatalog.directions(for: item, currencyCode: "PLN")
        XCTAssertGreaterThan(pln[0].priceRange.upperBound, directions[0].priceRange.upperBound)
    }

    func testBrandIsAddedToQuery() {
        let item = HypotheticalItem(category: .shoes, color: "brown", cut: "derby shoes")
        let directions = PurchaseDirectionCatalog.directions(for: item, currencyCode: "EUR", brand: "Loake")
        XCTAssertTrue(directions[0].query.hasPrefix("Loake "))
    }
}

final class InferenceTests: XCTestCase {
    func testCategoryFromName() {
        XCTAssertEqual(ManualEntryInference.category(in: "Beige chinos"), .chinos)
        XCTAssertEqual(ManualEntryInference.category(in: "White T-shirt"), .tShirt)
        XCTAssertEqual(ManualEntryInference.category(in: "Grey sweatshirt"), .hoodie)
        XCTAssertEqual(ManualEntryInference.category(in: "Navy sport coat"), .blazer)
        XCTAssertEqual(ManualEntryInference.category(in: "Brown oxfords"), .shoes)
        XCTAssertEqual(ManualEntryInference.category(in: "Light blue oxford shirt"), .shirt)
        XCTAssertNil(ManualEntryInference.category(in: "Steel grey thing"), "\"tee\" must not match \"steel\"")
    }

    func testApplyFillsColorAndFormality() {
        var draft = GarmentDraft()
        draft.name = "Charcoal wool trousers"
        ManualEntryInference.apply(to: &draft)
        XCTAssertEqual(draft.category, .trousers)
        XCTAssertEqual(draft.primaryColor, "charcoal")
        XCTAssertEqual(draft.formality, GarmentCategory.trousers.defaultFormality)
    }

    func testDuplicateKeyIgnoresCaseAndWhitespace() {
        XCTAssertEqual(
            DuplicateDetector.key(category: .chinos, color: "Beige", brand: " COS "),
            DuplicateDetector.key(category: .chinos, color: "beige", brand: "cos")
        )
        XCTAssertNotEqual(
            DuplicateDetector.key(category: .chinos, color: "beige", brand: "COS"),
            DuplicateDetector.key(category: .chinos, color: "navy", brand: "COS")
        )
    }
}
