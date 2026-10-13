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
        case .offline: "Can't reach the Wardrobe server. Check that your computer is on, the iPhone is on the same Wi-Fi, and the address in Profile → Server is right."
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
    /// Turns a garment photo into an online-store style product photo (slow: up to ~2 minutes).
    func renderProductPhoto(image: ImagePayload, garment: RenderGarmentHintsDTO?) async throws -> ImagePayload
}

/// Supplies the bearer token for authenticated requests.
protocol SessionTokenProvider: AnyObject {
    var sessionToken: String? { get }
    /// Stable random id for this installation, used for automatic sessions.
    var deviceID: String { get }
    func store(_ token: String?)
    func sessionExpired()
}

final class HTTPWardrobeAPI: WardrobeAPI {
    /// Read on every request so the server address can be changed in Profile without restarting.
    private let baseURL: () -> URL?
    private let session: URLSession
    private weak var tokens: SessionTokenProvider?
    private let timeout: TimeInterval

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
        self.timeout = timeout
        let configuration = URLSessionConfiguration.default
        // Idle timeout; individual requests set their own (product photos need much longer).
        configuration.timeoutIntervalForRequest = 180
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

    func renderProductPhoto(image: ImagePayload, garment: RenderGarmentHintsDTO?) async throws -> ImagePayload {
        let response: RenderProductPhotoResponse = try await post(
            "v1/garments/render", body: RenderProductPhotoRequest(image: image, garment: garment), timeout: 180
        )
        return response.image
    }

    /// Sends a request. Authenticated calls get an automatic device session when there is none,
    /// and retry once with a fresh one if the server says the session expired. No sign-in needed.
    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, authenticated: Bool = true, timeout: TimeInterval? = nil) async throws -> Response {
        do {
            return try await perform(path, body: body, authenticated: authenticated, timeout: timeout)
        } catch APIError.unauthorized where authenticated {
            tokens?.store(nil)
            try await createDeviceSession()
            return try await perform(path, body: body, authenticated: authenticated, timeout: timeout)
        }
    }

    private func createDeviceSession() async throws {
        guard let tokens else { throw APIError.unauthorized }
        let session: SessionResponse = try await perform(
            "v1/auth/device", body: DeviceSessionRequest(deviceId: tokens.deviceID), authenticated: false, timeout: nil
        )
        tokens.store(session.sessionToken)
    }

    private func perform<Body: Encodable, Response: Decodable>(_ path: String, body: Body, authenticated: Bool, timeout: TimeInterval?) async throws -> Response {
        guard let baseURL = baseURL() else { throw APIError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout ?? self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            if tokens?.sessionToken == nil { try await createDeviceSession() }
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

    /// Calls GET /health and explains the result in plain words (Profile → Test connection).
    static func testConnection() async -> String {
        guard let base = baseURL else { return "No server address is set." }
        var request = URLRequest(url: base.appendingPathComponent("health"), timeoutInterval: 8)
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200 ? "Connected to \(base.absoluteString) ✓" : "The server at \(base.absoluteString) answered with error \(status)."
        } catch let error as URLError {
            let reason: String = switch error.code {
            case .timedOut: "no answer in time. On the iPhone, check Settings → Apps → Wardrobe → Local Network is on, and that your computer's firewall allows Node.js."
            case .cannotConnectToHost: "the computer refused the connection. Is the Wardrobe server running?"
            case .cannotFindHost: "the address could not be found. Check it for typos."
            case .notConnectedToInternet: "the iPhone has no network connection."
            case .appTransportSecurityRequiresSecureConnection: "iOS blocked an insecure connection to this address."
            default: error.localizedDescription
            }
            return "Can't reach \(base.absoluteString): \(reason) (code \(error.code.rawValue))"
        } catch {
            return "Can't reach \(base.absoluteString): \(error.localizedDescription)"
        }
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
    func renderProductPhoto(image: ImagePayload, garment: RenderGarmentHintsDTO?) async throws -> ImagePayload { throw APIError.offline }
}
