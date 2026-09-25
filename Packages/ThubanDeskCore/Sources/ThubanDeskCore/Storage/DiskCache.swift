import CryptoKit
import Foundation

/// A key → JSON blob cache on disk, so the app opens instantly on cached data and works offline.
/// Entries carry the time they were stored; callers decide what "stale" means.
public actor DiskCache {
    public struct Entry: Sendable {
        public var data: Data
        public var storedAt: Date
    }

    private let directory: URL
    private var memory: [String: Entry] = [:]

    public init(directory: URL = AppPaths.cacheDirectory) {
        self.directory = directory
    }

    public func entry(for key: String) -> Entry? {
        if let hit = memory[key] { return hit }
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        let entry = Entry(data: data, storedAt: modified)
        memory[key] = entry
        return entry
    }

    public func store(_ data: Data, for key: String) {
        let entry = Entry(data: data, storedAt: Date())
        memory[key] = entry
        let url = fileURL(for: key)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    public func remove(_ key: String) {
        memory[key] = nil
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    /// Deletes every cached entry.
    public func clear() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Total bytes on disk.
    public func byteCount() -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        return names.reduce(0) { total, name in
            let path = directory.appendingPathComponent(name).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            return total + size
        }
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }
}
