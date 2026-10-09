import Foundation
import UIKit

/// Image persistence behind a protocol so a CloudKit/iCloud-backed store can replace it later.
/// The database only keeps file names; the bytes live here.
protocol ImageStore: AnyObject {
    /// Saves bytes under a new unique name (optionally prefixed, e.g. "product-") and returns the name.
    func save(_ data: Data, fileExtension: String, prefix: String) throws -> String
    func url(for fileName: String) -> URL
    func data(for fileName: String) -> Data?
    func image(for fileName: String) -> UIImage?
    func delete(_ fileName: String)
    func deleteAll()
}

extension ImageStore {
    func save(_ data: Data, fileExtension: String) throws -> String {
        try save(data, fileExtension: fileExtension, prefix: "")
    }
}

/// Stores images in Application Support/Images with a small in-memory cache.
final class FileImageStore: ImageStore {
    private let directory: URL
    private let cache = NSCache<NSString, UIImage>()

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Images", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        cache.countLimit = 200
    }

    func save(_ data: Data, fileExtension: String, prefix: String) throws -> String {
        let name = prefix + UUID().uuidString + "." + fileExtension
        try data.write(to: url(for: name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return name
    }

    func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    func data(for fileName: String) -> Data? {
        try? Data(contentsOf: url(for: fileName))
    }

    func image(for fileName: String) -> UIImage? {
        if let cached = cache.object(forKey: fileName as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: url(for: fileName).path) else { return nil }
        cache.setObject(image, forKey: fileName as NSString)
        return image
    }

    func delete(_ fileName: String) {
        cache.removeObject(forKey: fileName as NSString)
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    func deleteAll() {
        cache.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
