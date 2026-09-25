import Foundation
import ThubanDeskCore

/// iOS versions of the cross-area requests the Mac app keeps in `AppModel+Today.swift` (shared code such as
/// `DeskLinks.openInvitationEmail` calls `openThread`).
extension AppModel {
    /// Mail tab with the thread open (marks it read, like Gmail).
    func openThread(_ key: ThreadKey) {
        PhoneRouter.shared.showThread(key)
        Task { @MainActor in await mail.open(key) }
    }

    /// Opens the reply sheet for the thread's latest message, from the account the thread arrived in.
    func requestReply(to key: ThreadKey, all: Bool = false) {
        Task { @MainActor in
            guard let thread = try? await mail.thread(key),
                  let last = thread.messages.last(where: { !$0.isDraft }) ?? thread.messages.last else { return }
            PhoneRouter.shared.compose = PhoneComposeModel.reply(to: last, in: key, all: all, app: self)
        }
    }

    func requestForward(_ key: ThreadKey) {
        Task { @MainActor in
            guard let thread = try? await mail.thread(key), let last = thread.messages.last(where: { !$0.isDraft }) ?? thread.messages.last else { return }
            PhoneRouter.shared.compose = PhoneComposeModel.forward(last, in: key, app: self)
        }
    }

    func requestCompose() {
        PhoneRouter.shared.compose = PhoneComposeModel.new(app: self)
    }

    /// New event on the calendar tab's focused day (Today → New event opens it for today).
    func requestNewEvent(on day: CivilDate? = nil) {
        calendar.ui.newEvent(on: day ?? calendar.ui.today)
    }

    /// Calendar tab on the event's day with the editor open.
    func openEventInCalendar(_ item: AgendaEvent) {
        let router = PhoneRouter.shared
        router.tab = .calendar
        router.padSection = .calendar
        let day = CivilDate(item.start(in: zone), in: zone)
        calendar.ui.focus = day
        if router.calendarMode == .month { router.calendarMode = .day }
        calendar.ui.edit(item)
    }

    /// "2 accounts · synced 2:38" (Today's status pill).
    var phoneSyncText: String {
        let summary = syncSummary
        guard summary.tone == .ok, let lastSync else { return summary.text }
        let count = activeAccounts.count
        return "\(count) account\(count == 1 ? "" : "s") · synced \(CalendarText.clock(lastSync, zone: zone, suffix: false))"
    }
}
