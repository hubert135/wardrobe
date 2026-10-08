import Foundation

enum APIError: LocalizedError, Equatable {
    case offline
    case unauthorized
    case rateLimited
    case server(code: String, message: String)
    case invalidResponse
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .offline: "You're offline. Check your connection and try again."
        case .unauthorized: "Your session has expired. Sign in again in Profile."
        case .rateLimited: "Too many requests right now. Try again in a minute."
        case .server(_, let message): message
        case .invalidResponse: "The server sent an unexpected response."
        case .notConfigured: "The backend URL is not configured."
        }
    }
}

/// All AI calls go through the backend; the app never holds an Anthropic key.
protocol WardrobeAPI: AnyObject {
    func createSession(identityToken: String) async throws -> SessionResponse
    func analyzeGarment(image: ImagePayload) async throws -> [AnalyzedGarmentDTO]
    func parseOrder(text: String?, image: ImagePayload?) async throws -> [ParsedOrderItemDTO]
    func rankOutfits(_ request: RankOutfitsRequest) async throws -> RankOutfitsResponse
}

/// Supplies the bearer token for authenticated requests.
protocol SessionTokenProvider: AnyObject {
    var sessionToken: String? { get }
    func sessionExpired()
}

final class HTTPWardrobeAPI: WardrobeAPI {
    /// Read on every request so the server address can be changed in Profile without restarting.
    private let baseURL: () -> URL?
    private let session: URLSession
    private weak var tokens: SessionTokenProvider?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(baseURL: @escaping () -> URL?, tokens: SessionTokenProvider?, timeout: TimeInterval = 45) {
        self.baseURL = baseURL
        self.tokens = tokens
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    static func configuredBaseURL(bundle: Bundle = .main) -> URL? {
        (bundle.object(forInfoDictionaryKey: "WardrobeAPIBaseURL") as? String).flatMap(URL.init(string:))
    }

    func createSession(identityToken: String) async throws -> SessionResponse {
        try await post("v1/auth/session", body: SessionRequest(identityToken: identityToken), authenticated: false)
    }

    func analyzeGarment(image: ImagePayload) async throws -> [AnalyzedGarmentDTO] {
        let response: AnalyzeGarmentResponse = try await post("v1/garments/analyze", body: AnalyzeGarmentRequest(image: image))
        return response.garments
    }

    func parseOrder(text: String?, image: ImagePayload?) async throws -> [ParsedOrderItemDTO] {
        let response: ParseOrderResponse = try await post("v1/orders/parse", body: ParseOrderRequest(text: text, image: image))
        return response.items
    }

    func rankOutfits(_ request: RankOutfitsRequest) async throws -> RankOutfitsResponse {
        try await post("v1/outfits/rank", body: request)
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, authenticated: Bool = true) async throws -> Response {
        guard let baseURL = baseURL() else { throw APIError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let token = tokens?.sessionToken else { throw APIError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .timedOut, .dataNotAllowed:
                throw APIError.offline
            default:
                throw APIError.server(code: "network", message: error.localizedDescription)
            }
        }

        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw APIError.invalidResponse
            }
        case 401:
            tokens?.sessionExpired()
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        default:
            if let body = try? decoder.decode(APIErrorBody.self, from: data) {
                throw APIError.server(code: body.error.code, message: body.error.message)
            }
            throw APIError.server(code: "http_\(http.statusCode)", message: "Something went wrong (\(http.statusCode)). Please try again.")
        }
    }
}

/// Backend address: the build setting by default, or an address typed in Profile
/// (e.g. your computer's Wi-Fi IP when the backend runs at home).
enum ServerSettings {
    static let overrideKey = "server.baseURLOverride"

    static var baseURL: URL? {
        if let override = UserDefaults.standard.string(forKey: overrideKey).flatMap(normalized) { return override }
        return HTTPWardrobeAPI.configuredBaseURL()
    }

    /// Accepts "192.168.1.20:8787" as well as full URLs.
    static func normalized(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url
    }
}

/// Used by UI tests and as a safe default: every call fails as if offline, so the app takes its local paths.
final class OfflineWardrobeAPI: WardrobeAPI {
    func createSession(identityToken: String) async throws -> SessionResponse { throw APIError.offline }
    func analyzeGarment(image: ImagePayload) async throws -> [AnalyzedGarmentDTO] { throw APIError.offline }
    func parseOrder(text: String?, image: ImagePayload?) async throws -> [ParsedOrderItemDTO] { throw APIError.offline }
    func rankOutfits(_ request: RankOutfitsRequest) async throws -> RankOutfitsResponse { throw APIError.offline }
}
