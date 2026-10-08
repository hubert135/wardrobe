import Foundation

public struct NamedColor: Sendable, Hashable, Identifiable {
    public let name: String
    /// sRGB hex, e.g. "#1F2A44".
    public let hex: String
    /// Neutral colors form the base of an outfit and never count as accents.
    public let isNeutral: Bool

    public var id: String { name }
    public var displayName: String { name.capitalized }
}

/// The closed set of color names used across the app, the backend prompts and the engine.
/// Keep in sync with `backend/src/schemas/taxonomy.ts`.
public enum ColorPalette {
    public static let all: [NamedColor] = [
        NamedColor(name: "black", hex: "#1C1C1E", isNeutral: true),
        NamedColor(name: "white", hex: "#F7F7F5", isNeutral: true),
        NamedColor(name: "grey", hex: "#8E8E93", isNeutral: true),
        NamedColor(name: "charcoal", hex: "#3A3A3C", isNeutral: true),
        NamedColor(name: "navy", hex: "#1F2A44", isNeutral: true),
        NamedColor(name: "light blue", hex: "#A9C5E3", isNeutral: true),
        NamedColor(name: "denim", hex: "#3B5A7F", isNeutral: true),
        NamedColor(name: "beige", hex: "#D8C7A8", isNeutral: true),
        NamedColor(name: "cream", hex: "#EFE6D2", isNeutral: true),
        NamedColor(name: "tan", hex: "#B98B5E", isNeutral: true),
        NamedColor(name: "brown", hex: "#6B4423", isNeutral: true),
        NamedColor(name: "khaki", hex: "#A99F6E", isNeutral: true),
        NamedColor(name: "olive", hex: "#5F6B3A", isNeutral: false),
        NamedColor(name: "green", hex: "#2E6B4A", isNeutral: false),
        NamedColor(name: "blue", hex: "#2F6DB5", isNeutral: false),
        NamedColor(name: "burgundy", hex: "#6D1F2F", isNeutral: false),
        NamedColor(name: "red", hex: "#B3261E", isNeutral: false),
        NamedColor(name: "pink", hex: "#E3A3B5", isNeutral: false),
        NamedColor(name: "yellow", hex: "#E5C24A", isNeutral: false),
        NamedColor(name: "orange", hex: "#D9822B", isNeutral: false),
        NamedColor(name: "purple", hex: "#6A4C93", isNeutral: false),
        NamedColor(name: "multicolor", hex: "#9A9A9A", isNeutral: false)
    ]

    public static let names: [String] = all.map(\.name)

    private static let byName: [String: NamedColor] = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    private static let synonyms: [String: String] = [
        "gray": "grey", "light grey": "grey", "light gray": "grey", "silver": "grey", "heather grey": "grey",
        "dark grey": "charcoal", "dark gray": "charcoal", "anthracite": "charcoal", "graphite": "charcoal",
        "dark blue": "navy", "midnight blue": "navy", "midnight": "navy", "marine": "navy", "navy blue": "navy",
        "sky blue": "light blue", "pale blue": "light blue", "baby blue": "light blue",
        "indigo": "denim", "dark denim": "denim", "light denim": "denim", "washed blue": "denim",
        "royal blue": "blue", "cobalt": "blue",
        "sand": "beige", "stone": "beige", "taupe": "beige", "nude": "beige",
        "off-white": "cream", "off white": "cream", "ecru": "cream", "ivory": "cream", "oatmeal": "cream",
        "camel": "tan", "cognac": "tan", "caramel": "tan", "light brown": "tan",
        "dark brown": "brown", "chocolate": "brown", "mocha": "brown", "chestnut": "brown",
        "army green": "olive", "military green": "olive", "sage": "olive",
        "forest green": "green", "bottle green": "green", "dark green": "green", "emerald": "green", "mint": "green",
        "wine": "burgundy", "maroon": "burgundy", "bordeaux": "burgundy", "oxblood": "burgundy",
        "rose": "pink", "coral": "orange", "rust": "orange", "mustard": "yellow",
        "lilac": "purple", "lavender": "purple", "violet": "purple",
        "multi": "multicolor", "multi-color": "multicolor", "multicolour": "multicolor", "print": "multicolor"
    ]

    /// Maps free-form color text ("Dark Blue", "camel") to a palette name, or `nil` if unknown.
    public static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if byName[key] != nil { return key }
        if let synonym = synonyms[key] { return synonym }
        // Fall back to the longest known name contained in the text ("navy wool" -> "navy").
        let candidates = (Array(synonyms.keys) + names).sorted { $0.count > $1.count }
        for candidate in candidates where key.contains(candidate) {
            return synonyms[candidate] ?? candidate
        }
        return nil
    }

    public static func color(named name: String) -> NamedColor? { byName[name.lowercased()] }

    /// Unknown colors are treated as accents so they are never silently assumed safe.
    public static func isNeutral(_ name: String) -> Bool { byName[name.lowercased()]?.isNeutral ?? false }
}
