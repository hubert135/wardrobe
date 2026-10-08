import XCTest
@testable import OutfitEngine

final class GapAnalyzerTests: XCTestCase {
    let analyzer = GapAnalyzer()

    private var smartCasualContexts: [OutfitContext] {
        GapAnalyzer.standardContexts(preferences: StylePreferences(preferredStyles: [.smartCasual]), date: Fixtures.monday)
    }

    func testStandardContextsCoverEachStyleInEachSeason() {
        let contexts = GapAnalyzer.standardContexts(preferences: StylePreferences(preferredStyles: [.smartCasual, .casual]))
        XCTAssertEqual(contexts.count, 8)
        XCTAssertTrue(contexts.allSatisfy { $0.weather == nil && $0.ignoresRecentWear })
    }

    func testUnlockedCountMatchesHandCount() {
        // Two tops and one pair of shoes, no bottoms: beige chinos unlock exactly 2 x 1 = 2 outfits
        // (no outerwear in the closet, so only the "no outerwear" option exists).
        let closet = [
            Fixtures.garment(.shirt, "white", formality: 3),
            Fixtures.garment(.polo, "navy", formality: 3),
            Fixtures.garment(.shoes, "brown", formality: 3)
        ]
        let chinos = HypotheticalItem(category: .chinos, color: "beige", formality: 3)
        XCTAssertEqual(analyzer.unlockedCount(adding: chinos, to: closet, contexts: smartCasualContexts), 2)
    }

    func testSeasonalItemOnlyCountsInItsSeasons() {
        let closet = [
            Fixtures.garment(.shirt, "white", formality: 3),
            Fixtures.garment(.shoes, "brown", formality: 3)
        ]
        let summerOnly = HypotheticalItem(category: .chinos, color: "beige", formality: 3, seasons: [.summer])
        // Deduplicated across contexts: still the same single combination.
        XCTAssertEqual(analyzer.unlockedCount(adding: summerOnly, to: closet, contexts: smartCasualContexts), 1)
    }

    func testItemThatBreaksRulesUnlocksNothing() {
        // Formal oxford shoes (5) cannot pair with casual pieces (2) under the spread rule.
        let closet = [
            Fixtures.garment(.tShirt, "white", formality: 2),
            Fixtures.garment(.jeans, "denim", formality: 2)
        ]
        let oxfords = HypotheticalItem(category: .shoes, color: "black", cut: "oxford shoes", formality: 5)
        let contexts = GapAnalyzer.standardContexts(preferences: StylePreferences(preferredStyles: [.casual, .formal]))
        XCTAssertEqual(analyzer.unlockedCount(adding: oxfords, to: closet, contexts: contexts), 0)
    }

    func testRankSortsByImpactAndSkipsOwnedItems() {
        let closet = Fixtures.smartCasualCloset()
        let gaps = analyzer.rank(closet: closet, contexts: smartCasualContexts)
        XCTAssertFalse(gaps.isEmpty)
        XCTAssertEqual(gaps.map(\.unlockedOutfitCount), gaps.map(\.unlockedOutfitCount).sorted(by: >))
        XCTAssertTrue(gaps.allSatisfy { $0.unlockedOutfitCount > 0 })
        XCTAssertFalse(gaps.contains { $0.item.category == .chinos && $0.item.color == "beige" }, "Beige chinos are already owned")
        XCTAssertTrue(gaps.allSatisfy { $0.reason.hasPrefix("Works with") })
    }

    func testRankedCountsEqualDirectCounts() {
        let closet = Fixtures.smartCasualCloset()
        let contexts = smartCasualContexts
        for gap in analyzer.rank(closet: closet, contexts: contexts).prefix(5) {
            XCTAssertEqual(gap.unlockedOutfitCount, analyzer.unlockedCount(adding: gap.item, to: closet, contexts: contexts))
        }
    }

    func testReasonMentionsPartnerGarments() {
        let closet = [
            Fixtures.garment(.shirt, "white", formality: 3),
            Fixtures.garment(.polo, "navy", formality: 3),
            Fixtures.garment(.shoes, "brown", formality: 3)
        ]
        let chinos = HypotheticalItem(category: .chinos, color: "beige", formality: 3)
        let gap = analyzer.rank(closet: closet, catalog: [chinos], contexts: smartCasualContexts).first
        XCTAssertEqual(gap?.reason, "Works with 2 of your tops and 1 pair of shoes.")
    }
}

final class TaxonomyTests: XCTestCase {
    func testColorNormalization() {
        XCTAssertEqual(ColorPalette.normalize("Navy"), "navy")
        XCTAssertEqual(ColorPalette.normalize("dark blue"), "navy")
        XCTAssertEqual(ColorPalette.normalize("Gray"), "grey")
        XCTAssertEqual(ColorPalette.normalize("camel"), "tan")
        XCTAssertEqual(ColorPalette.normalize("Light Blue"), "light blue")
        XCTAssertEqual(ColorPalette.normalize("navy wool"), "navy")
        XCTAssertNil(ColorPalette.normalize(""))
        XCTAssertNil(ColorPalette.normalize("zzz"))
    }

    func testNeutrals() {
        XCTAssertTrue(ColorPalette.isNeutral("navy"))
        XCTAssertTrue(ColorPalette.isNeutral("beige"))
        XCTAssertFalse(ColorPalette.isNeutral("red"))
        XCTAssertFalse(ColorPalette.isNeutral("unknown-color"))
    }

    func testSeasonFromDate() {
        let calendar = Calendar(identifier: .gregorian)
        func date(_ month: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: 15))! }
        XCTAssertEqual(Season.from(date: date(1), calendar: calendar), .winter)
        XCTAssertEqual(Season.from(date: date(4), calendar: calendar), .spring)
        XCTAssertEqual(Season.from(date: date(7), calendar: calendar), .summer)
        XCTAssertEqual(Season.from(date: date(10), calendar: calendar), .autumn)
        XCTAssertEqual(Season.from(date: date(12), calendar: calendar), .winter)
    }

    func testDefaultOccasion() {
        let calendar = Calendar(identifier: .gregorian)
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!
        XCTAssertEqual(Occasion.defaultFor(date: monday, calendar: calendar), .work)
        XCTAssertEqual(Occasion.defaultFor(date: saturday, calendar: calendar), .weekend)
    }

    func testCategorySlots() {
        XCTAssertEqual(GarmentCategory.chinos.slot, .bottom)
        XCTAssertEqual(GarmentCategory.blazer.slot, .outerwear)
        XCTAssertEqual(GarmentCategory.tShirt.slot, .top)
        XCTAssertNil(GarmentCategory.other.slot)
        XCTAssertEqual(GarmentCategory(rawValue: "t-shirt"), .tShirt)
    }

    func testHypotheticalItemText() {
        let item = HypotheticalItem(category: .chinos, color: "Beige", cut: "slim", material: "cotton twill")
        XCTAssertEqual(item.title, "Beige chinos")
        XCTAssertEqual(item.searchQuery, "beige slim chinos cotton twill")
    }
}
