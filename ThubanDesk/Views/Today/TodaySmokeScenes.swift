import Foundation
import ThubanDeskCore

/// Today screens for the smoke walk (owned by the Today + Settings engineer). Names sort the PNGs: 40–49.
enum TodaySmokeScenes {
    static let scenes: [SmokeScene] = [
        SmokeScene("40-today", settle: 2.5) { app in
            app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            app.select(.today)
            // The needs-reply scan runs with the first refresh; make sure it has finished before the capture.
            if app.mail.needsReplyThreads.isEmpty { await app.mail.loadNeedsReply() }
        },
        SmokeScene("41-today-dark") { app in
            app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
            app.select(.today)
        },
        SmokeScene("42-today-cobalt-dark") { app in
            app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: "cobalt", custom: nil))
            app.select(.today)
        },
    ]
}
