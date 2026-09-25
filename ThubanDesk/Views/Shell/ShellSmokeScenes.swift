import Foundation
import ThubanDeskCore

/// Shell-level scenes (lead): the confirmation sheet and a dark-mode pass. Names: 10–19 and 90–99.
enum ShellSmokeScenes {
    static let first: [SmokeScene] = [
        SmokeScene("10-shell-calendar") { app in app.select(.calendar) },
    ]

    static let last: [SmokeScene] = [
        // The sheet is shown and then cancelled by the harness — `run()` is never called.
        SmokeScene("90-confirm-sheet", capture: .sheet) { app in
            app.select(.mail)
            app.confirm(ConfirmRequest(title: "Send this message?", message: "To Priya Shah · Re: Interview confirmed: Friday 3:00 PM. It is sent from alex.morgan@example.com.",
                                       actionLabel: "Send", workingLabel: "Sending…") { _ in })
        },
        SmokeScene("95-dark-mail") { app in
            app.pendingConfirmation = nil
            app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
            app.select(.mail)
        },
    ]
}
