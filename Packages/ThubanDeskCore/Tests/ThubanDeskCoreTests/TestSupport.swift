import Foundation
import XCTest
@testable import ThubanDeskCore

/// URLProtocol stub: every request of a stub session goes to `handler`; nothing reaches the network.
final class StubURLProtocol: URLProtocol {
    struct Recorded {
        var method: String
        var url: URL
        var headers: [String: String]
        var body: Data?
        var bodyText: String { String(decoding: body ?? Data(), as: UTF8.self) }
    }

    nonisolated(unsafe) static var handler: ((Recorded) -> (Int, Data, [String: String]))?
    nonisolated(unsafe) static var requests: [Recorded] = []
    static let lock = NSLock()

    static func reset(_ handler: @escaping (Recorded) -> (Int, Data, [String: String])) {
        lock.withLock {
            self.handler = handler
            requests = []
        }
    }

    static var recorded: [Recorded] { lock.withLock { requests } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(FixtureURLProtocol.read)
        let recorded = Recorded(method: request.httpMethod ?? "GET", url: request.url!, headers: request.allHTTPHeaderFields ?? [:], body: body)
        let handler = Self.lock.withLock { () -> ((Recorded) -> (Int, Data, [String: String]))? in
            Self.requests.append(recorded)
            return Self.handler
        }
        let (status, data, headers) = handler?(recorded) ?? (599, Data(), [:])
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

let newYork = TimeZone(identifier: "America/New_York")!

func fixtureData(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// A local time in New York.
func ny(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    Calendar.gregorian(newYork).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

/// Credentials with one signed-in account whose access token is still fresh.
func signedInFile(email: String = "me@example.com", fresh: Bool = true, now: Date = Date()) -> CredentialsFile {
    CredentialsFile(client: GoogleClientConfig(clientID: "123.apps.googleusercontent.com", clientSecret: "shh"),
                    accounts: [GoogleAccount(email: email, linkedAt: now.addingTimeInterval(-100), refreshToken: "refresh-1",
                                             accessToken: fresh ? "access-1" : "stale", accessTokenExpiry: now.addingTimeInterval(fresh ? 3000 : -10))])
}

/// Captures what the token store persisted.
final class PersistBox: @unchecked Sendable {
    private let lock = NSLock()
    private var saved: [CredentialsFile] = []
    func append(_ file: CredentialsFile) { lock.withLock { saved.append(file) } }
    var last: CredentialsFile? { lock.withLock { saved.last } }
    var count: Int { lock.withLock { saved.count } }
}

/// A fixture-backed client for an account of the sample world.
func fixtureClient(_ backend: FixtureGoogle, account: String, gate: WriteGate = .noSend) -> GoogleClient {
    let world = backend.snapshot
    let tokens = AccountTokenStore(file: CredentialsFile(client: world.client, accounts: world.accounts), session: backend.makeSession(), persist: { _ in })
    return GoogleClient(accountID: account, tokens: tokens, session: backend.makeSession(), gate: gate, retry: RetryPolicy(maxAttempts: 1), sleep: { _ in })
}

/// Fixed "now" matching the design: Thursday, September 24, 2026, 2:40 PM in New York.
let designNow = ny(2026, 9, 24, 14, 40)
