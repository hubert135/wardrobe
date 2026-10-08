import Foundation

/// Hand-off between the Share Extension and the app through the shared App Group container.
/// The extension writes a pending import; the app picks it up when it becomes active.
struct PendingImport: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case text, image }

    var id: UUID = UUID()
    var kind: Kind
    var text: String?
    /// File name inside the pending-imports directory (for images).
    var imageFile: String?
    var createdAt: Date = Date()
}

struct PendingImportStore {
    static let shared = PendingImportStore()

    private let directory: URL

    init(appGroupID: String? = Bundle.main.object(forInfoDictionaryKey: "WardrobeAppGroup") as? String) {
        let fileManager = FileManager.default
        let base: URL
        if let appGroupID, let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            base = container
        } else {
            // Without the App Group entitlement (e.g. unsigned Simulator builds) fall back to the local sandbox.
            base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        }
        directory = base.appendingPathComponent("PendingImports", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func save(text: String) throws {
        try write(PendingImport(kind: .text, text: text))
    }

    func save(imageData: Data) throws {
        let name = UUID().uuidString + ".jpg"
        try imageData.write(to: directory.appendingPathComponent(name), options: .atomic)
        try write(PendingImport(kind: .image, imageFile: name))
    }

    func imageData(for item: PendingImport) -> Data? {
        guard let file = item.imageFile else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(file))
    }

    func all() -> [PendingImport] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(PendingImport.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func remove(_ item: PendingImport) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.id.uuidString + ".json"))
        if let file = item.imageFile {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    private func write(_ item: PendingImport) throws {
        let data = try JSONEncoder().encode(item)
        try data.write(to: directory.appendingPathComponent(item.id.uuidString + ".json"), options: .atomic)
    }
}
