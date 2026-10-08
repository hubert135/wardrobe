import Foundation
import SwiftData

enum ModelContainerFactory {
    static let schema = Schema([Garment.self, Outfit.self, OutfitSlot.self, WishlistItem.self, UserProfile.self])

    /// - Parameter inMemory: used by UI tests and previews.
    static func make(inMemory: Bool) -> ModelContainer {
        // `cloudKitDatabase: .none` today; switching to `.automatic` (plus the iCloud capability)
        // is the intended path to multi-device sync. The schema already follows CloudKit's rules.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Could not create the SwiftData container: \(error)")
        }
    }
}
