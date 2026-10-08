import CryptoKit
import Foundation
import OutfitEngine

/// An outfit shown on screen (not yet persisted unless worn or favorited).
struct OutfitSuggestion: Identifiable, Hashable {
    enum Origin: String { case ai, local }

    var outfit: EngineOutfit
    var occasion: Occasion
    var style: Style
    var season: Season
    var weather: WeatherSnapshot?
    var origin: Origin
    var isFavorite = false
    var isWornToday = false

    var id: String { outfit.id }
}

/// Suggestion pipeline: deterministic engine shortlist -> AI ranking (cached) -> validated result,
/// with a local fallback whenever the backend is unavailable.
@MainActor
final class OutfitService {
    let engine: OutfitEngine
    private let api: WardrobeAPI
    private let cache: RankingCache
    /// AI ranking is attempted only when this returns true (e.g. signed in).
    var isAIEnabled: @MainActor () -> Bool

    init(engine: OutfitEngine = OutfitEngine(), api: WardrobeAPI, cache: RankingCache = RankingCache(), isAIEnabled: @escaping @MainActor () -> Bool) {
        self.engine = engine
        self.api = api
        self.cache = cache
        self.isAIEnabled = isAIEnabled
    }

    func suggestions(closet: [EngineGarment], context: OutfitContext, count: Int) async -> ([EngineOutfit], OutfitSuggestion.Origin) {
        let shortlist = engine.shortlist(closet: closet, context: context, limit: 30)
        guard !shortlist.isEmpty else { return ([], .local) }
        let local = { () -> [EngineOutfit] in
            self.engine.scorer.selectDiverse(shortlist, count: count).map {
                self.engine.finalize($0.candidate, score: $0.score, closet: closet, context: context)
            }
        }
        // With very few options there is nothing for the AI to choose; save the call.
        guard isAIEnabled(), shortlist.count > count else { return (local(), .local) }

        let request = RankRequestBuilder.request(shortlist: shortlist.map(\.candidate), context: context, count: count)
        let key = RankingCache.key(for: request)
        let ranked: [RankedOutfitDTO]
        if let cached = cache.load(key) {
            ranked = cached
        } else {
            do {
                ranked = try await api.rankOutfits(request).outfits
            } catch {
                return (local(), .local)
            }
        }

        let validated = RankResponseValidator.validate(
            ranked, shortlist: shortlist.map(\.candidate), closetIDs: Set(closet.map(\.id)), count: count
        )
        guard !validated.isEmpty else { return (local(), .local) }
        cache.store(validated.map(\.dto), for: key)

        var outfits = validated.map {
            engine.finalize($0.candidate, closet: closet, context: context, title: $0.dto.title, reasoning: $0.dto.reasoning)
        }
        // Top up from the local ranking if the AI returned fewer than requested.
        for extra in local() where outfits.count < count && !outfits.contains(where: { $0.id == extra.id }) {
            outfits.append(extra)
        }
        return (outfits, .ai)
    }

    /// Builder: anchors in `context`, optional missing pieces. Ranked locally (missing pieces
    /// are hypothetical, so there is nothing reliable for the AI to add).
    func build(closet: [EngineGarment], context: OutfitContext, includeMissing: Bool, count: Int = 5) -> [EngineOutfit] {
        engine.build(closet: closet, context: context, includeMissing: includeMissing, count: count)
    }
}

enum RankRequestBuilder {
    static func request(shortlist: [OutfitCandidate], context: OutfitContext, count: Int) -> RankOutfitsRequest {
        var garments: [UUID: EngineGarment] = [:]
        for candidate in shortlist {
            for garment in candidate.garments { garments[garment.id] = garment }
        }
        let weather = context.weather.map {
            RankWeatherDTO(temperatureC: $0.temperatureC, feelsLikeC: $0.feelsLikeC, precipitationChance: $0.precipitationChance, windKph: $0.windKph)
        }
        return RankOutfitsRequest(
            context: RankContextDTO(
                occasion: context.occasion?.rawValue,
                style: context.style?.rawValue,
                season: context.season?.rawValue,
                weather: weather,
                preferences: RankPreferencesDTO(
                    preferredStyles: context.preferences.preferredStyles.map(\.rawValue),
                    favoriteColors: context.preferences.favoriteColors.sorted(),
                    avoidedColors: context.preferences.avoidedColors.sorted()
                )
            ),
            garments: garments.values.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                RankGarmentDTO(
                    id: $0.id.uuidString, category: $0.category.rawValue, subcategory: $0.subcategory,
                    primaryColor: $0.primaryColor, secondaryColor: $0.secondaryColor, pattern: $0.pattern.rawValue,
                    material: $0.material, formality: $0.formality
                )
            },
            candidates: shortlist.enumerated().map { index, candidate in
                RankCandidateDTO(id: "c\(index + 1)", garmentIds: candidate.garmentIDs.map(\.uuidString))
            },
            count: count
        )
    }
}

/// Never trust the AI blindly: only candidates we generated, only garments the user owns.
enum RankResponseValidator {
    struct Validated {
        var candidate: OutfitCandidate
        var dto: RankedOutfitDTO
    }

    static let maxTitleLength = 60
    static let maxReasoningLength = 220

    static func validate(_ ranked: [RankedOutfitDTO], shortlist: [OutfitCandidate], closetIDs: Set<UUID>, count: Int) -> [Validated] {
        var byRequestID: [String: OutfitCandidate] = [:]
        var byGarmentSet: [Set<String>: OutfitCandidate] = [:]
        for (index, candidate) in shortlist.enumerated() {
            byRequestID["c\(index + 1)"] = candidate
            byGarmentSet[Set(candidate.garmentIDs.map(\.uuidString))] = candidate
        }

        var result: [Validated] = []
        var seen = Set<String>()
        for item in ranked {
            let candidate = byRequestID[item.candidateId] ?? byGarmentSet[Set(item.garmentIds)]
            guard let candidate,
                  candidate.garmentIDs.allSatisfy(closetIDs.contains),
                  item.garmentIds.allSatisfy({ UUID(uuidString: $0).map(closetIDs.contains) ?? false }),
                  seen.insert(candidate.id).inserted else { continue }

            var dto = item
            dto.title = clean(item.title, limit: maxTitleLength)
            dto.reasoning = clean(item.reasoning, limit: maxReasoningLength)
            if dto.title.isEmpty || dto.reasoning.isEmpty { continue }
            result.append(Validated(candidate: candidate, dto: dto))
            if result.count == count { break }
        }
        return result
    }

    private static func clean(_ text: String, limit: Int) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Caches AI rankings per (context, weather bucket, shortlist) for the current day to avoid repeated paid calls.
final class RankingCache {
    private struct Entry: Codable {
        var day: String
        var outfits: [RankedOutfitDTO]
    }

    private var entries: [String: Entry]
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("outfit-ranking-cache.json")
        if let data = try? Data(contentsOf: self.fileURL), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded.filter { $0.value.day == Self.today }
        } else {
            entries = [:]
        }
    }

    /// Weather is bucketed (2°C steps, rain yes/no, wind in 15 km/h steps) so tiny changes reuse the cache.
    static func key(for request: RankOutfitsRequest) -> String {
        var bucketed = request
        if let weather = request.context.weather {
            bucketed.context.weather = RankWeatherDTO(
                temperatureC: (weather.temperatureC / 2).rounded() * 2,
                feelsLikeC: (weather.feelsLikeC / 2).rounded() * 2,
                precipitationChance: weather.precipitationChance >= 0.5 ? 1 : 0,
                windKph: (weather.windKph / 15).rounded() * 15
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(bucketed)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func load(_ key: String) -> [RankedOutfitDTO]? {
        guard let entry = entries[key], entry.day == Self.today else { return nil }
        return entry.outfits
    }

    func store(_ outfits: [RankedOutfitDTO], for key: String) {
        entries[key] = Entry(day: Self.today, outfits: outfits)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func clear() {
        entries = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var today: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
