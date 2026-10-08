import Foundation
import SwiftData

enum ModelContainerFactory {
    static let schema = Schema([Garment.self, Outfit.self, OutfitSlot.self, WishlistItem.self, UserProfile.self])

    /// - Parameter inMemory: used by UI tests and previews.
    static func make(inMemory: Bool) -> ModelContainer {
        // `cloudKitDatabase: .none` today; switching to `.automatic` (plus the iCloud capability)
        // is the intended path to multi-device sync. The schema already follows CloudKit's rules.
        // Keep the store in the app's own container. With the App Group entitlement SwiftData would
        // otherwise default to the shared group container, whose Application Support folder may not exist.
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Could not create the SwiftData container: \(error)")
        }
    }
}
