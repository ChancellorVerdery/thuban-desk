import Foundation
import ThubanDeskCore

/// Settings screens for the smoke walk (owned by the Today + Settings engineer). Names sort the PNGs: 50–59.
enum SettingsSmokeScenes {
    private static let light = ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil)
    private static let dark = ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil)

    static let scenes: [SmokeScene] = [
        SmokeScene("50-settings-accounts") { app in
            app.setThemeSelection(light)
            app.openSettings(.accounts)
        },
        SmokeScene("51-settings-accounts-dark") { app in
            app.setThemeSelection(dark)
            app.openSettings(.accounts)
        },
        // The setup guide sheet (captured, then closed by the next scene).
        SmokeScene("52-settings-setup-guide", capture: .sheet) { app in
            app.setThemeSelection(light)
            app.openSettings(.accounts)
            app.showSetupGuide()
        },
        SmokeScene("53-settings-calendar") { app in
            DeskIntents.shared.showSetupGuide = false
            app.openSettings(.calendar)
        },
        SmokeScene("54-settings-mail") { app in app.openSettings(.mail) },
        SmokeScene("55-settings-filters") { app in app.openSettings(.filters) },
        SmokeScene("56-settings-appearance") { app in app.openSettings(.appearance) },
        SmokeScene("57-settings-appearance-dark") { app in
            app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: "emerald", custom: nil))
            app.openSettings(.appearance)
        },
        SmokeScene("58-settings-about") { app in
            app.setThemeSelection(light)
            app.openSettings(.about)
        },
        // First-run page (shown for real only before an account is linked).
        SmokeScene("59-onboarding") { app in
            DeskIntents.shared.previewOnboarding = true
            app.openSettings(.accounts)
        },
        SmokeScene("59b-onboarding-dark") { app in
            app.setThemeSelection(dark)
        },
        SmokeScene("59c-settings-notifications") { app in
            DeskIntents.shared.previewOnboarding = false
            app.setThemeSelection(light)
            app.openSettings(.notifications)
        },
    ]
}
