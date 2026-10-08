import OutfitEngine
import XCTest
@testable import Wardrobe

final class ResponseParsingTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func testAnalyzeResponseMapsAndNormalizes() throws {
        let json = """
        {"garments":[
          {"name":"Navy Oxford Shirt","category":"shirt","subcategory":"oxford shirt","primaryColor":"Dark Blue",
           "secondaryColor":null,"pattern":"solid","material":"cotton","formality":7,"seasons":["Spring","autumn","monsoon"],
           "brand":null,"confidence":1.4},
          {"name":"Grey tee","category":"tshirt","subcategory":"","primaryColor":"gray","secondaryColor":"white",
           "pattern":"STRIPED","material":null,"formality":2,"seasons":[],"brand":"Uniqlo","confidence":0.42}
        ]}
        """
        let response = try decoder.decode(AnalyzeGarmentResponse.self, from: Data(json.utf8))
        let drafts = response.garments.map(GarmentDraftMapper.draft(from:))

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].category, .shirt)
        XCTAssertEqual(drafts[0].primaryColor, "navy")
        XCTAssertEqual(drafts[0].formality, 5, "Formality is clamped to 1...5")
        XCTAssertEqual(drafts[0].seasons, [.spring, .autumn], "Unknown seasons are dropped")
        XCTAssertEqual(drafts[0].confidence, 1, "Confidence is clamped to 0...1")
        XCTAssertEqual(drafts[0].source, .photo)
        XCTAssertEqual(drafts[0].resolvedStatus, .confirmed)

        XCTAssertEqual(drafts[1].category, .tShirt)
        XCTAssertEqual(drafts[1].primaryColor, "grey")
        XCTAssertEqual(drafts[1].pattern, .striped)
        XCTAssertEqual(drafts[1].brand, "Uniqlo")
        XCTAssertEqual(drafts[1].resolvedStatus, .pendingReview, "Low confidence lands in Needs review")

        var edited = drafts[1]
        edited.wasEdited = true
        XCTAssertEqual(edited.resolvedStatus, .confirmed, "A card the user edited is confirmed")
    }

    func testUnknownCategoryFallsBackToNameInference() {
        let dto = AnalyzedGarmentDTO(
            name: "Brown suede chukka boots", category: "footwear", subcategory: "", primaryColor: "chestnut",
            secondaryColor: nil, pattern: "plain", material: "suede", formality: 3, seasons: [], brand: nil, confidence: 0.9
        )
        let draft = GarmentDraftMapper.draft(from: dto)
        XCTAssertEqual(draft.category, .shoes)
        XCTAssertEqual(draft.primaryColor, "brown")
        XCTAssertEqual(draft.pattern, .solid)
    }

    func testOrderItemsMapToPendingReviewDrafts() throws {
        let json = """
        {"items":[
          {"name":"Slim Fit Chinos","brand":"COS","category":"chinos","color":"Beige","size":"32/32","price":59.9,
           "currency":"EUR","purchaseDate":"2026-09-14","imageUrl":"https://img.example.com/chinos.jpg"},
          {"name":"Leather belt","brand":null,"category":"other","color":null,"size":null,"price":-5,
           "currency":null,"purchaseDate":"not a date","imageUrl":"javascript:alert(1)"}
        ]}
        """
        let response = try decoder.decode(ParseOrderResponse.self, from: Data(json.utf8))
        let drafts = response.items.map(GarmentDraftMapper.draft(from:))

        XCTAssertEqual(drafts[0].category, .chinos)
        XCTAssertEqual(drafts[0].primaryColor, "beige")
        XCTAssertEqual(drafts[0].price, 59.9)
        XCTAssertEqual(drafts[0].size, "32/32")
        XCTAssertNotNil(drafts[0].purchaseDate)
        XCTAssertEqual(drafts[0].remoteImageURL?.host, "img.example.com")
        XCTAssertEqual(drafts[0].resolvedStatus, .pendingReview)
        XCTAssertEqual(drafts[0].source, .order)

        XCTAssertEqual(drafts[1].category, .accessory, "Category inferred from the name")
        XCTAssertNil(drafts[1].price, "Negative prices are dropped")
        XCTAssertNil(drafts[1].purchaseDate)
        XCTAssertNil(drafts[1].remoteImageURL, "Only http(s) image URLs are accepted")
    }

    func testSessionResponseDecodesISODate() throws {
        let json = #"{"sessionToken":"abc","userId":"apple-123","expiresAt":"2026-11-06T10:00:00Z"}"#
        let session = try decoder.decode(SessionResponse.self, from: Data(json.utf8))
        XCTAssertEqual(session.userId, "apple-123")
    }

    // MARK: Rank validation

    private func garment(_ category: GarmentCategory, _ color: String) -> EngineGarment {
        EngineGarment(category: category, primaryColor: color, formality: 3)
    }

    func testRankValidatorDiscardsUnknownCandidatesAndForeignIDs() {
        let top = garment(.shirt, "white"), bottom = garment(.chinos, "beige"), shoes = garment(.shoes, "brown")
        let otherTop = garment(.polo, "navy")
        let a = OutfitCandidate(pieces: [.top: top, .bottom: bottom, .shoes: shoes])
        let b = OutfitCandidate(pieces: [.top: otherTop, .bottom: bottom, .shoes: shoes])
        let closetIDs = Set([top, bottom, shoes, otherTop].map(\.id))
        let foreign = UUID().uuidString

        let ranked = [
            RankedOutfitDTO(candidateId: "c9", garmentIds: [foreign], title: "Invented", reasoning: "Not ours."),
            RankedOutfitDTO(candidateId: "c2", garmentIds: b.garmentIDs.map(\.uuidString), title: "Polo day", reasoning: "Navy and beige work."),
            RankedOutfitDTO(candidateId: "c2", garmentIds: b.garmentIDs.map(\.uuidString), title: "Duplicate", reasoning: "Same again."),
            RankedOutfitDTO(candidateId: "c1", garmentIds: a.garmentIDs.map(\.uuidString) + [foreign], title: "Sneaky", reasoning: "Adds an id we don't own."),
            RankedOutfitDTO(candidateId: "x", garmentIds: Array(a.garmentIDs.map(\.uuidString).reversed()), title: "Matched by ids", reasoning: "White and beige.")
        ]

        let result = RankResponseValidator.validate(ranked, shortlist: [a, b], closetIDs: closetIDs, count: 3)
        XCTAssertEqual(result.map(\.dto.title), ["Polo day", "Matched by ids"])
        XCTAssertEqual(result.map(\.candidate.id), [b.id, a.id])
    }

    func testRankValidatorTrimsLongText() {
        let top = garment(.shirt, "white"), bottom = garment(.chinos, "beige"), shoes = garment(.shoes, "brown")
        let candidate = OutfitCandidate(pieces: [.top: top, .bottom: bottom, .shoes: shoes])
        let long = String(repeating: "word ", count: 100)
        let ranked = [RankedOutfitDTO(candidateId: "c1", garmentIds: candidate.garmentIDs.map(\.uuidString), title: long, reasoning: long + "\nsecond line")]
        let result = RankResponseValidator.validate(ranked, shortlist: [candidate], closetIDs: Set(candidate.garmentIDs), count: 3)
        XCTAssertLessThanOrEqual(result[0].dto.title.count, RankResponseValidator.maxTitleLength)
        XCTAssertLessThanOrEqual(result[0].dto.reasoning.count, RankResponseValidator.maxReasoningLength)
        XCTAssertFalse(result[0].dto.reasoning.contains("\n"))
    }

    func testRankRequestContainsOnlyAttributes() throws {
        let top = garment(.shirt, "white"), bottom = garment(.chinos, "beige"), shoes = garment(.shoes, "brown")
        let candidate = OutfitCandidate(pieces: [.top: top, .bottom: bottom, .shoes: shoes])
        let context = OutfitContext(occasion: .work, style: .smartCasual, season: .autumn, weather: WeatherContext(temperatureC: 9, precipitationChance: 0.6))
        let request = RankRequestBuilder.request(shortlist: [candidate], context: context, count: 3)
        XCTAssertEqual(request.garments.count, 3)
        XCTAssertEqual(request.candidates.first?.id, "c1")
        XCTAssertEqual(request.context.occasion, "work")
        XCTAssertEqual(request.context.weather?.precipitationChance, 0.6)
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        XCTAssertFalse(json.contains("image"), "No images are sent for ranking")
    }

    func testRankingCacheKeyBucketsWeather() {
        let top = garment(.shirt, "white"), bottom = garment(.chinos, "beige"), shoes = garment(.shoes, "brown")
        let candidate = OutfitCandidate(pieces: [.top: top, .bottom: bottom, .shoes: shoes])
        func key(_ temperature: Double, rain: Double) -> String {
            let context = OutfitContext(occasion: .work, style: .smartCasual, season: .autumn, weather: WeatherContext(temperatureC: temperature, precipitationChance: rain))
            return RankingCache.key(for: RankRequestBuilder.request(shortlist: [candidate], context: context, count: 3))
        }
        XCTAssertEqual(key(12.2, rain: 0.1), key(12.6, rain: 0.2))
        XCTAssertNotEqual(key(12.2, rain: 0.1), key(12.2, rain: 0.8))
        XCTAssertNotEqual(key(12, rain: 0.1), key(20, rain: 0.1))
    }
}
