import Foundation

/// Google's redirect for an **iOS** OAuth client: the reversed client ID as a custom URL scheme
/// (`com.googleusercontent.apps.<id>:/oauth2redirect`). The iOS app registers that scheme in its Info.plist
/// (`CFBundleURLTypes`, filled from the `GOOGLE_IOS_CLIENT_ID` build setting) and hands it to
/// `ASWebAuthenticationSession` as the callback scheme. Platform-neutral so it is unit-tested on macOS.
public enum GoogleMobileRedirect {
    public static let clientSuffix = ".apps.googleusercontent.com"
    public static let schemePrefix = "com.googleusercontent.apps."
    public static let path = "/oauth2redirect"

    /// The part before `.apps.googleusercontent.com` ("123-abc"); nil when `clientID` is not a Google client ID.
    public static func clientPrefix(_ clientID: String) -> String? {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.hasSuffix(clientSuffix) else { return nil }
        let prefix = String(id.dropLast(clientSuffix.count))
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return prefix
    }

    /// "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc".
    public static func scheme(forClientID clientID: String) -> String? {
        clientPrefix(clientID).map { schemePrefix + $0 }
    }

    /// "com.googleusercontent.apps.123-abc:/oauth2redirect".
    public static func redirectURI(forClientID clientID: String) -> URL? {
        scheme(forClientID: clientID).flatMap { URL(string: "\($0):\(path)") }
    }

    /// The client ID from the `GOOGLE_IOS_CLIENT_ID` build setting (Info.plist `GoogleIOSClientID`). Accepts the full
    /// ID or only its prefix ("123-abc"); empty, unexpanded (`$(…)`) or malformed values give nil.
    public static func clientID(fromBuildSetting raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, !text.contains("$(") else { return nil }
        let full = text.hasSuffix(clientSuffix) ? text : text + clientSuffix
        return clientPrefix(full) == nil ? nil : full
    }

    /// True when the app's `CFBundleURLTypes` registers `scheme` (case-insensitive, as iOS compares schemes).
    public static func isRegistered(scheme: String, urlTypes: [[String: Any]]?) -> Bool {
        let wanted = scheme.lowercased()
        return (urlTypes ?? []).contains { type in
            ((type["CFBundleURLSchemes"] as? [String]) ?? []).contains { $0.lowercased() == wanted }
        }
    }
}

/// The iOS sign-in, minus the browser sheet: `makeRequest` builds the authorization URL (PKCE S256, `state`, no
/// client secret), the app shows it in `ASWebAuthenticationSession` with `request.scheme` as the callback scheme,
/// and `finish` checks the callback and exchanges the code for tokens.
public struct GoogleMobileSignIn: Sendable {
    public struct Request: Sendable, Equatable {
        public var url: URL
        public var redirectURI: URL
        /// The callback URL scheme for ASWebAuthenticationSession.
        public var scheme: String
        public var pkce: PKCE
        public var state: String
    }

    public var oauth: GoogleOAuth

    public init(oauth: GoogleOAuth) {
        self.oauth = oauth
    }

    public func makeRequest(loginHint: String? = nil, pkce: PKCE = .generate(), state: String = PKCE.randomString(length: 32)) throws -> Request {
        guard let scheme = GoogleMobileRedirect.scheme(forClientID: oauth.config.clientID),
              let redirect = GoogleMobileRedirect.redirectURI(forClientID: oauth.config.clientID) else {
            throw ThubanError.oauth("That is not a Google iOS client ID (it ends in .apps.googleusercontent.com).")
        }
        let url = oauth.authorizationURL(redirectURI: redirect, pkce: pkce, state: state, loginHint: loginHint)
        return Request(url: url, redirectURI: redirect, scheme: scheme, pkce: pkce, state: state)
    }

    /// The authorization code from the callback URL; throws for a denial, a foreign scheme or a mismatched `state`.
    public static func code(from callback: URL, for request: Request) throws -> String {
        guard callback.scheme?.lowercased() == request.scheme.lowercased() else {
            throw ThubanError.oauth("Sign-in returned to an unexpected address. Try again.")
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw ThubanError.oauth(error == "access_denied" ? "Sign-in was declined." : "Google sign-in failed: \(value("error_description") ?? error)")
        }
        guard value("state") == request.state else { throw ThubanError.oauth("Sign-in response did not match this request. Try again.") }
        guard let code = value("code"), !code.isEmpty else { throw ThubanError.oauth("Google did not return a sign-in code.") }
        return code
    }

    /// Exchanges the callback's code (PKCE verifier, no client secret) and builds the account record.
    public func finish(callback: URL, request: Request, now: Date = Date()) async throws -> GoogleAccount {
        let code = try Self.code(from: callback, for: request)
        let tokens = try await oauth.exchange(code: code, verifier: request.pkce.verifier, redirectURI: request.redirectURI)
        return try GoogleSignIn.account(from: tokens, now: now)
    }
}
