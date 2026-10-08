import Foundation

// Wire formats for the Wardrobe backend. Mirrors `backend/src/schemas/*.ts`.

struct ImagePayload: Codable, Equatable {
    var mediaType: String
    /// Base64-encoded bytes.
    var data: String
}

// MARK: Auth

struct SessionRequest: Codable {
    var identityToken: String
}

struct SessionResponse: Codable {
    var sessionToken: String
    var userId: String
    var expiresAt: Date
}

// MARK: Garment analysis

struct AnalyzeGarmentRequest: Codable {
    var image: ImagePayload
}

struct AnalyzedGarmentDTO: Codable, Equatable {
    var name: String
    var category: String
    var subcategory: String
    var primaryColor: String
    var secondaryColor: String?
    var pattern: String
    var material: String?
    var formality: Int
    var seasons: [String]
    var brand: String?
    var confidence: Double
}

struct AnalyzeGarmentResponse: Codable {
    var garments: [AnalyzedGarmentDTO]
}

// MARK: Order parsing

struct ParseOrderRequest: Codable {
    var text: String?
    var image: ImagePayload?
}

struct ParsedOrderItemDTO: Codable, Equatable {
    var name: String
    var brand: String?
    var category: String
    var color: String?
    var size: String?
    var price: Double?
    var currency: String?
    /// ISO date "YYYY-MM-DD".
    var purchaseDate: String?
    var imageUrl: String?
}

struct ParseOrderResponse: Codable {
    var items: [ParsedOrderItemDTO]
}

// MARK: Outfit ranking

struct RankWeatherDTO: Codable, Equatable, Hashable {
    var temperatureC: Double
    var feelsLikeC: Double
    var precipitationChance: Double
    var windKph: Double
}

struct RankPreferencesDTO: Codable, Equatable, Hashable {
    var preferredStyles: [String]
    var favoriteColors: [String]
    var avoidedColors: [String]
}

struct RankContextDTO: Codable, Equatable, Hashable {
    var occasion: String?
    var style: String?
    var season: String?
    var weather: RankWeatherDTO?
    var preferences: RankPreferencesDTO
}

struct RankGarmentDTO: Codable, Equatable, Hashable {
    var id: String
    var category: String
    var subcategory: String
    var primaryColor: String
    var secondaryColor: String?
    var pattern: String
    var material: String
    var formality: Int
}

struct RankCandidateDTO: Codable, Equatable, Hashable {
    var id: String
    var garmentIds: [String]
}

struct RankOutfitsRequest: Codable, Equatable, Hashable {
    var context: RankContextDTO
    var garments: [RankGarmentDTO]
    var candidates: [RankCandidateDTO]
    var count: Int
}

struct RankedOutfitDTO: Codable, Equatable {
    var candidateId: String
    var garmentIds: [String]
    var title: String
    var reasoning: String
}

struct RankOutfitsResponse: Codable, Equatable {
    var outfits: [RankedOutfitDTO]
}

// MARK: Errors

struct APIErrorBody: Codable {
    struct Detail: Codable {
        var code: String
        var message: String
    }
    var error: Detail
}
