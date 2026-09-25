import XCTest
@testable import ThubanDeskCore

/// The iOS sign-in pieces (reversed-client-ID redirect, callback parsing, PKCE exchange without a secret).
/// URLProtocol stubs only — nothing reaches Google.
final class MobileSignInTests: XCTestCase {
    let clientID = "1234-abcd.apps.googleusercontent.com"

    func testReversedClientIDScheme() {
        XCTAssertEqual(GoogleMobileRedirect.scheme(forClientID: clientID), "com.googleusercontent.apps.1234-abcd")
        XCTAssertEqual(GoogleMobileRedirect.redirectURI(forClientID: clientID)?.absoluteString,
                       "com.googleusercontent.apps.1234-abcd:/oauth2redirect")
        XCTAssertNil(GoogleMobileRedirect.scheme(forClientID: "not-a-client"))
        XCTAssertNil(GoogleMobileRedirect.scheme(forClientID: ".apps.googleusercontent.com"))
        XCTAssertNil(GoogleMobileRedirect.scheme(forClientID: "a b.apps.googleusercontent.com"))
    }

    func testClientIDFromBuildSetting() {
        XCTAssertNil(GoogleMobileRedirect.clientID(fromBuildSetting: nil))
        XCTAssertNil(GoogleMobileRedirect.clientID(fromBuildSetting: ""))
        XCTAssertNil(GoogleMobileRedirect.clientID(fromBuildSetting: "  "))
        XCTAssertNil(GoogleMobileRedirect.clientID(fromBuildSetting: "$(GOOGLE_IOS_CLIENT_ID)"))
        XCTAssertEqual(GoogleMobileRedirect.clientID(fromBuildSetting: "1234-abcd"), clientID)
        XCTAssertEqual(GoogleMobileRedirect.clientID(fromBuildSetting: " \(clientID) "), clientID)
    }

    func testSchemeRegistrationCheck() {
        let types: [[String: Any]] = [["CFBundleURLSchemes": ["com.googleusercontent.apps.1234-ABCD"]]]
        XCTAssertTrue(GoogleMobileRedirect.isRegistered(scheme: "com.googleusercontent.apps.1234-abcd", urlTypes: types))
        XCTAssertFalse(GoogleMobileRedirect.isRegistered(scheme: "com.googleusercontent.apps.9", urlTypes: types))
        XCTAssertFalse(GoogleMobileRedirect.isRegistered(scheme: "x", urlTypes: nil))
    }

    func testRequestUsesTheCustomSchemeRedirectAndPKCE() throws {
        let flow = GoogleMobileSignIn(oauth: GoogleOAuth(config: GoogleClientConfig(clientID: clientID)))
        let request = try flow.makeRequest(loginHint: "me@x.org", pkce: PKCE(verifier: "verifier"), state: "state1")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(request.scheme, "com.googleusercontent.apps.1234-abcd")
        XCTAssertEqual(items["redirect_uri"], "com.googleusercontent.apps.1234-abcd:/oauth2redirect")
        XCTAssertEqual(items["code_challenge"], PKCE(verifier: "verifier").challenge)
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["state"], "state1")
        XCTAssertEqual(items["login_hint"], "me@x.org")
        XCTAssertNil(items["client_secret"])
        let bad = GoogleMobileSignIn(oauth: GoogleOAuth(config: GoogleClientConfig(clientID: "desktop-id")))
        XCTAssertThrowsError(try bad.makeRequest())
    }

    func testCallbackParsing() throws {
        let flow = GoogleMobileSignIn(oauth: GoogleOAuth(config: GoogleClientConfig(clientID: clientID)))
        let request = try flow.makeRequest(pkce: PKCE(verifier: "v"), state: "s1")
        let ok = URL(string: "com.googleusercontent.apps.1234-abcd:/oauth2redirect?state=s1&code=4%2F0Ab&scope=email")!
        XCTAssertEqual(try GoogleMobileSignIn.code(from: ok, for: request), "4/0Ab")
        let wrongState = URL(string: "com.googleusercontent.apps.1234-abcd:/oauth2redirect?state=zz&code=c")!
        XCTAssertThrowsError(try GoogleMobileSignIn.code(from: wrongState, for: request))
        let denied = URL(string: "com.googleusercontent.apps.1234-abcd:/oauth2redirect?error=access_denied&state=s1")!
        XCTAssertThrowsError(try GoogleMobileSignIn.code(from: denied, for: request)) { error in
            XCTAssertTrue(error.localizedDescription.contains("declined"))
        }
        let otherScheme = URL(string: "evil:/oauth2redirect?state=s1&code=c")!
        XCTAssertThrowsError(try GoogleMobileSignIn.code(from: otherScheme, for: request))
        let noCode = URL(string: "com.googleusercontent.apps.1234-abcd:/oauth2redirect?state=s1")!
        XCTAssertThrowsError(try GoogleMobileSignIn.code(from: noCode, for: request))
    }

    func testFinishExchangesWithoutAClientSecret() async throws {
        let claims = Base64URL.encode(json(["email": "Me@Example.com", "name": "Me"]))
        StubURLProtocol.reset { _ in
            (200, json(["access_token": "a1", "expires_in": 3600, "refresh_token": "r1", "id_token": "h.\(claims).s"]), [:])
        }
        let flow = GoogleMobileSignIn(oauth: GoogleOAuth(config: GoogleClientConfig(clientID: clientID), session: StubURLProtocol.session()))
        let request = try flow.makeRequest(pkce: PKCE(verifier: "ver"), state: "s1")
        let callback = URL(string: "com.googleusercontent.apps.1234-abcd:/oauth2redirect?state=s1&code=abc")!
        let account = try await flow.finish(callback: callback, request: request)
        XCTAssertEqual(account.id, "me@example.com")
        XCTAssertEqual(account.refreshToken, "r1")
        let sent = try XCTUnwrap(StubURLProtocol.recorded.first)
        XCTAssertTrue(sent.bodyText.contains("code=abc"))
        XCTAssertTrue(sent.bodyText.contains("code_verifier=ver"))
        XCTAssertTrue(sent.bodyText.contains("redirect_uri=com.googleusercontent.apps.1234-abcd%3A%2Foauth2redirect"))
        XCTAssertFalse(sent.bodyText.contains("client_secret"))
    }
}
