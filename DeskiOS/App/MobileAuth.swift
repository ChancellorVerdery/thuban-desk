import AuthenticationServices
import Foundation
import ThubanDeskCore
import UIKit

/// The Google iOS OAuth client this build was made with (`GOOGLE_IOS_CLIENT_ID` in DeskiOS/Config/Secrets.xcconfig →
/// Info.plist `GoogleIOSClientID`, whose reversed form is registered in `CFBundleURLTypes`).
enum MobileGoogleClient {
    static var bundledClientID: String? {
        GoogleMobileRedirect.clientID(fromBuildSetting: Bundle.main.object(forInfoDictionaryKey: "GoogleIOSClientID") as? String)
    }

    static var bundledConfig: GoogleClientConfig? {
        bundledClientID.map { GoogleClientConfig(clientID: $0) }
    }

    /// True when the app's Info.plist registers the redirect scheme for `clientID`.
    static func isRegistered(_ clientID: String) -> Bool {
        guard let scheme = GoogleMobileRedirect.scheme(forClientID: clientID) else { return false }
        return GoogleMobileRedirect.isRegistered(scheme: scheme, urlTypes: Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
    }

    static let missingMessage = """
    No Google iOS client ID yet. Create an OAuth client of type iOS (bundle ID org.thuban.desk.ios) in Google Cloud \
    Console, put its ID in DeskiOS/Config/Secrets.xcconfig as GOOGLE_IOS_CLIENT_ID and rebuild — the build registers \
    the redirect URL scheme — or paste the ID in Settings → Google sign-in.
    """
}

/// Runs one `ASWebAuthenticationSession` (ephemeral: no shared Safari cookies) and returns the callback URL.
@MainActor
enum WebAuthSession {
    private static var current: ASWebAuthenticationSession?
    private static let anchor = AnchorProvider()

    static func run(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) { callback, error in
                Task { @MainActor in current = nil }
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: ThubanError.oauth(error?.localizedDescription ?? "Sign-in did not finish."))
                }
            }
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = true
            current = session
            if !session.start() {
                current = nil
                continuation.resume(throwing: ThubanError.oauth("Could not open Google sign-in."))
            }
        }
    }

    private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            MainActor.assumeIsolated {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
            }
        }
    }
}
