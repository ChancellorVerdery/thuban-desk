import Foundation

/// The OAuth client the user created in Google Cloud Console ("Desktop app" type). Google issues a client secret
/// for Desktop clients too; it is not confidential for installed apps but the token endpoint still expects it.
public struct GoogleClientConfig: Codable, Equatable, Sendable {
    public var clientID: String
    public var clientSecret: String?

    public init(clientID: String, clientSecret: String? = nil) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    /// Trims and validates what the user pasted. Client IDs end in `.apps.googleusercontent.com`.
    public static func normalized(clientID rawID: String, clientSecret rawSecret: String?) throws -> GoogleClientConfig {
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw ThubanError.missingClientID }
        guard id.hasSuffix(".apps.googleusercontent.com"), !id.contains(" ") else {
            throw ThubanError.oauth("That does not look like a Google OAuth client ID (it ends in .apps.googleusercontent.com).")
        }
        let secret = rawSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GoogleClientConfig(clientID: id, clientSecret: (secret?.isEmpty ?? true) ? nil : secret)
    }
}

/// One linked Google account. `id` is the lower-cased email address.
public struct GoogleAccount: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var email: String
    public var displayName: String?
    public var linkedAt: Date
    public var refreshToken: String?
    public var accessToken: String?
    public var accessTokenExpiry: Date?
    public var scopes: [String]
    /// Google answered `invalid_grant` (revoked / expired): the tokens are dropped and the user must sign in again.
    public var disconnected: Bool
    public var lastSynced: Date?

    public var id: String { email.lowercased() }

    public init(email: String, displayName: String? = nil, linkedAt: Date = Date(), refreshToken: String?, accessToken: String? = nil,
                accessTokenExpiry: Date? = nil, scopes: [String] = GoogleScopes.all, disconnected: Bool = false, lastSynced: Date? = nil) {
        self.email = email
        self.displayName = displayName
        self.linkedAt = linkedAt
        self.refreshToken = refreshToken
        self.accessToken = accessToken
        self.accessTokenExpiry = accessTokenExpiry
        self.scopes = scopes
        self.disconnected = disconnected
        self.lastSynced = lastSynced
    }

    /// "gmail.com" / "charlotte.edu" — the short account tag the design shows next to threads.
    public var domain: String { email.split(separator: "@").last.map(String.init) ?? email }

    /// True when a still-valid access token is cached (with `margin` seconds to spare).
    public func hasFreshAccessToken(now: Date = Date(), margin: TimeInterval = 60) -> Bool {
        guard accessToken != nil, let expiry = accessTokenExpiry else { return false }
        return expiry.timeIntervalSince(now) > margin
    }
}

/// Everything in `credentials.json` (mode 0600).
public struct CredentialsFile: Codable, Equatable, Sendable {
    public var client: GoogleClientConfig?
    public var accounts: [GoogleAccount]

    public init(client: GoogleClientConfig? = nil, accounts: [GoogleAccount] = []) {
        self.client = client
        self.accounts = accounts
    }

    enum CodingKeys: String, CodingKey { case client, accounts }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        client = try c.decodeIfPresent(GoogleClientConfig.self, forKey: .client)
        accounts = try c.decodeIfPresent([GoogleAccount].self, forKey: .accounts) ?? []
    }

    /// Accounts ordered by link date: the first is the primary.
    public var orderedAccounts: [GoogleAccount] { accounts.sorted { $0.linkedAt < $1.linkedAt } }

    /// The earliest linked account.
    public var primary: GoogleAccount? { orderedAccounts.first }

    public func account(_ id: String) -> GoogleAccount? { accounts.first { $0.id == id.lowercased() } }

    /// Inserts or replaces (by email). A re-link keeps the original `linkedAt`, so the primary never changes by signing in again.
    public mutating func upsert(_ account: GoogleAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            var merged = account
            merged.linkedAt = accounts[index].linkedAt
            merged.lastSynced = account.lastSynced ?? accounts[index].lastSynced
            accounts[index] = merged
        } else {
            accounts.append(account)
        }
    }

    public mutating func remove(_ id: String) {
        accounts.removeAll { $0.id == id.lowercased() }
    }

    public mutating func update(_ id: String, _ change: (inout GoogleAccount) -> Void) {
        guard let index = accounts.firstIndex(where: { $0.id == id.lowercased() }) else { return }
        change(&accounts[index])
    }
}

/// Plain-file credential storage (mode 0600 under the app home). No Keychain by design — see `AppPaths.credentialsFile`.
public enum CredentialStore {
    public static func load(from url: URL = AppPaths.credentialsFile) throws -> CredentialsFile {
        try JSONFile.read(CredentialsFile.self, from: url) ?? CredentialsFile()
    }

    public static func save(_ file: CredentialsFile, to url: URL = AppPaths.credentialsFile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONFile.write(file, to: url, permissions: 0o600)
    }

    public static func clear(at url: URL = AppPaths.credentialsFile) throws {
        try JSONFile.remove(url)
    }
}
