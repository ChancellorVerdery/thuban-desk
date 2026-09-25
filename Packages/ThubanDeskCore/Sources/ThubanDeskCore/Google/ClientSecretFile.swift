import Foundation

/// The JSON Google Cloud Console offers when a Desktop OAuth client is created ("Download JSON",
/// `client_secret_….json`): `{"installed": {"client_id": …, "client_secret": …, …}}`. Settings → Accounts can import
/// it instead of copying two strings by hand.
public enum ClientSecretFile {
    struct File: Decodable {
        struct Client: Decodable {
            var client_id: String
            var client_secret: String?
        }
        var installed: Client?
        var web: Client?
    }

    /// The client in a downloaded file (validated like a typed-in ID). A "Web application" client is refused: the
    /// loopback sign-in needs a Desktop client.
    public static func parse(_ data: Data) throws -> GoogleClientConfig {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            throw ThubanError.oauth("That file is not a Google OAuth client file (client_secret_….json).")
        }
        guard let client = file.installed else {
            if file.web != nil { throw ThubanError.oauth("That is a “Web application” client. Create a “Desktop app” client instead.") }
            throw ThubanError.oauth("That file does not contain a Desktop OAuth client.")
        }
        return try GoogleClientConfig.normalized(clientID: client.client_id, clientSecret: client.client_secret)
    }
}
