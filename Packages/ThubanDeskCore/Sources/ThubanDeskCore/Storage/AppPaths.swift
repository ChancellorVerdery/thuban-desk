import Foundation

/// Where the app keeps its files. `THUBAN_DESK_HOME` overrides the root (smoke and tests point it at a temp dir).
public enum AppPaths {
    public static let homeVariable = "THUBAN_DESK_HOME"

    /// Set by tests to redirect every path without touching the process environment.
    nonisolated(unsafe) public static var overrideHome: URL?

    /// `~/Library/Application Support/Thuban Desk` (on iOS: Application Support inside the app container) unless overridden. Fixture mode never uses the real folder:
    /// without `THUBAN_DESK_HOME` it gets a throwaway temp directory, so the fake Google (which answers
    /// `invalid_grant` to any real refresh token) can never disconnect — and erase — the user's real accounts.
    public static var home: URL {
        if let overrideHome { return overrideHome }
        if let raw = ProcessInfo.processInfo.environment[homeVariable]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        }
        if FixtureMode.isEnabled { return fixtureFallbackHome }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Thuban Desk", isDirectory: true)
    }

    private static let fixtureFallbackHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("thuban-desk-fixtures-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    public static var settingsFile: URL { home.appendingPathComponent("settings.json") }
    /// OAuth client + every account's tokens, mode 0600. Deliberately a file rather than the Keychain: an
    /// ad-hoc-signed build would trigger a Keychain prompt on every launch.
    public static var credentialsFile: URL { home.appendingPathComponent("credentials.json") }
    public static var cacheDirectory: URL { home.appendingPathComponent("cache", isDirectory: true) }
    /// Downloaded attachments.
    public static var downloadsDirectory: URL { home.appendingPathComponent("attachments", isDirectory: true) }

    /// Creates the home tree (idempotent). On iOS the folders carry `NSFileProtectionComplete`, so every file created
    /// in them (credentials, settings, cached mail and events) inherits it.
    public static func ensureDirectories() throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        for url in [home, cacheDirectory, downloadsDirectory] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
            #if os(iOS)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            #endif
        }
    }
}
