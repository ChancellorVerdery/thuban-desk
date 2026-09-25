import Foundation
import ThubanDeskCore

// Shared by the macOS Today area and the iOS Today tab.

// MARK: - Model

/// Everything the Today cards show, computed once per render from the stores (pure functions in the core).
@MainActor
struct TodayModel {
    let now: Date
    let zone: TimeZone
    let today: CivilDate
    let entries: [TodayAgenda.Entry]
    let tomorrow: [AgendaEvent]
    let invitations: [AgendaEvent]
    let replies: [ReplyItem]
    /// Event id → the thread asking about it (the agenda row's "Maya: …" chip).
    let questionsByEvent: [String: ReplyItem]
    /// All loaded events today and tomorrow (conflict checks).
    let nearby: [AgendaEvent]

    struct ReplyItem: Identifiable {
        var summary: ThreadSummary
        var verdict: NeedsReply.Verdict
        var link: TodayLinks.Link?
        /// The asking sentence (+ the next one) from the full thread.
        var quote: String?
        var id: String { summary.key.description }
    }

    init(app: AppModel) {
        let now = app.now()
        let zone = app.zone
        let today = CivilDate(now, in: zone)
        let start = today.startDate(in: zone)
        let mid = today.adding(days: 1).startDate(in: zone)
        let end = today.adding(days: 2).startDate(in: zone)
        let tomorrowDay = today.adding(days: 1)
        let invitations = app.calendar.pendingInvitations
        let own = app.ownAddresses
        let linkPool = app.calendar.events(from: start, to: today.adding(days: 4).startDate(in: zone))
        let items = app.mail.needsReplyThreads.map { pair in
            ReplyItem(summary: pair.summary, verdict: pair.verdict,
                      link: pair.summary.from.flatMap { TodayLinks.link(sender: $0.normalized, events: linkPool, invitations: invitations, own: own, now: now, zone: zone) },
                      quote: app.mail.details[pair.summary.key].flatMap { TodayLinks.excerpt(of: $0, verdict: pair.verdict) } ?? pair.verdict.question)
        }
        var byEvent: [String: ReplyItem] = [:]
        for item in items {
            if let link = item.link, link.kind == .event, byEvent[link.event.id] == nil { byEvent[link.event.id] = item }
        }
        self.now = now
        self.zone = zone
        self.today = today
        entries = TodayAgenda.build(events: app.calendar.events(from: start, to: mid), day: today, now: now, zone: zone)
        tomorrow = app.calendar.events(from: mid, to: end)
            .filter { item in
                guard !item.event.isCancelled, item.event.selfResponse != .declined else { return false }
                if item.event.isAllDay {
                    return (item.event.start.date ?? tomorrowDay) <= tomorrowDay && (item.event.end.date ?? tomorrowDay.adding(days: 1)) > tomorrowDay
                }
                return item.start(in: zone) >= mid
            }
            .sorted { ($0.event.isAllDay ? 0 : 1, $0.start(in: zone), $0.event.title) < ($1.event.isAllDay ? 0 : 1, $1.start(in: zone), $1.event.title) }
        self.invitations = invitations
        nearby = app.calendar.events(from: start, to: end, includeHidden: true)
        replies = items
        questionsByEvent = byEvent
    }

    var eventCount: Int {
        entries.reduce(0) { count, entry in
            switch entry {
            case .allDay, .event: return count + 1
            case .free, .nowMarker: return count
            }
        }
    }

    var remainingCount: Int {
        entries.reduce(0) { count, entry in
            if case .event(_, let status) = entry, status != .done { return count + 1 }
            return count
        }
    }
}

extension AppModel {
    /// Account colour: the primary is accent, the next signal, and so on (as in Settings → Accounts and Mail).
    func accountTint(_ account: String) -> CalendarTint {
        mail.accountTint(account)
    }
}

