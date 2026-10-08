import Foundation
import OutfitEngine
import SwiftData

enum WishlistStatus: String, Codable {
    case open, bought
}

@Model
final class WishlistItem {
    var id: UUID = UUID()
    var ownerID: String = "local"
    /// Human description, e.g. "Beige chinos". (Named `itemDescription` to avoid clashing with `description`.)
    var itemDescription: String = ""
    var categoryRaw: String = GarmentCategory.other.rawValue
    var color: String = ""
    var cut: String = ""
    var formality: Int = 3
    var searchQuery: String = ""
    var unlockedOutfitCount: Int = 0
    var statusRaw: String = WishlistStatus.open.rawValue
    var createdAt: Date = Date()

    init(item: HypotheticalItem, unlockedOutfitCount: Int) {
        self.itemDescription = item.title
        self.categoryRaw = item.category.rawValue
        self.color = item.color
        self.cut = item.cut
        self.formality = item.formality
        self.searchQuery = item.searchQuery
        self.unlockedOutfitCount = unlockedOutfitCount
    }

    var category: GarmentCategory { GarmentCategory(rawValue: categoryRaw) ?? .other }

    var status: WishlistStatus {
        get { WishlistStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    var hypotheticalItem: HypotheticalItem {
        HypotheticalItem(category: category, color: color, cut: cut, formality: formality)
    }
}
