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

    static func context(_ style: Style, _ occasion: Occasion) -> OutfitContext {
        OutfitContext(
            occasion: occasion, style: style, season: .autumn, weather: WeatherContext(temperatureC: 12),
            date: Fixtures.monday, recipes: RecipeLibrary.standard
        )
    }

    func testVarietyReport() throws {
        var blocks: [String] = []
        for sample in [Self.sample("capsule"), Self.sample("small", ids: Self.smallIDs)] {
            for (style, occasion) in Self.cases {
                let set = OutfitEngine().suggestionSet(closet: sample.garments, context: Self.context(style, occasion), count: 3)
                blocks.append(report(sample: sample, style: style, occasion: occasion, set: set))
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

    private func report(sample: Sample, style: Style, occasion: Occasion, set: SuggestionSet) -> String {
        let outfits = set.outfits
        var lines = ["AFTER \(style.displayName) / \(occasion.displayName), \(sample.name) closet (\(sample.garments.count) pieces): \(outfits.count) outfits"]
        for (index, outfit) in outfits.enumerated() {
            let pieces = [Slot.outerwear, .top, .bottom, .shoes].compactMap { slot in
                outfit.pieces[slot].map { "\(slot.rawValue)=\(sample.names[$0.id] ?? $0.shortLabel)" }
            }
            let signature = outfit.signature
            let idea = signature.look?.displayName ?? "no template"
            lines.append("\(index + 1). [\(outfit.recipe?.id ?? "generic") \(idea), \(signature.silhouette)] \(outfit.title) | \(pieces.joined(separator: ", "))")
        }
        let variety = OutfitVariety.suggestions
        for i in outfits.indices {
            for j in outfits.indices where j > i {
                let differ = outfits[i].signature.differences(from: outfits[j].signature)
                let names = VarietyDimension.allCases.filter(differ.contains).map(\.rawValue)
                let verdict = variety.areDistinct(outfits[i], outfits[j]) ? "OK" : "NEAR-DUPLICATE"
                lines.append("  \(i + 1) vs \(j + 1): differ in \(names.count) (\(names.joined(separator: "+"))) \(verdict)")
            }
        }
        for unlock in set.unlocks {
            lines.append("  unlock: add \(unlock.piece.displayName.lowercased()) -> \(unlock.recipe.id) \(unlock.recipe.title) (\(unlock.recipe.effectiveLook.displayName))")
        }
        return lines.joined(separator: "\n")
    }
}

/// The rule itself: three genuinely different outfits, or fewer with an honest hint.
final class OutfitVarietyTests: XCTestCase {
    let variety = OutfitVariety.suggestions

    func testEveryStyleGetsThreeDistinctOutfitsFromDifferentTemplates() {
        let capsule = VarietyReportTests.sample("capsule").garments
        for (style, occasion) in VarietyReportTests.cases {
            let outfits = OutfitEngine().suggestionSet(closet: capsule, context: VarietyReportTests.context(style, occasion), count: 3).outfits
            XCTAssertEqual(outfits.count, 3, "\(style)")
            XCTAssertTrue(variety.isDistinctSet(outfits), "\(style): \(outfits.map(\.title))")
            XCTAssertEqual(Set(outfits.compactMap { $0.recipe?.id }).count, outfits.count, "\(style): one template per outfit")
            XCTAssertGreaterThanOrEqual(Set(outfits.compactMap { $0.recipe?.effectiveLook }).count, 2, "\(style): more than one idea")
        }
    }

    func testSmallClosetNeverPadsWithNearDuplicates() {
        let small = VarietyReportTests.sample("small", ids: VarietyReportTests.smallIDs).garments
        for (style, occasion) in VarietyReportTests.cases {
            let set = OutfitEngine().suggestionSet(closet: small, context: VarietyReportTests.context(style, occasion), count: 3)
            XCTAssertTrue(variety.isDistinctSet(set.outfits), "\(style): \(set.outfits.map(\.title))")
            if set.outfits.count < 3 {
                XCTAssertFalse(set.unlocks.isEmpty, "\(style): fewer outfits come with a piece that would unlock another look")
            }
        }
    }

    func testShoesAloneNeverMakeADifferentOutfit() {
        let shirt = Fixtures.garment(.shirt, "white", formality: 3)
        let chinos = Fixtures.garment(.chinos, "beige", formality: 3)
        let brown = Fixtures.garment(.shoes, "brown", formality: 3)
        let white = Fixtures.garment(.shoes, "white", formality: 3)
        let blazer = Fixtures.garment(.blazer, "navy", formality: 4)
        let a = OutfitSignature(candidate: OutfitCandidate(pieces: [.top: shirt, .bottom: chinos, .shoes: brown]), recipe: nil)
        let b = OutfitSignature(candidate: OutfitCandidate(pieces: [.top: shirt, .bottom: chinos, .shoes: white]), recipe: nil)
        let c = OutfitSignature(candidate: OutfitCandidate(pieces: [.outerwear: blazer, .top: shirt, .bottom: chinos, .shoes: white]), recipe: nil)
        XCTAssertFalse(variety.areDistinct(a, b))
        XCTAssertFalse(variety.areDistinct(a, c), "Adding a jacket to the same shirt and chinos is not a new outfit")
    }

    func testSameSuitWithAnotherShirtIsTheSameOutfit() {
        let jacket = Fixtures.garment(.blazer, "navy", formality: 5, material: "wool", subcategory: "suit jacket")
        let trousers = Fixtures.garment(.trousers, "navy", formality: 5, material: "wool", subcategory: "suit trousers")
        let white = Fixtures.garment(.shirt, "white", formality: 5)
        let blue = Fixtures.garment(.shirt, "light blue", formality: 5)
        let shoes = Fixtures.garment(.shoes, "black", formality: 5)
        let business = StyleRecipe(id: "A", title: "A", styles: [.formal], pieces: [RecipePiece(slot: .outerwear, categories: [.blazer])], look: .business)
        let evening = StyleRecipe(id: "B", title: "B", styles: [.formal], pieces: [RecipePiece(slot: .outerwear, categories: [.blazer])], look: .evening)
        let a = OutfitSignature(candidate: OutfitCandidate(pieces: [.outerwear: jacket, .top: white, .bottom: trousers, .shoes: shoes]), recipe: business)
        let b = OutfitSignature(candidate: OutfitCandidate(pieces: [.outerwear: jacket, .top: blue, .bottom: trousers, .shoes: shoes]), recipe: evening)
        XCTAssertFalse(variety.areDistinct(a, b))
    }

    func testSilhouetteComesFromTheGarments() {
        let knowledge = StyleKnowledge.shared
        let pleated = Fixtures.garment(.trousers, "grey", material: "wool", subcategory: "high-rise pleated wide-leg trousers")
        let chinos = Fixtures.garment(.chinos, "beige", material: "cotton twill", subcategory: "slim chinos")
        let suit = Fixtures.garment(.trousers, "navy", material: "wool suit", subcategory: "suit trousers")
        let cable = Fixtures.garment(.sweater, "cream", material: "wool cable knit", subcategory: "cable knit sweater")
        XCTAssertEqual(knowledge.fit(of: pleated), "wide")
        XCTAssertEqual(knowledge.fit(of: chinos), "slim")
        XCTAssertEqual(knowledge.fit(of: suit), "tailored")
        XCTAssertEqual(knowledge.silhouette(of: OutfitCandidate(pieces: [.top: cable, .bottom: chinos])), "slim+volume")
    }

    func testStyleGuideIdeasAreInTheLibrary() {
        let library = RecipeLibrary.standard
        XCTAssertTrue(library.contains { recipe in
            recipe.pieces.contains { $0.slot == .bottom && $0.requires.contains("high-waisted") }
        }, "High-waisted trousers have their own templates")
        XCTAssertTrue(library.allSatisfy { $0.look != nil }, "Every template names its idea")
        for style in Style.allCases {
            let looks = Set(library.filter { $0.styles.contains(style) }.map(\.effectiveLook))
            XCTAssertGreaterThanOrEqual(looks.count, 3, "\(style) needs at least three ideas")
        }
    }
}
