import XCTest
@testable import OutfitEngine

final class StyleRecipeTests: XCTestCase {
    let matcher = RecipeMatcher()

    /// Invented sample recipe: navy knit, beige chinos, brown boots, optional coat.
    let recipe = StyleRecipe(
        id: "S1",
        title: "Navy knit + beige chinos + brown boots",
        occasions: [.casualOuting, .weekend],
        styles: [.smartCasual],
        seasons: [.autumn, .winter],
        pieces: [
            RecipePiece(slot: .top, categories: [.sweater], colors: ["navy"], materials: ["wool"]),
            RecipePiece(slot: .bottom, categories: [.chinos, .trousers], colors: ["beige"]),
            RecipePiece(slot: .shoes, categories: [.shoes], colors: ["brown"], materials: ["boot"]),
            RecipePiece(slot: .outerwear, categories: [.coat], colors: ["camel"], optional: true)
        ]
    )

    // Stored, so each test sees the same garments (and ids) every time it refers to them.
    let sweater = Fixtures.garment(.sweater, "navy", formality: 3, material: "merino wool")
    let chinos = Fixtures.garment(.chinos, "beige", formality: 3)
    let boots = Fixtures.garment(.shoes, "brown", formality: 3, material: "leather", subcategory: "chelsea boots")

    func testPieceScoring() {
        let piece = recipe.pieces[0]
        XCTAssertEqual(matcher.score(piece, garment: sweater) ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(matcher.score(piece, garment: Fixtures.garment(.sweater, "grey", formality: 3)) ?? 0, 0.6, accuracy: 0.001, "Right type, wrong color, no material match")
        XCTAssertNil(matcher.score(piece, garment: Fixtures.garment(.shirt, "navy", formality: 3)), "Wrong category never matches")
        XCTAssertEqual(recipe.pieces[3].colors, ["tan"], "Recipe colors are normalized to the palette")
    }

    func testPatternRequirement() {
        let striped = RecipePiece(slot: .top, categories: [.sweater], patterns: [.striped])
        XCTAssertNil(matcher.score(striped, garment: Fixtures.garment(.sweater, "cream", pattern: .solid)))
        XCTAssertNotNil(matcher.score(striped, garment: Fixtures.garment(.sweater, "cream", pattern: .striped)))
    }

    func testOutfitMatchIgnoresOptionalPieces() {
        let candidate = OutfitCandidate(pieces: [.top: sweater, .bottom: chinos, .shoes: boots])
        let match = matcher.match(candidate, recipe: recipe)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.quality ?? 0, 1.0, accuracy: 0.001)
    }

    func testMissingRequiredPieceMeansNoMatch() {
        let jeans = Fixtures.garment(.jeans, "denim", formality: 3)
        XCTAssertNil(matcher.match(OutfitCandidate(pieces: [.top: sweater, .bottom: jeans, .shoes: boots]), recipe: recipe))
    }

    func testRecipeAppliesBySeasonAndOccasionOrStyle() {
        XCTAssertTrue(matcher.applies(recipe, to: OutfitContext(occasion: .weekend, style: .casual, season: .autumn)))
        XCTAssertTrue(matcher.applies(recipe, to: OutfitContext(occasion: .work, style: .smartCasual, season: .winter)), "Style alone is enough")
        XCTAssertFalse(matcher.applies(recipe, to: OutfitContext(occasion: .work, style: .formal, season: .autumn)))
        XCTAssertFalse(matcher.applies(recipe, to: OutfitContext(occasion: .weekend, style: .smartCasual, season: .summer)), "Autumn/winter recipe")
    }

    func testEngineLabelsAndPrefersRecipeOutfits() {
        let shirt = Fixtures.garment(.shirt, "white", formality: 3)
        let jeans = Fixtures.garment(.jeans, "denim", formality: 3)
        let sneakers = Fixtures.garment(.shoes, "white", formality: 3, material: "leather", subcategory: "sneakers")
        let closet = [sweater, chinos, boots, shirt, jeans, sneakers]
        let context = OutfitContext(occasion: .casualOuting, style: .smartCasual, season: .autumn, date: Fixtures.monday, recipes: [recipe])

        let best = OutfitEngine().suggest(closet: closet, context: context, count: 1).first
        XCTAssertEqual(best?.recipe?.id, "S1")
        XCTAssertEqual(Set(best?.ownedGarmentIDs ?? []), Set([sweater.id, chinos.id, boots.id]))
        XCTAssertTrue(best?.reasoning.hasPrefix("Follows recipe S1 from your style guide.") ?? false)

        let withoutRecipes = OutfitEngine().suggest(closet: closet, context: OutfitContext(occasion: .casualOuting, style: .smartCasual, season: .autumn, date: Fixtures.monday), count: 3)
        XCTAssertTrue(withoutRecipes.allSatisfy { $0.recipe == nil })
    }

    func testOwnedPiecesFindsBestGarmentPerRequiredPiece() {
        let greySweater = Fixtures.garment(.sweater, "grey", formality: 3)
        let owned = matcher.ownedPieces(of: recipe, in: [greySweater, sweater, chinos])
        XCTAssertEqual(owned[0]?.id, sweater.id, "The navy sweater, not the grey one")
        XCTAssertEqual(owned[1]?.id, chinos.id)
        XCTAssertNil(owned[2], "No brown boots owned")
        XCTAssertNil(owned[3], "Optional pieces are not tracked")
    }
}
