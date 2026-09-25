import Foundation

/// Atomic Codable file I/O with fixed encoder settings.
public enum JSONFile {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// `nil` when the file does not exist. Throws `ThubanError.store` when it exists but cannot be decoded.
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try decoder.decode(T.self, from: Data(contentsOf: url))
        } catch {
            throw ThubanError.store("\(url.lastPathComponent) could not be read: \(error.localizedDescription)")
        }
    }

    /// Writes atomically; `permissions` (e.g. 0o600) is applied after the write. `completeProtection` (credentials)
    /// adds `NSFileProtectionComplete` on iOS: the file is unreadable while the device is locked.
    public static func write<T: Encodable>(_ value: T, to url: URL, permissions: Int? = nil, completeProtection: Bool = false) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var options: Data.WritingOptions = .atomic
            #if os(iOS)
            if completeProtection { options.insert(.completeFileProtection) }
            #endif
            try encoder.encode(value).write(to: url, options: options)
            if let permissions {
                try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
            }
        } catch let error as ThubanError {
            throw error
        } catch {
            throw ThubanError.store("\(url.lastPathComponent) could not be written: \(error.localizedDescription)")
        }
    }

    public static func remove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
