import Foundation

/// Every error the core throws. `parse` / `store` are shared with the theme code copied from Thuban Study.
public enum ThubanError: Error, LocalizedError, Equatable, Sendable {
    case parse(String)
    case store(String)
    /// No OAuth client ID has been entered yet (Settings → Accounts).
    case missingClientID
    /// No Google account is linked, or the named account is not known.
    case notSignedIn(String?)
    /// Google answered `invalid_grant`: the refresh token was revoked or expired. The account is marked disconnected.
    case accountDisconnected(String)
    /// The OAuth flow failed or was cancelled (message is user-facing).
    case oauth(String)
    /// Settings → "Allow changes" is off, or the call is a send and sending is disabled for this client.
    case writesDisabled
    case sendDisabled
    /// Google refused the call (403 insufficient permissions, 404, …). `reason` is Google's `errors[0].reason` when present.
    case http(status: Int, message: String, reason: String?)
    case network(String)
    case decoding(String)
    /// Raised by the fixture backend for any request it does not serve (so nothing can leak to the network).
    case blocked(String)

    public var errorDescription: String? {
        switch self {
        case .parse(let message), .store(let message), .network(let message), .decoding(let message), .oauth(let message):
            return message
        case .missingClientID: return "Enter your Google OAuth client ID in Settings → Accounts."
        case .notSignedIn(let email):
            if let email { return "\(email) is not signed in." }
            return "No Google account is linked. Add one in Settings → Accounts."
        case .accountDisconnected(let email): return "Google signed \(email) out. Sign in again in Settings → Accounts."
        case .writesDisabled: return "Changes are turned off in Settings."
        case .sendDisabled: return "Sending is disabled in this mode."
        case .http(let status, let message, _): return "Google returned \(status): \(message)"
        case .blocked(let message): return "Blocked: \(message)"
        }
    }

    /// 404 / 410: the item is gone (deleted elsewhere).
    public var isNotFound: Bool {
        if case .http(let status, _, _) = self { return status == 404 || status == 410 }
        return false
    }
}
