import Foundation

/// Template-based titles and one-sentence reasoning for offline outfits.
/// The AI ranking replaces these with richer wording when the backend is reachable.
public struct ReasoningWriter: Sendable {
    public var rules: OutfitRules

    public init(rules: OutfitRules = OutfitRules()) { self.rules = rules }

    public func title(for candidate: OutfitCandidate) -> String {
        let lead = candidate.pieces[.outerwear] ?? candidate.pieces[.top]
        let parts = [lead, candidate.pieces[.bottom]].compactMap { $0 }.map(\.shortLabel)
        guard let first = parts.first else { return "Outfit" }
        let sentence = parts.count > 1 ? "\(first) & \(parts[1])" : first
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    public func reasoning(for candidate: OutfitCandidate, in context: OutfitContext) -> String {
        let pieces = candidate.pieces
        let upper = pieces[.outerwear] ?? pieces[.top]
        let accents = rules.accentColors(in: candidate.garments)

        var base: String
        if let accent = accents.first, accents.count == 1,
           let accentPiece = candidate.garments.first(where: { $0.primaryColor == accent }) {
            base = "The \(accentPiece.shortLabel) adds one point of color to a calm neutral base"
        } else if let upper, let bottom = pieces[.bottom], upper.primaryColor != bottom.primaryColor {
            base = "\(upper.primaryColor.capitalizedFirst) and \(bottom.primaryColor) make an easy, balanced base"
        } else {
            base = "A tonal, low-effort combination that keeps the focus on fit"
        }

        var clause: String?
        if let weather = context.weather, rules.requiresOuterwear(context), let outer = pieces[.outerwear] {
            clause = "the \(outer.shortLabel) handles the \(Int(weather.feelsLikeC.rounded()))°C chill"
        } else if rules.isRainy(context.weather), let shoes = pieces[.shoes] {
            clause = "the \(shoes.shortLabel) can cope with the rain"
        } else if let shoes = pieces[.shoes], let top = pieces[.top] {
            if shoes.formality > top.formality {
                clause = "the \(shoes.shortLabel) lift the formality"
            } else if shoes.formality < top.formality {
                clause = "the \(shoes.shortLabel) keep it relaxed"
            } else {
                clause = "the \(shoes.shortLabel) keep it consistent"
            }
        }
        if let clause { base += ", and " + clause }
        return base + "."
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
