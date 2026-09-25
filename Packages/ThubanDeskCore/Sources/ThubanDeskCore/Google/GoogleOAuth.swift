import Foundation

/// The token endpoint's answer.
public struct TokenResponse: Decodable, Sendable, Equatable {
    public var accessToken: String
    public var expiresIn: Int?
    public var refreshToken: String?
    public var scope: String?
    public var tokenType: String?
    public var idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", expiresIn = "expires_in", refreshToken = "refresh_token", scope
        case tokenType = "token_type", idToken = "id_token"
    }

    public init(accessToken: String, expiresIn: Int? = 3599, refreshToken: String? = nil, scope: String? = nil, tokenType: String? = "Bearer", idToken: String? = nil) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.scope = scope
        self.tokenType = tokenType
        self.idToken = idToken
    }
}

/// Claims read from the `id_token` Google returns with `openid email`. The token arrives directly from Google's
/// token endpoint over TLS, so it is decoded without signature verification (as Google's installed-app guidance allows).
public struct IDTokenClaims: Decodable, Sendable, Equatable {
    public var email: String?
    public var emailVerified: Bool?
    public var name: String?
    public var sub: String?

    enum CodingKeys: String, CodingKey { case email, emailVerified = "email_verified", name, sub }

    public static func decode(_ jwt: String) -> IDTokenClaims? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2, let data = Base64URL.decode(String(parts[1])) else { return nil }
        return try? JSONDecoder().decode(IDTokenClaims.self, from: data)
    }
}

/// Google OAuth 2.0 for installed apps: authorization URL (PKCE, loopback redirect), code exchange, refresh, revoke.
public struct GoogleOAuth: Sendable {
    /// Thrown by `refresh` when Google answers `invalid_grant` (token revoked, expired, or password changed).
    public struct InvalidGrant: Error, Sendable, Equatable { public var description: String? }

    public var config: GoogleClientConfig
    public var session: URLSession

    public init(config: GoogleClientConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func authorizationURL(redirectURI: URL, pkce: PKCE, state: String, scopes: [String] = GoogleScopes.all, loginHint: String? = nil) -> URL {
        var components = URLComponents(url: GoogleEndpoints.authorize, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state),
            // Offline access + consent every time so Google always returns a refresh token.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent select_account"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
        ]
        if let loginHint { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        components.queryItems = items
        // URLComponents leaves '+' alone; encode it so Google does not read a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    public func exchange(code: String, verifier: String, redirectURI: URL) async throws -> TokenResponse {
        var form = [
            ("code", code), ("client_id", config.clientID), ("code_verifier", verifier),
            ("redirect_uri", redirectURI.absoluteString), ("grant_type", "authorization_code"),
        ]
        if let secret = config.clientSecret { form.append(("client_secret", secret)) }
        do {
            return try await postToken(form)
        } catch let grant as InvalidGrant {
            throw ThubanError.oauth("Google rejected the sign-in code\(grant.description.map { ": \($0)" } ?? ""). Try again.")
        }
    }

    /// Throws `InvalidGrant` when the refresh token is no longer valid.
    public func refresh(refreshToken: String) async throws -> TokenResponse {
        var form = [("client_id", config.clientID), ("refresh_token", refreshToken), ("grant_type", "refresh_token")]
        if let secret = config.clientSecret { form.append(("client_secret", secret)) }
        return try await postToken(form)
    }

    /// Best effort: revokes the refresh token when an account is removed.
    public func revoke(token: String) async {
        var request = URLRequest(url: GoogleEndpoints.revoke)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode([("token", token)]).utf8)
        _ = try? await session.data(for: request)
    }

    private func postToken(_ form: [(String, String)]) async throws -> TokenResponse {
        var request = URLRequest(url: GoogleEndpoints.token)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(form).utf8)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch {
            throw ThubanError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let envelope = GoogleErrorEnvelope.parse(data)
            if envelope?.oauthError == "invalid_grant" { throw InvalidGrant(description: envelope?.oauthDescription) }
            throw ThubanError.http(status: status, message: envelope?.message ?? "Token request failed", reason: envelope?.reason)
        }
        do { return try JSONDecoder().decode(TokenResponse.self, from: data) } catch {
            throw ThubanError.decoding("Token response: \(error.localizedDescription)")
        }
    }

    static func formEncode(_ pairs: [(String, String)]) -> String {
        pairs.map { "\(PercentEncoding.strict($0.0))=\(PercentEncoding.strict($0.1))" }.joined(separator: "&")
    }
}

enum PercentEncoding {
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Encodes everything but RFC 3986 unreserved characters (safe for path segments, query values and forms).
    static func strict(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }
}

/// The whole installed-app sign-in: loopback listener → system browser → code → tokens → account.
public struct GoogleSignIn: Sendable {
    public var oauth: GoogleOAuth
    public var openURL: @Sendable (URL) -> Void
    public var timeout: TimeInterval

    public init(oauth: GoogleOAuth, timeout: TimeInterval = 300, openURL: @escaping @Sendable (URL) -> Void) {
        self.oauth = oauth
        self.openURL = openURL
        self.timeout = timeout
    }

    public func run(loginHint: String? = nil, now: Date = Date()) async throws -> GoogleAccount {
        let receiver = LoopbackReceiver()
        let redirect = try await receiver.start()
        defer { receiver.stop() }
        let pkce = PKCE.generate()
        let state = PKCE.randomString(length: 32)
        receiver.expect(state: state)
        openURL(oauth.authorizationURL(redirectURI: redirect, pkce: pkce, state: state, loginHint: loginHint))
        let callback = try await receiver.waitForCallback(timeout: timeout)
        if let error = callback.error {
            throw ThubanError.oauth(error == "access_denied" ? "Sign-in was declined in the browser." : "Google sign-in failed: \(callback.errorDescription ?? error)")
        }
        guard callback.state == state else { throw ThubanError.oauth("Sign-in response did not match this request. Try again.") }
        guard let code = callback.code else { throw ThubanError.oauth("Google did not return a sign-in code.") }
        let tokens = try await oauth.exchange(code: code, verifier: pkce.verifier, redirectURI: redirect)
        return try Self.account(from: tokens, now: now)
    }

    /// Builds the account record from a code exchange (email from the id_token).
    public static func account(from tokens: TokenResponse, now: Date = Date()) throws -> GoogleAccount {
        guard let refresh = tokens.refreshToken else {
            throw ThubanError.oauth("Google did not return a refresh token. Remove Thuban Desk at myaccount.google.com/permissions and sign in again.")
        }
        guard let idToken = tokens.idToken, let claims = IDTokenClaims.decode(idToken), let email = claims.email else {
            throw ThubanError.oauth("Google did not say which account signed in (missing email scope).")
        }
        let scopes = tokens.scope?.split(separator: " ").map(String.init) ?? GoogleScopes.all
        return GoogleAccount(email: email, displayName: claims.name, linkedAt: now, refreshToken: refresh, accessToken: tokens.accessToken,
                             accessTokenExpiry: now.addingTimeInterval(TimeInterval(tokens.expiresIn ?? 3599)), scopes: scopes)
    }
}
