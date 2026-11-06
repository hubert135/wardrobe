import XCTest
@testable import OutfitEngine

/// Debug report: suggestions for every style against sample closets, and how different the 3 outfits are.
/// Prints the report; with VARIETY_REPORT_DIR set (CI), also writes one file per block.
final class VarietyReportTests: XCTestCase {
    struct Sample {
        var name: String
        var garments: [EngineGarment]
        var names: [UUID: String]
    }

    static func sample(_ name: String, ids: Set<String>? = nil) -> Sample {
        var garments: [EngineGarment] = []
        var names: [UUID: String] = [:]
        for item in GenericCapsule.items where ids?.contains(item.id) ?? true {
            let garment = EngineGarment(
                category: item.category, subcategory: item.subcategory, primaryColor: item.color,
                secondaryColor: item.secondaryColor, pattern: item.pattern, material: item.material,
                formality: item.formality, seasons: Set(item.seasons)
            )
            garments.append(garment)
            names[garment.id] = item.name
        }
        return Sample(name: name, garments: garments, names: names)
    }

    /// A small everyday closet (12 pieces).
    static let smallIDs: Set<String> = ["C01", "C02", "C09", "C14", "C16", "C23", "C26", "C29", "C37", "C39", "C45", "C53"]

    static let cases: [(Style, Occasion)] = [(.formal, .businessMeeting), (.smartCasual, .work), (.casual, .weekend), (.sporty, .weekend)]

    func testVarietyReport() throws {
        var blocks: [String] = []
        for sample in [Self.sample("capsule"), Self.sample("small", ids: Self.smallIDs)] {
            for (style, occasion) in Self.cases {
                let context = OutfitContext(
                    occasion: occasion, style: style, season: .autumn, weather: WeatherContext(temperatureC: 12),
                    date: Fixtures.monday, recipes: RecipeLibrary.standard
                )
                let outfits = OutfitEngine().suggestWithRecipes(closet: sample.garments, context: context, count: 3)
                blocks.append(report(sample: sample, style: style, occasion: occasion, outfits: outfits))
            }
        }
        let text = blocks.joined(separator: "\n\n")
        print(text)
        if let dir = ProcessInfo.processInfo.environment["VARIETY_REPORT_DIR"] {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            for (index, block) in blocks.enumerated() {
                try block.write(toFile: "\(dir)/\(index).txt", atomically: true, encoding: .utf8)
            }
        }
    }

    private func report(sample: Sample, style: Style, occasion: Occasion, outfits: [EngineOutfit]) -> String {
        var lines = ["\(style.displayName) / \(occasion.displayName), \(sample.name) closet (\(sample.garments.count) pieces): \(outfits.count) outfits"]
        for (index, outfit) in outfits.enumerated() {
            let pieces = [Slot.outerwear, .top, .bottom, .shoes].compactMap { slot in
                outfit.pieces[slot].map { "\(slot.rawValue)=\(sample.names[$0.id] ?? $0.shortLabel)" }
            }
            lines.append("\(index + 1). [\(outfit.recipe?.id ?? "generic")] \(outfit.title) | \(pieces.joined(separator: ", "))")
        }
        for i in outfits.indices {
            for j in outfits.indices where j > i {
                let a = outfits[i].pieces, b = outfits[j].pieces
                let same = [Slot.outerwear, .top, .bottom, .shoes].filter { a[$0] != nil && a[$0]?.id == b[$0]?.id }.map(\.rawValue)
                let differ = [Slot.outerwear, .top, .bottom, .shoes].filter { a[$0]?.id != b[$0]?.id }.map(\.rawValue)
                let nearDuplicate = a[.top]?.id == b[.top]?.id && a[.bottom]?.id == b[.bottom]?.id
                lines.append("  \(i + 1) vs \(j + 1): same \(same.isEmpty ? "-" : same.joined(separator: "+")); differ \(differ.joined(separator: "+"))\(nearDuplicate ? "  <- NEAR-DUPLICATE (same top and bottom)" : "")")
            }
        }
        return lines.joined(separator: "\n")
    }
}
