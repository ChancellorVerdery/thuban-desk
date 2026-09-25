import Foundation

/// Settings screens for the smoke walk (owned by the Today + Settings engineer). Names sort the PNGs: 50–59.
enum SettingsSmokeScenes {
    static let scenes: [SmokeScene] = [
        SmokeScene("50-settings-accounts") { app in app.openSettings(.accounts) },
        SmokeScene("51-settings-appearance") { app in app.openSettings(.appearance) },
    ]
}
