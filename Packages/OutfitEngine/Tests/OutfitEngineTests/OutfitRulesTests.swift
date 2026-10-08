import XCTest
@testable import OutfitEngine

final class OutfitRulesTests: XCTestCase {
    let rules = OutfitRules()

    func testArchivedGarmentIsExcluded() {
        let shirt = Fixtures.garment(.shirt, "white", formality: 3, archived: true)
        XCTAssertEqual(rules.exclusionReason(for: shirt, in: Fixtures.context()), .archived)
    }

    func testOtherCategoryHasNoSlot() {
        let item = Fixtures.garment(.other, "black")
        XCTAssertEqual(rules.exclusionReason(for: item, in: Fixtures.context()), .noSlot)
    }

    func testSeasonMismatchIsExcluded() {
        let summerShirt = Fixtures.garment(.shirt, "white", formality: 3, seasons: [.summer])
        XCTAssertEqual(rules.exclusionReason(for: summerShirt, in: Fixtures.context(season: .winter)), .season)
        XCTAssertNil(rules.exclusionReason(for: summerShirt, in: Fixtures.context(season: .summer, weather: nil)))
    }

    func testEmptySeasonsMeansAllSeasons() {
        let shirt = Fixtures.garment(.shirt, "white", formality: 3)
        for season in Season.allCases {
            XCTAssertNil(rules.exclusionReason(for: shirt, in: Fixtures.context(season: season, weather: nil)))
        }
    }

    func testFormalityOutsideOccasionRangeIsExcluded() {
        let hoodie = Fixtures.garment(.hoodie, "grey", formality: 1)
        XCTAssertEqual(rules.exclusionReason(for: hoodie, in: Fixtures.context(occasion: .businessMeeting, style: .formal)), .formality)
    }

    func testFormalityRangeIntersectsOccasionAndStyle() {
        XCTAssertEqual(Fixtures.context(occasion: .work, style: .smartCasual).formalityRange, 3...4)
        XCTAssertEqual(Fixtures.context(occasion: .weekend, style: .casual).formalityRange, 2...3)
        // No overlap: style wins.
        XCTAssertEqual(Fixtures.context(occasion: .businessMeeting, style: .sporty).formalityRange, 1...2)
        XCTAssertEqual(Fixtures.context(occasion: nil, style: nil).formalityRange, 1...5)
    }

    func testRecentlyWornGarmentIsExcluded() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Fixtures.monday)!
        let shirt = Fixtures.garment(.shirt, "white", formality: 3, lastWornAt: yesterday)
        XCTAssertEqual(rules.exclusionReason(for: shirt, in: Fixtures.context()), .recentlyWorn)
    }

    func testGarmentWornThreeDaysAgoIsAllowed() {
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Fixtures.monday)!
        let shirt = Fixtures.garment(.shirt, "white", formality: 3, lastWornAt: threeDaysAgo)
        XCTAssertNil(rules.exclusionReason(for: shirt, in: Fixtures.context()))
    }

    func testAnchorIgnoresRecentWear() {
        let shirt = Fixtures.garment(.shirt, "white", formality: 3, lastWornAt: Fixtures.monday)
        XCTAssertNil(rules.exclusionReason(for: shirt, in: Fixtures.context(anchors: [shirt.id])))
    }

    func testRecentWearWindowIsConfigurable() {
        var config = EngineConfig()
        config.recentWearExclusionDays = 0
        let shirt = Fixtures.garment(.shirt, "white", formality: 3, lastWornAt: Fixtures.monday)
        XCTAssertNil(OutfitRules(config: config).exclusionReason(for: shirt, in: Fixtures.context()))
    }

    // MARK: Weather

    func testCoatTooWarmAndShortsTooCold() {
        let coat = Fixtures.garment(.coat, "navy", formality: 4)
        let shorts = Fixtures.garment(.shorts, "beige", formality: 2)
        let warm = Fixtures.context(occasion: nil, style: nil, season: nil, weather: WeatherContext(temperatureC: 25))
        let cold = Fixtures.context(occasion: nil, style: nil, season: nil, weather: WeatherContext(temperatureC: 5))
        XCTAssertEqual(rules.exclusionReason(for: coat, in: warm), .tooWarm)
        XCTAssertNil(rules.exclusionReason(for: coat, in: cold))
        XCTAssertEqual(rules.exclusionReason(for: shorts, in: cold), .tooCold)
        XCTAssertNil(rules.exclusionReason(for: shorts, in: warm))
    }

    func testFeelsLikeTemperatureDrivesRules() {
        let coat = Fixtures.garment(.coat, "navy", formality: 4)
        let windy = Fixtures.context(occasion: nil, style: nil, season: nil, weather: WeatherContext(temperatureC: 18, feelsLikeC: 12))
        XCTAssertNil(rules.exclusionReason(for: coat, in: windy))
    }

    func testShortsNotAllowedAtWork() {
        let shorts = Fixtures.garment(.shorts, "beige", formality: 3)
        XCTAssertEqual(rules.exclusionReason(for: shorts, in: Fixtures.context(occasion: .work, style: nil, weather: WeatherContext(temperatureC: 28))), .formality)
    }

    func testRainExcludesSuedeShoes() {
        let suede = Fixtures.garment(.shoes, "tan", formality: 3, material: "suede", subcategory: "chukka boots")
        let leather = Fixtures.garment(.shoes, "brown", formality: 3, material: "leather")
        let rainy = Fixtures.context(weather: WeatherContext(temperatureC: 14, precipitationChance: 0.8))
        let dry = Fixtures.context(weather: WeatherContext(temperatureC: 14, precipitationChance: 0.1))
        XCTAssertEqual(rules.exclusionReason(for: suede, in: rainy), .rain)
        XCTAssertNil(rules.exclusionReason(for: leather, in: rainy))
        XCTAssertNil(rules.exclusionReason(for: suede, in: dry))
    }

    func testOuterwearRequiredBelowTenDegrees() {
        let top = Fixtures.garment(.shirt, "white", formality: 3)
        let bottom = Fixtures.garment(.chinos, "beige", formality: 3)
        let shoes = Fixtures.garment(.shoes, "brown", formality: 3)
        let blazer = Fixtures.garment(.blazer, "navy", formality: 4)
        let coat = Fixtures.garment(.coat, "navy", formality: 4)
        let cold = Fixtures.context(weather: WeatherContext(temperatureC: 6))

        XCTAssertFalse(rules.isValid(OutfitCandidate(pieces: [.top: top, .bottom: bottom, .shoes: shoes]), in: cold))
        XCTAssertFalse(rules.isValid(OutfitCandidate(pieces: [.top: top, .bottom: bottom, .shoes: shoes, .outerwear: blazer]), in: cold), "A blazer is not enough below 10°C")
        XCTAssertTrue(rules.isValid(OutfitCandidate(pieces: [.top: top, .bottom: bottom, .shoes: shoes, .outerwear: coat]), in: cold))
    }

    // MARK: Outfit level

    func testRequiredSlotsMustBeFilled() {
        let top = Fixtures.garment(.shirt, "white", formality: 3)
        let bottom = Fixtures.garment(.chinos, "beige", formality: 3)
        XCTAssertFalse(rules.isValid(OutfitCandidate(pieces: [.top: top, .bottom: bottom]), in: Fixtures.context()))
    }

    func testFormalitySpreadOfAtMostOne() {
        let a = Fixtures.garment(.shirt, "white", formality: 3)
        let b = Fixtures.garment(.trousers, "grey", formality: 4)
        let c = Fixtures.garment(.shoes, "black", formality: 5)
        XCTAssertTrue(rules.hasAcceptableFormalitySpread([a, b]))
        XCTAssertFalse(rules.hasAcceptableFormalitySpread([a, b, c]))
    }

    func testPatternCombinations() {
        let striped = Fixtures.garment(.shirt, "white", pattern: .striped)
        let checked = Fixtures.garment(.jacket, "grey", pattern: .checked)
        let patterned = Fixtures.garment(.chinos, "beige", pattern: .patterned)
        let checked2 = Fixtures.garment(.chinos, "grey", pattern: .checked)
        let solid = Fixtures.garment(.shoes, "brown")

        XCTAssertTrue(rules.hasCompatiblePatterns([striped, solid]))
        XCTAssertTrue(rules.hasCompatiblePatterns([striped, checked, solid]), "Subtle stripes may pair with one other pattern")
        XCTAssertFalse(rules.hasCompatiblePatterns([checked, patterned]), "Two loud patterns clash")
        XCTAssertFalse(rules.hasCompatiblePatterns([checked, checked2]), "Same pattern twice clashes")
        XCTAssertFalse(rules.hasCompatiblePatterns([striped, checked, patterned]))
    }

    func testAtMostTwoAccentColors() {
        let neutralBase = [Fixtures.garment(.chinos, "beige"), Fixtures.garment(.shoes, "brown")]
        let red = Fixtures.garment(.shirt, "red")
        let green = Fixtures.garment(.jacket, "green")
        let yellow = Fixtures.garment(.accessory, "yellow")
        XCTAssertTrue(rules.hasHarmoniousColors(neutralBase + [red, green]))
        XCTAssertFalse(rules.hasHarmoniousColors(neutralBase + [red, green, yellow]))
    }

    func testShortsNeverUnderBlazer() {
        let top = Fixtures.garment(.polo, "navy", formality: 2)
        let shorts = Fixtures.garment(.shorts, "beige", formality: 2)
        let shoes = Fixtures.garment(.shoes, "white", formality: 2)
        let blazer = Fixtures.garment(.blazer, "navy", formality: 3)
        let summer = Fixtures.context(occasion: .weekend, style: .casual, season: .summer, weather: WeatherContext(temperatureC: 26))
        XCTAssertTrue(rules.isValid(OutfitCandidate(pieces: [.top: top, .bottom: shorts, .shoes: shoes]), in: summer))
        XCTAssertFalse(rules.isValid(OutfitCandidate(pieces: [.top: top, .bottom: shorts, .shoes: shoes, .outerwear: blazer]), in: summer))
    }
}
