import Foundation
import ThubanDeskCore

/// Cross-area scenes (lead, integration): search across Mail and Calendar, invitations Mail ↔ Calendar, and Today's
/// Reply / New event. Names: 60–69. Nothing is saved or sent; the editor and composer are closed at the end.
enum IntegrationSmokeScenes {
    static let scenes: [SmokeScene] = [
        SmokeScene("60-search-today", settle: 2.5) { app in
            app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            app.mail.compose = nil
            app.mail.scope = MailScope()
            app.mail.selection = nil
            app.calendar.ui.editor = nil
            app.calendar.ui.closePopover()
            app.select(.today)
            app.searchText = "interview"
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        },
        SmokeScene("61-search-mail", settle: 2.0) { app in
            app.select(.mail)
            try? await Task.sleep(nanoseconds: 900_000_000)
        },
        SmokeScene("62-search-calendar", settle: 2.0) { app in
            app.settings.calendarViewMode = .week
            app.select(.calendar)
            app.calendar.ui.goToday()
        },
        SmokeScene("63-invite-popover", settle: 2.0) { app in
            app.searchText = ""
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let invite = await invitation(app) else { return }
            app.openEvent(invite)
            try? await Task.sleep(nanoseconds: 600_000_000)
        },
        SmokeScene("64-invite-email", settle: 2.5) { app in
            guard let invite = await invitation(app) else { return }
            app.calendar.ui.closePopover()
            await app.openInvitationEmail(for: invite)
        },
        SmokeScene("65-today-reply", settle: 2.5) { app in
            app.select(.today)
            if app.mail.needsReplyThreads.isEmpty { await app.mail.loadNeedsReply() }
            guard let first = app.mail.needsReplyThreads.first?.summary.key else { return }
            app.requestReply(to: first)
            try? await Task.sleep(nanoseconds: 900_000_000)
        },
        SmokeScene("66-today-new-event", settle: 2.0) { app in
            app.mail.compose = nil
            app.select(.today)
            try? await Task.sleep(nanoseconds: 300_000_000)
            app.requestNewEvent()
        },
        SmokeScene("67-cleanup", settle: 1.0) { app in
            app.calendar.ui.editor = nil
            app.calendar.ui.closePopover()
            app.mail.compose = nil
            app.mail.scope = MailScope()
            app.select(.today)
        },
    ]

    /// The design's pending invitation (the interview), from the loaded calendar.
    @MainActor private static func invitation(_ app: AppModel) async -> AgendaEvent? {
        let now = app.now()
        await app.calendar.ensureEvents(from: now, to: now.addingTimeInterval(21 * 86_400))
        return app.calendar.pendingInvitations.first
            ?? app.calendar.events(from: now, to: now.addingTimeInterval(21 * 86_400)).first { $0.event.organizer?.isSelf != true && $0.event.selfAttendee != nil }
    }
}
