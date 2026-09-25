import Network
import XCTest
@testable import ThubanDeskCore

final class OAuthTests: XCTestCase {
    func testPKCEMatchesRFC7636Example() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let fresh = PKCE.generate()
        XCTAssertEqual(fresh.verifier.count, 64)
        XCTAssertNotEqual(fresh.verifier, PKCE.generate().verifier)
    }

    func testAuthorizationURL() throws {
        let oauth = GoogleOAuth(config: GoogleClientConfig(clientID: "123.apps.googleusercontent.com"))
        let url = oauth.authorizationURL(redirectURI: URL(string: "http://127.0.0.1:54321")!, pkce: PKCE(verifier: "v"), state: "st+ate", loginHint: "me@x.org")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "accounts.google.com")
        XCTAssertEqual(items["client_id"], "123.apps.googleusercontent.com")
        XCTAssertEqual(items["redirect_uri"], "http://127.0.0.1:54321")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["access_type"], "offline")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["state"], "st+ate")
        XCTAssertEqual(items["login_hint"], "me@x.org")
        let scopes = Set((items["scope"] ?? "").split(separator: " ").map(String.init))
        XCTAssertEqual(scopes, Set(GoogleScopes.all))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/gmail.settings.basic"))
    }

    func testClientIDValidation() throws {
        XCTAssertThrowsError(try GoogleClientConfig.normalized(clientID: "  ", clientSecret: nil))
        XCTAssertThrowsError(try GoogleClientConfig.normalized(clientID: "not-an-id", clientSecret: nil))
        let config = try GoogleClientConfig.normalized(clientID: " 123-abc.apps.googleusercontent.com \n", clientSecret: "  ")
        XCTAssertEqual(config.clientID, "123-abc.apps.googleusercontent.com")
        XCTAssertNil(config.clientSecret)
    }

    func testCodeExchangeBuildsTheAccountFromTheIDToken() async throws {
        let claims = Base64URL.encode(json(["email": "Me@Example.com", "name": "Me Person", "email_verified": true]))
        StubURLProtocol.reset { request in
            (200, json(["access_token": "a1", "expires_in": 3600, "refresh_token": "r1", "scope": GoogleScopes.all.joined(separator: " "),
                        "id_token": "h.\(claims).s"]), [:])
        }
        let oauth = GoogleOAuth(config: GoogleClientConfig(clientID: "c.apps.googleusercontent.com", clientSecret: "sec"), session: StubURLProtocol.session())
        let tokens = try await oauth.exchange(code: "code/1", verifier: "ver", redirectURI: URL(string: "http://127.0.0.1:5000")!)
        let request = try XCTUnwrap(StubURLProtocol.recorded.first)
        XCTAssertEqual(request.url.absoluteString, "https://oauth2.googleapis.com/token")
        XCTAssertTrue(request.bodyText.contains("code=code%2F1"))
        XCTAssertTrue(request.bodyText.contains("code_verifier=ver"))
        XCTAssertTrue(request.bodyText.contains("client_secret=sec"))
        XCTAssertTrue(request.bodyText.contains("grant_type=authorization_code"))
        let now = Date()
        let account = try GoogleSignIn.account(from: tokens, now: now)
        XCTAssertEqual(account.id, "me@example.com")
        XCTAssertEqual(account.displayName, "Me Person")
        XCTAssertEqual(account.refreshToken, "r1")
        XCTAssertTrue(account.hasFreshAccessToken(now: now))
        XCTAssertThrowsError(try GoogleSignIn.account(from: TokenResponse(accessToken: "a", refreshToken: nil, idToken: "h.\(claims).s")))
    }

    func testRefreshIsSharedByConcurrentCallersAndPersisted() async throws {
        StubURLProtocol.reset { _ in
            Thread.sleep(forTimeInterval: 0.05)
            return (200, json(["access_token": "new-access", "expires_in": 3600, "refresh_token": "rotated"]), [:])
        }
        let box = PersistBox()
        let store = AccountTokenStore(file: signedInFile(fresh: false), session: StubURLProtocol.session(), persist: { box.append($0) })
        async let a = store.accessToken(for: "me@example.com")
        async let b = store.accessToken(for: "ME@example.com")
        let tokens = try await [a, b]
        XCTAssertEqual(tokens, ["new-access", "new-access"])
        XCTAssertEqual(StubURLProtocol.recorded.count, 1, "one refresh for both callers")
        XCTAssertTrue(StubURLProtocol.recorded[0].bodyText.contains("grant_type=refresh_token"))
        XCTAssertTrue(StubURLProtocol.recorded[0].bodyText.contains("refresh_token=refresh-1"))
        XCTAssertEqual(box.last?.accounts.first?.refreshToken, "rotated")
        XCTAssertEqual(box.last?.accounts.first?.accessToken, "new-access")
        // Fresh now: no second request.
        _ = try await store.accessToken(for: "me@example.com")
        XCTAssertEqual(StubURLProtocol.recorded.count, 1)
    }

    func testInvalidGrantDisconnectsTheAccountCleanly() async throws {
        StubURLProtocol.reset { _ in (400, json(["error": "invalid_grant", "error_description": "Token has been expired or revoked."]), [:]) }
        let box = PersistBox()
        let store = AccountTokenStore(file: signedInFile(fresh: false), session: StubURLProtocol.session(), persist: { box.append($0) })
        do {
            _ = try await store.accessToken(for: "me@example.com")
            XCTFail("should throw")
        } catch let error as ThubanError {
            XCTAssertEqual(error, .accountDisconnected("me@example.com"))
        }
        let saved = try XCTUnwrap(box.last?.accounts.first)
        XCTAssertTrue(saved.disconnected)
        XCTAssertNil(saved.refreshToken)
        XCTAssertNil(saved.accessToken)
        // Later calls fail fast without the network.
        let before = StubURLProtocol.recorded.count
        do { _ = try await store.accessToken(for: "me@example.com") } catch {}
        XCTAssertEqual(StubURLProtocol.recorded.count, before)
        // Signing in again clears the flag.
        try await store.upsert(GoogleAccount(email: "me@example.com", refreshToken: "r2", accessToken: "a2", accessTokenExpiry: Date().addingTimeInterval(3000)))
        let token = try await store.accessToken(for: "me@example.com")
        XCTAssertEqual(token, "a2")
    }

    func testPrimaryIsTheEarliestLinkedAndRelinkKeepsIt() {
        var file = CredentialsFile()
        file.upsert(GoogleAccount(email: "b@x.org", linkedAt: Date(timeIntervalSince1970: 200), refreshToken: "r"))
        file.upsert(GoogleAccount(email: "a@x.org", linkedAt: Date(timeIntervalSince1970: 100), refreshToken: "r"))
        XCTAssertEqual(file.primary?.email, "a@x.org")
        file.upsert(GoogleAccount(email: "A@x.org", linkedAt: Date(timeIntervalSince1970: 999), refreshToken: "r2"))
        XCTAssertEqual(file.primary?.email.lowercased(), "a@x.org")
        XCTAssertEqual(file.accounts.count, 2)
        file.remove("a@x.org")
        XCTAssertEqual(file.primary?.email, "b@x.org")
    }

    func testRemoveRevokesTheRefreshToken() async throws {
        StubURLProtocol.reset { _ in (200, Data(), [:]) }
        let store = AccountTokenStore(file: signedInFile(), session: StubURLProtocol.session(), persist: { _ in })
        try await store.remove("me@example.com")
        let accounts = await store.accounts
        XCTAssertTrue(accounts.isEmpty)
        XCTAssertEqual(StubURLProtocol.recorded.first?.url.absoluteString, "https://oauth2.googleapis.com/revoke")
        XCTAssertEqual(StubURLProtocol.recorded.first?.bodyText, "token=refresh-1")
    }

    func testLoopbackParsesCallbacks() {
        XCTAssertEqual(LoopbackReceiver.parse(target: "/?state=s1&code=4%2F0Ab&scope=email"), LoopbackReceiver.Callback(code: "4/0Ab", state: "s1"))
        XCTAssertEqual(LoopbackReceiver.parse(target: "/?error=access_denied&state=s")?.error, "access_denied")
        XCTAssertNil(LoopbackReceiver.parse(target: "/favicon.ico"))
    }

    /// Exercises the real listener on 127.0.0.1 (local only; no Google involved).
    func testLoopbackReceiverReceivesTheRedirect() async throws {
        let receiver = LoopbackReceiver()
        let redirect = try await receiver.start()
        XCTAssertEqual(redirect.host, "127.0.0.1")
        XCTAssertNotNil(redirect.port)
        let waiter = Task { try await receiver.waitForCallback(timeout: 10) }
        // A stray request first (ignored), then the real redirect.
        _ = try? await URLSession.shared.data(from: URL(string: "\(redirect.absoluteString)/favicon.ico")!)
        let (data, _) = try await URLSession.shared.data(from: URL(string: "\(redirect.absoluteString)/?code=abc&state=xyz")!)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("You can close this tab"))
        let callback = try await waiter.value
        XCTAssertEqual(callback.code, "abc")
        XCTAssertEqual(callback.state, "xyz")
        receiver.stop()
    }
}

final class GoogleClientTests: XCTestCase {
    func client(gate: WriteGate = .open, attempts: Int = 4, file: CredentialsFile = signedInFile()) -> GoogleClient {
        let tokens = AccountTokenStore(file: file, session: StubURLProtocol.session(), persist: { _ in })
        return GoogleClient(accountID: "me@example.com", tokens: tokens, session: StubURLProtocol.session(), gate: gate,
                            retry: RetryPolicy(maxAttempts: attempts, baseDelay: 0.001), sleep: { _ in })
    }

    func testRetriesRateLimitsAndServerErrors() async throws {
        var calls = 0
        StubURLProtocol.reset { _ in
            calls += 1
            switch calls {
            case 1: return (429, json(["error": ["code": 429, "message": "Rate Limit Exceeded"]]), ["Retry-After": "1"])
            case 2: return (403, json(["error": ["code": 403, "message": "User rate limit", "errors": [["reason": "userRateLimitExceeded"]]]]), [:])
            case 3: return (503, json(["error": ["code": 503, "message": "Backend Error"]]), [:])
            default: return (200, json(["emailAddress": "me@example.com"]), [:])
            }
        }
        let profile = try await client().gmailProfile()
        XCTAssertEqual(profile.emailAddress, "me@example.com")
        XCTAssertEqual(calls, 4)
        XCTAssertEqual(StubURLProtocol.recorded.first?.headers["Authorization"], "Bearer access-1")
    }

    func testGivesUpAfterMaxAttemptsWithGooglesMessage() async {
        StubURLProtocol.reset { _ in (500, json(["error": ["code": 500, "message": "Internal error", "errors": [["reason": "backendError"]]]]), [:]) }
        do {
            _ = try await client(attempts: 2).labels()
            XCTFail("should throw")
        } catch let error as ThubanError {
            XCTAssertEqual(error, .http(status: 500, message: "Internal error", reason: "backendError"))
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(StubURLProtocol.recorded.count, 2)
    }

    func testNotFoundIsNotRetried() async {
        StubURLProtocol.reset { _ in (404, json(["error": ["code": 404, "message": "Not Found"]]), [:]) }
        do { _ = try await client().event(calendarID: "c", eventID: "e") } catch let error as ThubanError { XCTAssertTrue(error.isNotFound) } catch {}
        XCTAssertEqual(StubURLProtocol.recorded.count, 1)
    }

    func testUnauthorizedRefreshesOnceAndRetries() async throws {
        var apiCalls = 0
        StubURLProtocol.reset { request in
            if request.url.host == "oauth2.googleapis.com" { return (200, json(["access_token": "access-2", "expires_in": 3600]), [:]) }
            apiCalls += 1
            if request.headers["Authorization"] == "Bearer access-1" { return (401, json(["error": ["code": 401, "message": "Invalid Credentials"]]), [:]) }
            return (200, json(["labels": [["id": "INBOX", "name": "INBOX", "type": "system"]]]), [:])
        }
        let labels = try await client().labels()
        XCTAssertEqual(labels.map(\.id), ["INBOX"])
        XCTAssertEqual(apiCalls, 2)
    }

    func testSendIsNeverRetriedOnServerErrors() async {
        StubURLProtocol.reset { _ in (503, json(["error": ["code": 503, "message": "Unavailable"]]), [:]) }
        let message = OutgoingMessage(from: EmailAddress("me@example.com"), to: [EmailAddress("x@y.org")], subject: "s", text: "t")
        do { try await client().send(message); XCTFail("should throw") } catch {}
        XCTAssertEqual(StubURLProtocol.recorded.count, 1)
    }

    func testWriteAndSendGates() async {
        StubURLProtocol.reset { _ in (200, json([:]), [:]) }
        let message = OutgoingMessage(from: EmailAddress("me@example.com"), to: [EmailAddress("x@y.org")], subject: "s", text: "t")
        do { try await client(gate: .noSend).send(message); XCTFail() } catch let error as ThubanError { XCTAssertEqual(error, .sendDisabled) } catch {}
        do { try await client(gate: .readOnly).perform(.archive, threadID: "t"); XCTFail() } catch let error as ThubanError { XCTAssertEqual(error, .writesDisabled) } catch {}
        XCTAssertTrue(StubURLProtocol.recorded.isEmpty, "gated calls never reach the network")
    }

    func testPaginationFollowsTokens() async throws {
        StubURLProtocol.reset { request in
            let token = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "pageToken" }?.value
            switch token {
            case nil: return (200, json(["items": [["id": "a"], ["id": "b"]], "nextPageToken": "p2"]), [:])
            case "p2": return (200, json(["items": [["id": "c"]], "nextPageToken": "p3"]), [:])
            default: return (200, json(["items": [["id": "d", "deleted": true]]]), [:])
            }
        }
        let calendars = try await client().calendarList()
        XCTAssertEqual(calendars.map(\.id), ["a", "b", "c"], "deleted entries are dropped")
        XCTAssertEqual(StubURLProtocol.recorded.count, 3)
    }

    func testDisconnectedAccountSurfacesWithoutNetwork() async {
        var file = signedInFile()
        file.update("me@example.com") { $0.disconnected = true }
        StubURLProtocol.reset { _ in (200, Data(), [:]) }
        do { _ = try await client(file: file).labels() } catch let error as ThubanError { XCTAssertEqual(error, .accountDisconnected("me@example.com")) } catch {}
        XCTAssertTrue(StubURLProtocol.recorded.isEmpty)
    }
}
