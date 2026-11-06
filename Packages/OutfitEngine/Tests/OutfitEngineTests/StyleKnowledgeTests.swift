import XCTest
@testable import OutfitEngine

final class StyleKnowledgeTests: XCTestCase {
    let knowledge = StyleKnowledge.shared
    let rules = OutfitRules()

    func testKnowledgeLoads() {
        XCTAssertGreaterThan(knowledge.pairScores.count, 80)
        XCTAssertGreaterThanOrEqual(knowledge.principles.count, 10)
    }

    func testColorPairsAreSymmetric() {
        XCTAssertEqual(knowledge.colorScore("navy", "grey"), 2)
        XCTAssertEqual(knowledge.colorScore("grey", "navy"), 2)
        XCTAssertEqual(knowledge.colorScore("brown", "black"), -1)
        XCTAssertEqual(knowledge.colorScore("denim", "denim"), -1, "Double denim in one wash")
        XCTAssertEqual(knowledge.colorScore("navy", "navy"), 0)
    }

    func testHarmonyPrefersClassicPairs() {
        let classic = [Fixtures.garment(.sweater, "navy"), Fixtures.garment(.trousers, "grey"), Fixtures.garment(.shoes, "brown")]
        let clash = [Fixtures.garment(.sweater, "burgundy"), Fixtures.garment(.trousers, "red"), Fixtures.garment(.shoes, "black")]
        XCTAssertGreaterThan(knowledge.colorHarmony(classic), knowledge.colorHarmony(clash))
        XCTAssertTrue(knowledge.hasColorClash(clash))
        XCTAssertFalse(knowledge.hasColorClash(classic))
        let navySuitBlackShoes = [Fixtures.garment(.blazer, "navy"), Fixtures.garment(.trousers, "navy"), Fixtures.garment(.shoes, "black")]
        XCTAssertFalse(knowledge.hasColorClash(navySuitBlackShoes), "Black shoes with navy are classic")
    }

    func testSuitDetectionIgnoresTracksuits() {
        XCTAssertTrue(knowledge.isSuitPiece(Fixtures.garment(.blazer, "navy", material: "wool", subcategory: "suit jacket")))
        XCTAssertFalse(knowledge.isSuitPiece(Fixtures.garment(.trousers, "black", material: "polyester", subcategory: "tracksuit bottoms")))
        XCTAssertFalse(knowledge.isSuitPiece(Fixtures.garment(.blazer, "navy", material: "wool", subcategory: "blazer")))
    }

    func testHeavyTexturesDoNotStack() {
        let cable = Fixtures.garment(.sweater, "cream", material: "wool", subcategory: "cable knit sweater")
        let cords = Fixtures.garment(.trousers, "brown", material: "corduroy")
        let chinos = Fixtures.garment(.chinos, "beige", material: "cotton twill")
        XCTAssertTrue(knowledge.hasTextureClash(OutfitCandidate(pieces: [.top: cable, .bottom: cords])))
        XCTAssertFalse(knowledge.hasTextureClash(OutfitCandidate(pieces: [.top: cable, .bottom: chinos])))
    }

    func testFabricDecidesTheSeason() {
        let linen = Fixtures.garment(.shirt, "white", formality: 3, material: "linen")
        XCTAssertEqual(rules.exclusionReason(for: linen, in: Fixtures.context(season: .winter)), .season)
        XCTAssertNil(rules.exclusionReason(for: linen, in: Fixtures.context(season: .summer, weather: WeatherContext(temperatureC: 26))))
        let flannel = Fixtures.garment(.trousers, "grey", formality: 4, material: "wool flannel")
        XCTAssertEqual(rules.exclusionReason(for: flannel, in: Fixtures.context(season: .summer)), .season)
    }

    func testStyleExclusions() {
        let sneakers = Fixtures.garment(.shoes, "white", formality: 4, material: "leather", subcategory: "leather sneakers")
        XCTAssertTrue(knowledge.isExcluded(sneakers, from: .formal))
        XCTAssertFalse(knowledge.isExcluded(sneakers, from: .smartCasual))
        let sweater = Fixtures.garment(.sweater, "navy", formality: 3, material: "merino wool", subcategory: "merino sweater")
        XCTAssertFalse(knowledge.isExcluded(sweater, from: .smartCasual), "A sweater is not a sweatshirt")
        let joggers = Fixtures.garment(.trousers, "grey", formality: 3, material: "cotton jersey", subcategory: "joggers")
        XCTAssertTrue(knowledge.isExcluded(joggers, from: .smartCasual))
        XCTAssertEqual(rules.exclusionReason(for: joggers, in: Fixtures.context(occasion: .work, style: .smartCasual)), .formality)
        XCTAssertEqual(knowledge.effectiveFormality(for: joggers), 1, "The type corrects an implausible formality")
    }

    func testSuitJacketNeedsItsTrousers() {
        let jacket = Fixtures.garment(.blazer, "navy", formality: 5, material: "wool", subcategory: "suit jacket")
        let trousers = Fixtures.garment(.trousers, "navy", formality: 5, material: "wool", subcategory: "suit trousers")
        let greyTrousers = Fixtures.garment(.trousers, "charcoal", formality: 5, material: "wool", subcategory: "suit trousers")
        let chinos = Fixtures.garment(.chinos, "beige", formality: 3)
        let blazer = Fixtures.garment(.blazer, "navy", formality: 4, material: "wool", subcategory: "blazer")
        XCTAssertTrue(rules.hasConsistentSuit(OutfitCandidate(pieces: [.outerwear: jacket, .bottom: trousers])))
        XCTAssertFalse(rules.hasConsistentSuit(OutfitCandidate(pieces: [.outerwear: jacket, .bottom: chinos])))
        XCTAssertFalse(rules.hasConsistentSuit(OutfitCandidate(pieces: [.outerwear: jacket, .bottom: greyTrousers])))
        XCTAssertFalse(rules.hasConsistentSuit(OutfitCandidate(pieces: [.outerwear: blazer, .bottom: trousers])))
        XCTAssertTrue(rules.hasConsistentSuit(OutfitCandidate(pieces: [.bottom: trousers])), "Suit trousers with a knit are fine")
    }
}

final class RecipeLibraryTests: XCTestCase {
    private var capsule: [EngineGarment] {
        GenericCapsule.items.map { item in
            EngineGarment(
                category: item.category, subcategory: item.subcategory, primaryColor: item.color,
                secondaryColor: item.secondaryColor, pattern: item.pattern, material: item.material,
                formality: item.formality, seasons: Set(item.seasons)
            )
        }
    }

    func testLibraryAndCapsuleLoad() {
        XCTAssertGreaterThanOrEqual(RecipeLibrary.standard.count, 40)
        XCTAssertEqual(Set(RecipeLibrary.standard.map(\.id)).count, RecipeLibrary.standard.count)
        XCTAssertGreaterThanOrEqual(GenericCapsule.items.count, 60)
        XCTAssertEqual(Set(GenericCapsule.items.map(\.id)).count, GenericCapsule.items.count)
        for style in Style.allCases {
            XCTAssertTrue(RecipeLibrary.standard.contains { $0.styles.contains(style) }, "No recipe for \(style)")
        }
    }

    /// Every library recipe can be worn, closely, with the generic capsule.
    func testCapsuleWearsEveryRecipe() {
        let builder = RecipeOutfitBuilder()
        let closet = capsule
        for recipe in RecipeLibrary.standard {
            let context = OutfitContext(
                occasion: recipe.occasions.first, style: recipe.styles.first, season: recipe.seasons.sorted { $0.rawValue < $1.rawValue }.first ?? .autumn,
                weather: nil, date: Fixtures.monday, recipes: [recipe]
            )
            let best = builder.fills(for: recipe, closet: closet, context: context).first
            XCTAssertNotNil(best, "\(recipe.id) \(recipe.title) cannot be worn from the capsule")
            XCTAssertGreaterThanOrEqual(best?.quality ?? 0, 0.9, "\(recipe.id) is only a loose match")
        }
    }

    func testFormalSuggestionsAreSuits() {
        let context = OutfitContext(occasion: .businessMeeting, style: .formal, season: .autumn, weather: WeatherContext(temperatureC: 14),
                                    date: Fixtures.monday, recipes: RecipeLibrary.standard)
        let outfits = OutfitEngine().recipeSuggestions(closet: capsule, context: context, count: 3)
        XCTAssertEqual(outfits.count, 3)
        for outfit in outfits {
            XCTAssertNotEqual(outfit.pieces[.shoes]?.subcategory.contains("sneaker"), true)
            XCTAssertTrue(OutfitRules().hasConsistentSuit(outfit.candidate))
        }
    }

    func testSmartCasualNeverUsesSportswear() {
        let context = OutfitContext(occasion: .work, style: .smartCasual, season: .autumn, weather: WeatherContext(temperatureC: 14),
                                    date: Fixtures.monday, recipes: RecipeLibrary.standard)
        let outfits = OutfitEngine().recipeSuggestions(closet: capsule, context: context, count: 5)
        XCTAssertGreaterThanOrEqual(outfits.count, 3)
        let sporty = ["jogger", "hoodie", "running", "sweatshirt"]
        for outfit in outfits {
            for garment in outfit.candidate.garments {
                XCTAssertFalse(sporty.contains { garment.subcategory.contains($0) }, "\(garment.subcategory) in \(outfit.title)")
            }
        }
    }
}
