import Foundation
import ThubanDeskCore

/// States the other walks never reach (lead): no account linked (the real ConnectPrompt path, not the Settings
/// preview), offline after a failed refresh, an empty inbox and an empty day. The fixture data is swapped in
/// memory only (nothing is written anywhere) and put back at the end.
enum StateSmokeScenes {
    @MainActor private static var original: FixtureWorld?

    static let scenes: [SmokeScene] = [
        SmokeScene("59z-no-accounts-calendar") { app in
            app.pendingConfirmation = nil
            app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            app.smokeHideAccounts(true)
            app.select(.calendar)
        },
        SmokeScene("59z-no-accounts-mail") { app in app.select(.mail) },
        SmokeScene("59z-no-accounts-today") { app in app.select(.today) },
        SmokeScene("68-offline-mail") { app in
            app.smokeHideAccounts(false)
            app.select(.mail)
            app.smokeSetSyncError("The Internet connection appears to be offline.", account: SampleData.primaryEmail)
        },
        SmokeScene("69-empty-inbox", settle: 2.0) { app in
            app.smokeSetSyncError(nil, account: SampleData.primaryEmail)
            guard let fixture = app.fixture else { return }
            let world = fixture.snapshot
            original = world
            var empty = world
            for (account, threads) in empty.threads {
                empty.threads[account] = threads.map { thread in
                    var thread = thread
                    thread.messages = thread.messages?.map { message in
                        var message = message
                        message.labelIds = message.labelIds?.filter { $0 != GmailSystemLabel.inbox }
                        return message
                    }
                    return thread
                }
            }
            fixture.replaceWorld(empty)
            app.mail.scope = MailScope()
            app.mail.selection = nil
            app.select(.mail)
            await app.refreshAll()
        },
        SmokeScene("69b-today-empty", settle: 2.0) { app in
            guard let fixture = app.fixture, let original else { return }
            var noEvents = original
            noEvents.events = noEvents.events.mapValues { $0.mapValues { _ in [] } }
            fixture.replaceWorld(noEvents)
            app.select(.today)
            await app.refreshAll()
        },
        SmokeScene("69c-restored-calendar", settle: 2.0) { app in
            if let fixture = app.fixture, let original { fixture.replaceWorld(original) }
            original = nil
            app.select(.calendar)
            app.calendar.ui.goToday()
            await app.refreshAll()
        },
    ]
}
