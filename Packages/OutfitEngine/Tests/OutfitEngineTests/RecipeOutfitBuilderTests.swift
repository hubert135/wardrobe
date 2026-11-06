import XCTest
@testable import OutfitEngine

final class RecipeOutfitBuilderTests: XCTestCase {
    let builder = RecipeOutfitBuilder()

    // Invented recipes (no style-guide content in the repository).
    let smart = StyleRecipe(
        id: "T1", title: "NAVY KNIT + GREY TROUSERS + BROWN SHOES", summary: "Navy knit, grey trousers, brown shoes.",
        occasions: [.work], styles: [.smartCasual], seasons: [.autumn, .winter],
        pieces: [
            RecipePiece(slot: .top, categories: [.sweater], colors: ["navy"]),
            RecipePiece(slot: .bottom, categories: [.trousers, .chinos], colors: ["grey"]),
            RecipePiece(slot: .shoes, categories: [.shoes], colors: ["brown"])
        ]
    )
    let formal = StyleRecipe(
        id: "T2", title: "NAVY BLAZER + WHITE SHIRT + GREY TROUSERS + BLACK SHOES", summary: "Navy blazer, white shirt.",
        occasions: [.businessMeeting], styles: [.formal], seasons: [],
        pieces: [
            RecipePiece(slot: .outerwear, categories: [.blazer], colors: ["navy"]),
            RecipePiece(slot: .top, categories: [.shirt], colors: ["white"]),
            RecipePiece(slot: .bottom, categories: [.trousers], colors: ["grey"]),
            RecipePiece(slot: .shoes, categories: [.shoes], colors: ["black"])
        ]
    )
    let weekend = StyleRecipe(
        id: "T3", title: "CREAM KNIT + JEANS + BROWN SHOES", summary: "Cream knit and jeans.",
        occasions: [.weekend], styles: [.smartCasual, .casual], seasons: [],
        pieces: [
            RecipePiece(slot: .top, categories: [.sweater], colors: ["cream"]),
            RecipePiece(slot: .bottom, categories: [.jeans], colors: ["denim"]),
            RecipePiece(slot: .shoes, categories: [.shoes], colors: ["brown"])
        ]
    )

    let navyKnit = Fixtures.garment(.sweater, "navy", formality: 3)
    let creamKnit = Fixtures.garment(.sweater, "cream", formality: 3)
    let greyTrousers = Fixtures.garment(.trousers, "grey", formality: 4)
    let greyJoggers = Fixtures.garment(.trousers, "grey", formality: 1, material: "jersey", subcategory: "joggers")
    let jeans = Fixtures.garment(.jeans, "denim", formality: 3)
    let brownShoes = Fixtures.garment(.shoes, "brown", formality: 3, material: "leather")
    let blackShoes = Fixtures.garment(.shoes, "black", formality: 5, material: "leather")
    let blazer = Fixtures.garment(.blazer, "navy", formality: 5)
    let whiteShirt = Fixtures.garment(.shirt, "white", formality: 4)
    let coat = Fixtures.garment(.coat, "charcoal", formality: 4)

    private var closet: [EngineGarment] { [navyKnit, creamKnit, greyTrousers, greyJoggers, jeans, brownShoes, blackShoes, blazer, whiteShirt, coat] }

    private func context(_ occasion: Occasion, _ style: Style, weather: WeatherContext? = WeatherContext(temperatureC: 15), anchors: Set<UUID> = []) -> OutfitContext {
        OutfitContext(occasion: occasion, style: style, season: .autumn, weather: weather, date: Fixtures.monday,
                      anchorGarmentIDs: anchors, recipes: [smart, formal, weekend])
    }

    func testStyleIsStrict() {
        XCTAssertTrue(builder.applies(formal, to: context(.businessMeeting, .formal)))
        XCTAssertFalse(builder.applies(formal, to: context(.work, .smartCasual)), "A formal-only recipe never appears for smart casual")
        XCTAssertFalse(builder.applies(smart, to: context(.work, .formal)))
    }

    func testFillUsesMatchingGarmentsAndSkipsSportswear() {
        let best = builder.fills(for: smart, closet: closet, context: context(.work, .smartCasual)).first
        XCTAssertEqual(best?.candidate.pieces[.top]?.id, navyKnit.id)
        XCTAssertEqual(best?.candidate.pieces[.bottom]?.id, greyTrousers.id, "Grey joggers are sporty, never smart casual")
        XCTAssertEqual(best?.candidate.pieces[.shoes]?.id, brownShoes.id)
        XCTAssertEqual(best?.quality ?? 0, 1.0, accuracy: 0.001)
    }

    func testFormalOutfitsComeFromFormalRecipes() {
        let outfits = OutfitEngine().recipeSuggestions(closet: closet, context: context(.businessMeeting, .formal), count: 3)
        XCTAssertEqual(outfits.map { $0.recipe?.id }, ["T2"])
        XCTAssertEqual(Set(outfits[0].ownedGarmentIDs).isSuperset(of: [blazer.id, whiteShirt.id, greyTrousers.id, blackShoes.id]), true)
        XCTAssertEqual(outfits[0].title, "Navy blazer + white shirt + grey trousers + black shoes")
        XCTAssertTrue(outfits[0].reasoning.hasPrefix("Navy blazer, white shirt."))
    }

    func testOccasionRanksAndRotationBringsOtherRecipes() {
        let first = builder.suggestions(closet: closet, context: context(.work, .smartCasual), count: 1)
        XCTAssertEqual(first.first?.recipe.id, "T1", "Fits work and is a perfect match; T3 is for weekends")
        let next = builder.suggestions(closet: closet, context: context(.work, .smartCasual), count: 1, recentlyShown: ["T1"])
        XCTAssertEqual(next.first?.recipe.id, "T3", "Just shown recipes move down")
    }

    func testColdWeatherAddsOuterwear() {
        let cold = context(.work, .smartCasual, weather: WeatherContext(temperatureC: 4))
        let best = builder.fills(for: smart, closet: closet, context: cold).first
        XCTAssertEqual(best?.candidate.pieces[.outerwear]?.id, coat.id)
    }

    func testAnchorsMustBeUsed() {
        let anchored = context(.work, .smartCasual, anchors: [jeans.id])
        let outfits = builder.suggestions(closet: closet, context: anchored, count: 3)
        XCTAssertEqual(outfits.map(\.recipe.id), ["T3"], "Only the recipe that can wear the chosen jeans")
    }

    func testMissingPieceForBuilder() {
        let noShoes = closet.filter { $0.category != .shoes }
        XCTAssertTrue(builder.fills(for: smart, closet: noShoes, context: context(.work, .smartCasual)).isEmpty)
        let withMissing = builder.fills(for: smart, closet: noShoes, context: context(.work, .smartCasual), allowMissing: true).first
        XCTAssertEqual(withMissing?.missing[.shoes]?.category, .shoes)
        XCTAssertEqual(withMissing?.missing[.shoes]?.color, "brown")
    }

    func testGenericOutfitsTopUpWhenFewRecipesFit() {
        let outfits = OutfitEngine().suggestWithRecipes(closet: closet, context: context(.businessMeeting, .formal), count: 3)
        XCTAssertEqual(outfits.first?.recipe?.id, "T2")
        XCTAssertGreaterThanOrEqual(outfits.count, 1)
    }
}
