import XCTest
@testable import OutfitEngine

final class OutfitEngineTests: XCTestCase {
    let engine = OutfitEngine()

    func testCandidatesAreAllValidAndUnique() {
        let closet = Fixtures.smartCasualCloset()
        let context = Fixtures.context()
        let candidates = engine.builder.build(closet: closet, context: context)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertEqual(Set(candidates.map(\.id)).count, candidates.count)
        for candidate in candidates {
            XCTAssertTrue(engine.rules.isValid(candidate, in: context))
            XCTAssertNil(candidate.pieces[.accessory], "Accessories are attached after enumeration")
        }
    }

    func testCandidateCountMatchesHandCount() {
        // 3 tops (f3) x 2 bottoms (f3, f4) x 2 shoes (f4, f3) x outerwear options (none, blazer f4, jacket f3).
        // Formality spread <= 1 holds for every combination (all values are 3 or 4), colors are neutral
        // except olive (one accent), so every combination is valid: 3 * 2 * 2 * 3 = 36.
        let candidates = engine.builder.build(closet: Fixtures.smartCasualCloset(), context: Fixtures.context())
        XCTAssertEqual(candidates.count, 36)
    }

    func testSuggestReturnsThreeDiverseOutfitsFromOwnedGarments() {
        let closet = Fixtures.smartCasualCloset()
        let ids = Set(closet.map(\.id))
        let outfits = engine.suggest(closet: closet, context: Fixtures.context(), count: 3)
        XCTAssertEqual(outfits.count, 3)
        for outfit in outfits {
            XCTAssertTrue(Set(outfit.garmentIDs).isSubset(of: ids))
            XCTAssertFalse(outfit.title.isEmpty)
            XCTAssertTrue(outfit.reasoning.hasSuffix("."))
        }
        // No two outfits are the same combination.
        XCTAssertEqual(Set(outfits.map(\.id)).count, 3)
    }

    func testSuggestIsDeterministic() {
        let closet = Fixtures.smartCasualCloset()
        let a = engine.suggest(closet: closet, context: Fixtures.context()).map(\.id)
        let b = engine.suggest(closet: closet, context: Fixtures.context()).map(\.id)
        XCTAssertEqual(a, b)
    }

    func testColdWeatherOutfitsAllHaveWeatherOuterwear() {
        var closet = Fixtures.smartCasualCloset()
        closet.append(Fixtures.garment(.coat, "navy", formality: 4))
        let cold = Fixtures.context(weather: WeatherContext(temperatureC: 4))
        let outfits = engine.suggest(closet: closet, context: cold, count: 3)
        XCTAssertFalse(outfits.isEmpty)
        for outfit in outfits {
            XCTAssertEqual(outfit.pieces[.outerwear]?.category.isWeatherOuterwear, true)
        }
    }

    func testRainyDaySkipsSuedeShoes() {
        var closet = Fixtures.smartCasualCloset().filter { $0.category != .shoes }
        let suede = Fixtures.garment(.shoes, "tan", formality: 3, material: "suede")
        let leather = Fixtures.garment(.shoes, "brown", formality: 3, material: "leather")
        closet += [suede, leather]
        let rainy = Fixtures.context(weather: WeatherContext(temperatureC: 14, precipitationChance: 0.9))
        let outfits = engine.suggest(closet: closet, context: rainy, count: 3)
        XCTAssertFalse(outfits.isEmpty)
        XCTAssertTrue(outfits.allSatisfy { $0.pieces[.shoes]?.id == leather.id })
    }

    func testRecentlyWornGarmentsAreAvoided() {
        var closet = Fixtures.smartCasualCloset()
        let worn = closet.firstIndex { $0.primaryColor == "white" && $0.category == .shirt }!
        closet[worn].lastWornAt = Fixtures.monday
        let outfits = engine.suggest(closet: closet, context: Fixtures.context(), count: 3)
        XCTAssertFalse(outfits.contains { $0.garmentIDs.contains(closet[worn].id) })
    }

    func testAccessoryIsAttachedWhenItFits() {
        let outfits = engine.suggest(closet: Fixtures.smartCasualCloset(), context: Fixtures.context(), count: 1)
        XCTAssertEqual(outfits.first?.pieces[.accessory]?.subcategory, "belt")
    }

    func testNotEnoughGarments() {
        let closet = Array(Fixtures.smartCasualCloset().prefix(7))
        XCTAssertFalse(engine.hasEnoughGarments(closet))
        XCTAssertTrue(engine.hasEnoughGarments(Fixtures.smartCasualCloset()))
    }

    func testAlternativesKeepOutfitValidAndExcludeCurrentPiece() {
        let closet = Fixtures.smartCasualCloset()
        let context = Fixtures.context()
        let outfit = engine.suggest(closet: closet, context: context, count: 1)[0]
        let currentTop = outfit.pieces[.top]!
        let alternatives = engine.alternatives(for: .top, in: outfit, closet: closet, context: context)
        XCTAssertFalse(alternatives.isEmpty)
        XCTAssertFalse(alternatives.contains { $0.id == currentTop.id })
        XCTAssertTrue(alternatives.allSatisfy { $0.slot == .top })

        let swapped = engine.swap(.top, in: outfit, closet: closet, context: context)
        XCTAssertNotNil(swapped)
        XCTAssertNotEqual(swapped?.pieces[.top]?.id, currentTop.id)
        XCTAssertEqual(swapped?.pieces[.bottom]?.id, outfit.pieces[.bottom]?.id)
    }

    func testSwapReturnsNilWhenNoAlternative() {
        let closet = Fixtures.smartCasualCloset().filter { $0.category != .chinos }
        let context = Fixtures.context()
        let outfit = engine.suggest(closet: closet, context: context, count: 1)[0]
        XCTAssertNil(engine.swap(.bottom, in: outfit, closet: closet, context: context))
    }

    // MARK: Builder

    func testBuilderRespectsAnchors() {
        let closet = Fixtures.smartCasualCloset()
        let chinos = closet.first { $0.category == .chinos }!
        let context = Fixtures.context(anchors: [chinos.id])
        let outfits = engine.build(closet: closet, context: context, includeMissing: false, count: 5)
        XCTAssertFalse(outfits.isEmpty)
        XCTAssertTrue(outfits.allSatisfy { $0.pieces[.bottom]?.id == chinos.id })
        XCTAssertTrue(outfits.allSatisfy { !$0.hasMissingPieces })
    }

    func testBuilderWithMissingItemsMarksHypotheticalPieces() {
        // Only a top and a bottom: every outfit needs shoes from the catalog.
        let closet = [Fixtures.garment(.shirt, "white", formality: 3), Fixtures.garment(.chinos, "beige", formality: 3)]
        let context = Fixtures.context(weather: nil)
        let withoutMissing = engine.build(closet: closet, context: context, includeMissing: false)
        XCTAssertTrue(withoutMissing.isEmpty)

        let outfits = engine.build(closet: closet, context: context, includeMissing: true)
        XCTAssertFalse(outfits.isEmpty)
        for outfit in outfits {
            XCTAssertEqual(outfit.missing.count, 1)
            XCTAssertNotNil(outfit.missing[.shoes])
            XCTAssertEqual(outfit.pieces[.shoes]?.isHypothetical, true)
        }
    }

    func testBuilderReturnsNothingWhenAnchorIsIneligible() {
        let shorts = Fixtures.garment(.shorts, "beige", formality: 2)
        let closet = Fixtures.smartCasualCloset() + [shorts]
        let cold = Fixtures.context(occasion: .weekend, style: .casual, weather: WeatherContext(temperatureC: 5), anchors: [shorts.id])
        XCTAssertTrue(engine.build(closet: closet, context: cold, includeMissing: false).isEmpty)
    }

    // MARK: Scoring

    func testAvoidedColorsArePenalized() {
        let closet = Fixtures.smartCasualCloset()
        var context = Fixtures.context()
        context.preferences = StylePreferences(avoidedColors: ["olive"])
        let outfits = engine.suggest(closet: closet, context: context, count: 3)
        XCTAssertFalse(outfits.contains { $0.candidate.garments.contains { $0.primaryColor == "olive" } })
    }

    func testSelectDiversePrefersLowOverlap() {
        let top = Fixtures.garment(.shirt, "white", formality: 3)
        let otherTop = Fixtures.garment(.shirt, "light blue", formality: 3)
        let bottom = Fixtures.garment(.chinos, "beige", formality: 3)
        let otherBottom = Fixtures.garment(.trousers, "grey", formality: 3)
        let shoes = Fixtures.garment(.shoes, "brown", formality: 3)
        let otherShoes = Fixtures.garment(.shoes, "white", formality: 3)

        let a = ScoredCandidate(candidate: OutfitCandidate(pieces: [.top: top, .bottom: bottom, .shoes: shoes]), score: 10)
        let nearDuplicate = ScoredCandidate(candidate: OutfitCandidate(pieces: [.top: otherTop, .bottom: bottom, .shoes: shoes]), score: 9.9)
        let different = ScoredCandidate(candidate: OutfitCandidate(pieces: [.top: otherTop, .bottom: otherBottom, .shoes: shoes]), score: 9.2)
        let fullyDifferent = ScoredCandidate(candidate: OutfitCandidate(pieces: [.top: otherTop, .bottom: otherBottom, .shoes: otherShoes]), score: 5)

        let picked = engine.scorer.selectDiverse([a, nearDuplicate, different, fullyDifferent], count: 2)
        XCTAssertEqual(picked.map(\.candidate.id), [a.candidate.id, different.candidate.id])

        // When nothing else is left, overlapping candidates are still returned.
        XCTAssertEqual(engine.scorer.selectDiverse([a, nearDuplicate], count: 2).count, 2)
    }
}
