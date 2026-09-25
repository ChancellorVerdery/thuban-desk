import Foundation

/// Owns the credentials file in memory: the OAuth client, every linked account and their tokens. Hands out valid
/// access tokens (refreshing — once, shared by concurrent callers — when within a minute of expiry) and persists
/// every change through `persist`. On `invalid_grant` the account is marked `disconnected`, its tokens are dropped,
/// and `ThubanError.accountDisconnected(email)` is thrown.
public actor AccountTokenStore {
    public private(set) var file: CredentialsFile
    private let session: URLSession
    private let persist: @Sendable (CredentialsFile) throws -> Void
    private let now: @Sendable () -> Date
    private var refreshing: [String: Task<String, Error>] = [:]
    private var observers: [UUID: @Sendable (CredentialsFile) -> Void] = [:]

    public init(file: CredentialsFile, session: URLSession = .shared,
                now: @escaping @Sendable () -> Date = { Date() },
                persist: @escaping @Sendable (CredentialsFile) throws -> Void = { try CredentialStore.save($0) }) {
        self.file = file
        self.session = session
        self.persist = persist
        self.now = now
    }

    // MARK: Observation

    /// Called (on the actor) after every change; the app hops to the main actor to refresh its account list.
    @discardableResult
    public func observe(_ handler: @escaping @Sendable (CredentialsFile) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    private func changed() throws {
        try persist(file)
        for handler in observers.values { handler(file) }
    }

    // MARK: Client + accounts

    public func setClient(_ config: GoogleClientConfig?) throws {
        file.client = config
        try changed()
    }

    public func upsert(_ account: GoogleAccount) throws {
        file.upsert(account)
        try changed()
    }

    /// Removes the account and revokes its refresh token (best effort; revocation failures are ignored).
    public func remove(_ accountID: String, revoke: Bool = true) async throws {
        let account = file.account(accountID)
        file.remove(accountID)
        try changed()
        if revoke, let token = account?.refreshToken, let config = file.client {
            await GoogleOAuth(config: config, session: session).revoke(token: token)
        }
    }

    public func markSynced(_ accountID: String, at date: Date) throws {
        file.update(accountID) { $0.lastSynced = date }
        try changed()
    }

    public var accounts: [GoogleAccount] { file.orderedAccounts }

    // MARK: Tokens

    /// A valid access token for the account; refreshes when needed (or when `forceRefresh`, after a 401).
    public func accessToken(for accountID: String, forceRefresh: Bool = false) async throws -> String {
        guard let account = file.account(accountID) else { throw ThubanError.notSignedIn(accountID) }
        if account.disconnected { throw ThubanError.accountDisconnected(account.email) }
        if !forceRefresh, account.hasFreshAccessToken(now: now()), let token = account.accessToken { return token }
        if let inflight = refreshing[account.id] { return try await inflight.value }
        let task = Task { try await self.performRefresh(accountID: account.id) }
        refreshing[account.id] = task
        defer { refreshing[account.id] = nil }
        return try await task.value
    }

    private func performRefresh(accountID: String) async throws -> String {
        guard let config = file.client else { throw ThubanError.missingClientID }
        guard let account = file.account(accountID) else { throw ThubanError.notSignedIn(accountID) }
        guard let refreshToken = account.refreshToken else {
            try markDisconnected(accountID)
            throw ThubanError.accountDisconnected(account.email)
        }
        do {
            let response = try await GoogleOAuth(config: config, session: session).refresh(refreshToken: refreshToken)
            let issued = now()
            file.update(accountID) {
                $0.accessToken = response.accessToken
                $0.accessTokenExpiry = issued.addingTimeInterval(TimeInterval(response.expiresIn ?? 3599))
                // Google may rotate the refresh token.
                if let rotated = response.refreshToken { $0.refreshToken = rotated }
            }
            try changed()
            return response.accessToken
        } catch is GoogleOAuth.InvalidGrant {
            try markDisconnected(accountID)
            throw ThubanError.accountDisconnected(account.email)
        }
    }

    private func markDisconnected(_ accountID: String) throws {
        file.update(accountID) {
            $0.disconnected = true
            $0.accessToken = nil
            $0.accessTokenExpiry = nil
            $0.refreshToken = nil
        }
        try changed()
    }
}
