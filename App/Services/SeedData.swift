import Foundation
import OutfitEngine
import UIKit

#if DEBUG
/// Debug-only sample closet so the engine, gaps and UI can be exercised without photographing clothes.
@MainActor
enum SeedData {
    struct Item {
        var name: String
        var category: GarmentCategory
        var color: String
        var formality: Int
        var pattern: Pattern = .solid
        var material: String = "cotton"
        var subcategory: String = ""
        var seasons: Set<Season> = []
        var brand: String = ""
        var price: Double? = nil
        var wearCount: Int = 0
        var secondaryColor: String? = nil
    }

    static let sampleCloset: [Item] = [
        Item(name: "White oxford shirt", category: .shirt, color: "white", formality: 4, subcategory: "oxford shirt", brand: "Uniqlo", price: 40, wearCount: 14),
        Item(name: "Light blue oxford shirt", category: .shirt, color: "light blue", formality: 4, subcategory: "oxford shirt", brand: "Uniqlo", price: 40, wearCount: 11),
        Item(name: "Striped poplin shirt", category: .shirt, color: "white", formality: 3, pattern: .striped, subcategory: "poplin shirt", price: 55, wearCount: 6, secondaryColor: "navy"),
        Item(name: "Pink linen shirt", category: .shirt, color: "pink", formality: 3, material: "linen", subcategory: "linen shirt", seasons: [.spring, .summer], price: 60, wearCount: 2),
        Item(name: "White crew t-shirt", category: .tShirt, color: "white", formality: 2, subcategory: "crew neck", price: 15, wearCount: 20),
        Item(name: "Navy t-shirt", category: .tShirt, color: "navy", formality: 2, subcategory: "crew neck", price: 15, wearCount: 9),
        Item(name: "Navy knitted polo", category: .polo, color: "navy", formality: 3, subcategory: "knitted polo", brand: "Massimo Dutti", price: 70, wearCount: 5),
        Item(name: "Grey merino sweater", category: .sweater, color: "grey", formality: 3, material: "merino wool", subcategory: "crew neck sweater", seasons: [.autumn, .winter, .spring], price: 80, wearCount: 8),
        Item(name: "Burgundy lambswool sweater", category: .sweater, color: "burgundy", formality: 3, material: "lambswool", subcategory: "crew neck sweater", seasons: [.autumn, .winter], price: 90, wearCount: 1),
        Item(name: "Grey zip hoodie", category: .hoodie, color: "grey", formality: 1, material: "cotton fleece", subcategory: "zip hoodie", price: 45, wearCount: 7),
        Item(name: "Navy blazer", category: .blazer, color: "navy", formality: 4, material: "wool", subcategory: "unstructured blazer", brand: "Suitsupply", price: 300, wearCount: 10),
        Item(name: "Grey check blazer", category: .blazer, color: "grey", formality: 4, pattern: .checked, material: "wool", subcategory: "check blazer", seasons: [.autumn, .winter], price: 250, wearCount: 3),
        Item(name: "Olive field jacket", category: .jacket, color: "olive", formality: 3, subcategory: "field jacket", seasons: [.spring, .autumn], price: 120, wearCount: 6),
        Item(name: "Navy wool overcoat", category: .coat, color: "navy", formality: 4, material: "wool", subcategory: "overcoat", seasons: [.autumn, .winter], price: 350, wearCount: 12),
        Item(name: "Beige chinos", category: .chinos, color: "beige", formality: 3, material: "cotton twill", subcategory: "slim chinos", price: 60, wearCount: 15),
        Item(name: "Navy chinos", category: .chinos, color: "navy", formality: 3, material: "cotton twill", subcategory: "slim chinos", price: 60, wearCount: 9),
        Item(name: "Grey wool trousers", category: .trousers, color: "grey", formality: 4, material: "wool", subcategory: "tailored trousers", price: 110, wearCount: 8),
        Item(name: "Charcoal suit trousers", category: .trousers, color: "charcoal", formality: 5, material: "wool", subcategory: "suit trousers", price: 150, wearCount: 2),
        Item(name: "Dark slim jeans", category: .jeans, color: "denim", formality: 3, material: "denim", subcategory: "slim jeans", brand: "Levi's", price: 100, wearCount: 18),
        Item(name: "Beige chino shorts", category: .shorts, color: "beige", formality: 2, subcategory: "chino shorts", seasons: [.summer], price: 40, wearCount: 4),
        Item(name: "White leather sneakers", category: .shoes, color: "white", formality: 3, material: "leather", subcategory: "leather sneakers", brand: "Common Projects", price: 350, wearCount: 25),
        Item(name: "Brown derby shoes", category: .shoes, color: "brown", formality: 4, material: "leather", subcategory: "derby shoes", price: 180, wearCount: 13),
        Item(name: "Black oxford shoes", category: .shoes, color: "black", formality: 5, material: "leather", subcategory: "oxford shoes", price: 220, wearCount: 3),
        Item(name: "Tan suede chukka boots", category: .shoes, color: "tan", formality: 3, material: "suede", subcategory: "chukka boots", seasons: [.autumn, .winter, .spring], price: 160, wearCount: 6),
        Item(name: "Brown leather belt", category: .accessory, color: "brown", formality: 3, material: "leather", subcategory: "belt", price: 50, wearCount: 30)
    ]

    /// Seven garments for the UI test: adding one more (8) unlocks outfit generation.
    static let uiTestCloset: [Item] = [
        Item(name: "White shirt", category: .shirt, color: "white", formality: 3, subcategory: "shirt"),
        Item(name: "Light blue shirt", category: .shirt, color: "light blue", formality: 3, subcategory: "shirt"),
        Item(name: "Navy chinos", category: .chinos, color: "navy", formality: 3, subcategory: "chinos"),
        Item(name: "Grey trousers", category: .trousers, color: "grey", formality: 4, subcategory: "trousers"),
        Item(name: "Brown derby shoes", category: .shoes, color: "brown", formality: 4, material: "leather", subcategory: "derby shoes"),
        Item(name: "White sneakers", category: .shoes, color: "white", formality: 3, material: "leather", subcategory: "sneakers"),
        Item(name: "Navy blazer", category: .blazer, color: "navy", formality: 4, material: "wool", subcategory: "blazer")
    ]

    static func seed(_ items: [Item], into repository: WardrobeRepository, imageStore: ImageStore) {
        for item in items {
            let garment = Garment(
                name: item.name, category: item.category, subcategory: item.subcategory, primaryColor: item.color,
                secondaryColor: item.secondaryColor, pattern: item.pattern, material: item.material,
                formality: item.formality, seasons: item.seasons, brand: item.brand, price: item.price,
                purchaseDate: Calendar.current.date(byAdding: .month, value: -item.wearCount % 12, to: Date()),
                source: .manual, status: .confirmed
            )
            garment.wearCount = item.wearCount
            if let png = PlaceholderImageRenderer.render(category: item.category, color: item.color, pattern: item.pattern).pngData() {
                garment.cutoutImageFile = try? imageStore.save(png, fileExtension: "png")
            }
            repository.insert(garment)
        }
    }
}
#endif

/// Draws a simple garment silhouette in the garment's color. Used for seed data and as a fallback image.
enum PlaceholderImageRenderer {
    static func render(category: GarmentCategory, color: String, pattern: Pattern = .solid, size: CGFloat = 600) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let fill = UIColor(hex: ColorPalette.color(named: color)?.hex ?? "#8E8E93")
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let cg = context.cgContext
            cg.scaleBy(x: size / 600, y: size / 600)
            let path = silhouette(for: category)
            fill.setFill()
            path.fill()
            if pattern != .solid {
                cg.saveGState()
                path.addClip()
                UIColor.white.withAlphaComponent(0.35).setFill()
                let step: CGFloat = pattern == .striped ? 36 : 48
                var x: CGFloat = 0
                while x < 600 {
                    cg.fill(CGRect(x: x, y: 0, width: step / 3, height: 600))
                    if pattern == .checked { cg.fill(CGRect(x: 0, y: x, width: 600, height: step / 3)) }
                    x += step
                }
                cg.restoreGState()
            }
            fill.darker().setStroke()
            path.lineWidth = 6
            path.stroke()
        }
    }

    private static func polygon(_ points: [(CGFloat, CGFloat)]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        path.close()
        path.lineJoinStyle = .round
        return path
    }

    private static func silhouette(for category: GarmentCategory) -> UIBezierPath {
        switch category.slot {
        case .top:
            return polygon([(210, 90), (255, 125), (345, 125), (390, 90), (500, 140), (560, 290), (490, 315), (450, 235),
                            (450, 520), (150, 520), (150, 235), (110, 315), (40, 290), (100, 140)])
        case .outerwear:
            return polygon([(205, 70), (300, 210), (395, 70), (505, 120), (565, 330), (495, 350), (460, 250),
                            (460, 560), (140, 560), (140, 250), (105, 350), (35, 330), (95, 120)])
        case .bottom:
            let bottom: CGFloat = category == .shorts ? 330 : 560
            return polygon([(195, 60), (405, 60), (435, bottom), (325, bottom), (300, 220), (275, bottom), (165, bottom)])
        case .shoes:
            let path = UIBezierPath(roundedRect: CGRect(x: 70, y: 290, width: 460, height: 130), cornerRadius: 60)
            path.append(UIBezierPath(roundedRect: CGRect(x: 60, y: 410, width: 480, height: 36), cornerRadius: 14))
            return path
        case .accessory:
            let path = UIBezierPath(roundedRect: CGRect(x: 50, y: 265, width: 500, height: 70), cornerRadius: 20)
            path.append(UIBezierPath(roundedRect: CGRect(x: 380, y: 245, width: 90, height: 110), cornerRadius: 12))
            return path
        case nil:
            return UIBezierPath(roundedRect: CGRect(x: 120, y: 120, width: 360, height: 360), cornerRadius: 40)
        }
    }
}
