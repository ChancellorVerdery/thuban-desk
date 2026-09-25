import Foundation

/// Mail screens for the smoke walk (owned by the Mail engineer). Names sort the PNGs: 30–39.
enum MailSmokeScenes {
    static let scenes: [SmokeScene] = [
        SmokeScene("30-mail-inbox") { app in app.select(.mail) },
    ]
}
