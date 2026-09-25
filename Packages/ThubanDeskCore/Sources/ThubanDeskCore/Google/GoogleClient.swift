import Foundation

/// One Google REST call, built by the typed endpoint helpers (`CalendarAPI`, `GmailAPI`). Building a request never
/// performs it, so tests can inspect writes and sends without executing them.
public struct GoogleRequest: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// GET — retried on 429 / 5xx / transient network errors.
        case read
        /// Changes Google state (insert / patch / modify / delete). Needs `WriteGate.allowWrites`.
        case write
        /// Sends mail (messages.send, drafts.send). Needs `allowWrites` and `allowSend`; only retried on 429.
        case send
    }

    public var method: String
    public var url: URL
    public var body: Data?
    public var contentType: String?
    public var kind: Kind

    public init(method: String, url: URL, body: Data? = nil, contentType: String? = nil, kind: Kind) {
        self.method = method
        self.url = url
        self.body = body
        self.contentType = contentType
        self.kind = kind
    }

    /// Whether repeating the request after an ambiguous failure (5xx: it may have gone through) cannot create a
    /// second copy of something. GET / PUT / PATCH / DELETE are; POST creates (events.insert, labels / filters /
    /// drafts.create) except Gmail's label-changing POSTs (modify, trash, untrash, batchModify, batchDelete).
    public var isIdempotent: Bool {
        guard kind != .send else { return false }
        guard method.uppercased() == "POST" else { return true }
        return ["modify", "trash", "untrash", "batchModify", "batchDelete"].contains(url.lastPathComponent)
    }

    /// `base` + escaped path segments + strictly escaped query.
    public static func url(_ base: URL, _ segments: [String], query: [(String, String?)] = []) -> URL {
        var text = base.absoluteString
        for segment in segments { text += "/" + PercentEncoding.strict(segment) }
        let pairs = query.compactMap { name, value in value.map { "\(PercentEncoding.strict(name))=\(PercentEncoding.strict($0))" } }
        if !pairs.isEmpty { text += "?" + pairs.joined(separator: "&") }
        return URL(string: text)!
    }

    public static func get(_ base: URL, _ segments: [String], query: [(String, String?)] = []) -> GoogleRequest {
        GoogleRequest(method: "GET", url: url(base, segments, query: query), kind: .read)
    }

    public static func json<Body: Encodable>(_ method: String, _ base: URL, _ segments: [String], query: [(String, String?)] = [],
                                             body: Body, kind: Kind = .write) -> GoogleRequest {
        let data = (try? GoogleJSON.encoder.encode(body)) ?? Data("{}".utf8)
        return GoogleRequest(method: method, url: url(base, segments, query: query), body: data, contentType: "application/json", kind: kind)
    }

    public static func bodiless(_ method: String, _ base: URL, _ segments: [String], query: [(String, String?)] = [], kind: Kind = .write) -> GoogleRequest {
        GoogleRequest(method: method, url: url(base, segments, query: query), kind: kind)
    }

    /// Query value for a name (tests).
    public func queryValue(_ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    public var path: String { URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path }
}

/// Gate consulted before every write / send (the app wires it to Settings; tests and smoke disable sends).
public struct WriteGate: Sendable {
    public var allowWrites: @Sendable () -> Bool
    public var allowSend: @Sendable () -> Bool

    public init(allowWrites: @escaping @Sendable () -> Bool, allowSend: @escaping @Sendable () -> Bool) {
        self.allowWrites = allowWrites
        self.allowSend = allowSend
    }

    public static let open = WriteGate(allowWrites: { true }, allowSend: { true })
    public static let readOnly = WriteGate(allowWrites: { false }, allowSend: { false })
    /// Writes allowed, sending never (tests, smoke, fixture mode).
    public static let noSend = WriteGate(allowWrites: { true }, allowSend: { false })
}

public struct RetryPolicy: Sendable {
    public var maxAttempts: Int
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval

    public init(maxAttempts: Int = 4, baseDelay: TimeInterval = 0.5, maxDelay: TimeInterval = 16) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// Exponential backoff with ±20 % jitter; `Retry-After` wins when present.
    public func delay(attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter { return min(maxDelay, max(0, retryAfter)) }
        let exponential = min(maxDelay, baseDelay * pow(2, Double(attempt - 1)))
        return exponential * Double.random(in: 0.8...1.2)
    }
}

/// Any list response with a `nextPageToken`.
public protocol GooglePage: Decodable, Sendable {
    associatedtype Item: Sendable
    var pageItems: [Item] { get }
    var nextPageToken: String? { get }
}

/// Authenticated REST client for one Google account: bearer tokens from `AccountTokenStore` (refresh + one retry on
/// 401), retries with backoff on 429 / 5xx, pagination, the write/send gate, and Google's error envelope → `ThubanError`.
public actor GoogleClient {
    public nonisolated let accountID: String
    private let tokens: AccountTokenStore
    private let session: URLSession
    private let gate: WriteGate
    private let retry: RetryPolicy
    private let sleep: @Sendable (TimeInterval) async -> Void

    public init(accountID: String, tokens: AccountTokenStore, session: URLSession = .shared, gate: WriteGate = .open,
                retry: RetryPolicy = RetryPolicy(),
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.accountID = accountID.lowercased()
        self.tokens = tokens
        self.session = session
        self.gate = gate
        self.retry = retry
        self.sleep = sleep
    }

    /// Performs the request; returns the body.
    @discardableResult
    public func data(_ request: GoogleRequest) async throws -> Data {
        switch request.kind {
        case .read: break
        case .write: guard gate.allowWrites() else { throw ThubanError.writesDisabled }
        case .send:
            guard gate.allowWrites() else { throw ThubanError.writesDisabled }
            guard gate.allowSend() else { throw ThubanError.sendDisabled }
        }
        var attempt = 0
        var refreshedAfter401 = false
        while true {
            attempt += 1
            let token = try await tokens.accessToken(for: accountID)
            var urlRequest = URLRequest(url: request.url)
            urlRequest.httpMethod = request.method
            urlRequest.httpBody = request.body
            urlRequest.timeoutInterval = 60
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            if let contentType = request.contentType { urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type") }

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch {
                if let thuban = error as? ThubanError { throw thuban }
                if request.kind == .read, attempt < retry.maxAttempts, Self.isTransient(error) {
                    await sleep(retry.delay(attempt: attempt, retryAfter: nil))
                    continue
                }
                throw ThubanError.network(error.localizedDescription)
            }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if (200..<300).contains(status) { return data }

            let envelope = GoogleErrorEnvelope.parse(data)
            if status == 401, !refreshedAfter401 {
                refreshedAfter401 = true
                _ = try await tokens.accessToken(for: accountID, forceRefresh: true)
                attempt -= 1
                continue
            }
            if attempt < retry.maxAttempts, Self.shouldRetry(status: status, reason: envelope?.reason, request: request) {
                let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                await sleep(retry.delay(attempt: attempt, retryAfter: retryAfter))
                continue
            }
            throw ThubanError.http(status: status, message: envelope?.message ?? HTTPURLResponse.localizedString(forStatusCode: status),
                                   reason: envelope?.reason)
        }
    }

    public func decode<T: Decodable>(_ type: T.Type, _ request: GoogleRequest) async throws -> T {
        let body = try await data(request)
        do { return try GoogleJSON.decoder.decode(T.self, from: body) } catch {
            throw ThubanError.decoding("\(T.self): \(error)")
        }
    }

    /// Follows `nextPageToken` until exhausted (or `limit` items). `make(pageToken)` builds each page's request.
    public func paginate<Page: GooglePage>(_ type: Page.Type, limit: Int = .max, _ make: (String?) -> GoogleRequest) async throws -> [Page.Item] {
        var items: [Page.Item] = []
        var token: String?
        var pages = 0
        repeat {
            let page = try await decode(Page.self, make(token))
            items.append(contentsOf: page.pageItems)
            token = page.nextPageToken
            pages += 1
        } while token != nil && items.count < limit && pages < 200
        return items.count > limit ? Array(items.prefix(limit)) : items
    }

    static func shouldRetry(status: Int, reason: String?, request: GoogleRequest) -> Bool {
        let rateLimited = status == 429 || (status == 403 && (reason == "rateLimitExceeded" || reason == "userRateLimitExceeded"))
        if rateLimited { return true }
        // A 5xx may still have done the work: never resend mail or repeat an insert (duplicate event / draft / filter).
        guard request.isIdempotent else { return false }
        return [500, 502, 503, 504].contains(status)
    }

    static func isTransient(_ error: Error) -> Bool {
        guard let url = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet].contains(url.code)
    }
}
