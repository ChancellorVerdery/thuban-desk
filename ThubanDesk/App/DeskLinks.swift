import Foundation
import Observation
import ThubanDeskCore

/// Links between the areas (integration, lead): the title-bar search over Mail and Calendar, opening an event from
/// anywhere, and finding the email an invitation came in.
///
/// Search: Mail filters its own list with Gmail `q=` and Calendar filters its grid; `DeskSearch` adds the other half
/// — matching events (from the cached months, `SearchMatch`) and matching threads across every account (Gmail
/// `q=`) — for the Today / Settings results page, the "Events" strip in Mail and the "emails match" pill in Calendar.
@MainActor
@Observable
final class DeskSearch {
    static let shared = DeskSearch()

    /// The trimmed query the results belong to ("" = no search).
    private(set) var query = ""
    private(set) var events: [AgendaEvent] = []
    private(set) var threads: [ThreadSummary] = []
    private(set) var isSearchingEvents = false
    private(set) var isSearchingMail = false
    /// Query the mail results were fetched for (Mail's own list covers it while Mail is shown).
    @ObservationIgnored private var mailQuery = ""
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var mailTask: Task<Void, Never>?

    var isSearching: Bool { isSearchingEvents || isSearchingMail }
    var hasMailResults: Bool { mailQuery == query && !query.isEmpty }

    /// Call on every search-text or area change; debounced.
    func update(text: String, app: AppModel) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            eventTask?.cancel(); mailTask?.cancel()
            query = ""; mailQuery = ""; events = []; threads = []
            isSearchingEvents = false; isSearchingMail = false
            return
        }
        if q != query {
            query = q
            eventTask?.cancel()
            isSearchingEvents = true
            eventTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await self.searchEvents(q, app: app)
            }
        }
        // Mail: Gmail search across accounts — skipped while Mail is shown (its list runs the same search).
        if app.area != .mail, mailQuery != q {
            mailTask?.cancel()
            isSearchingMail = true
            mailTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { return }
                await self.searchMail(q, app: app)
            }
        }
    }

    /// Re-match events after the calendar changed (an edit, a sync) without refetching.
    func rematchEvents(app: AppModel) {
        guard !query.isEmpty, !isSearchingEvents else { return }
        let (from, to) = Self.window(app)
        events = SearchMatch.events(app.calendar.events(from: from, to: to), query: query, now: app.now(), zone: app.zone)
    }

    private func searchEvents(_ q: String, app: AppModel) async {
        let (from, to) = Self.window(app)
        await app.calendar.ensureEvents(from: from, to: to)
        guard !Task.isCancelled, q == query else { return }
        events = SearchMatch.events(app.calendar.events(from: from, to: to), query: q, now: app.now(), zone: app.zone)
        isSearchingEvents = false
    }

    private func searchMail(_ q: String, app: AppModel) async {
        var found: [ThreadSummary] = []
        for account in app.activeAccounts {
            guard let client = app.client(for: account.id) else { continue }
            if let list = try? await client.threadSummaries(query: q, limit: 12) { found += list }
            guard !Task.isCancelled else { return }
        }
        guard q == query else { return }
        threads = found.sorted { $0.date > $1.date }
        mailQuery = q
        isSearchingMail = false
    }

    /// Two months back, six ahead — the months the calendar caches anyway around a typical view.
    private static func window(_ app: AppModel) -> (Date, Date) {
        let now = app.now()
        return (now.addingTimeInterval(-60 * 86_400), now.addingTimeInterval(180 * 86_400))
    }
}

extension AppModel {
    /// Calendar with the event's week (or day) shown, scrolled to it, and its popover open.
    func openEvent(_ item: AgendaEvent) {
        select(.calendar)
        let ui = calendar.ui
        let day = CivilDate(item.start(in: zone), in: zone)
        ui.show(day, mode: ui.mode == .month ? .week : nil)
        Task { @MainActor in
            await calendar.ensureEvents(from: day.startDate(in: zone), to: day.adding(days: 1).startDate(in: zone))
            try? await Task.sleep(nanoseconds: 120_000_000)
            ui.select(item)
            ui.scrollRequest += 1
        }
    }

    /// The email an invitation arrived in: a loaded thread from the organizer whose message matches the event,
    /// else a Gmail search `from:<organizer>` in the calendar's account. Opens it in Mail; nil if none was found.
    @discardableResult
    func openInvitationEmail(for item: AgendaEvent) async -> Bool {
        guard let key = await invitationThread(for: item) else { return false }
        openThread(key)
        return true
    }

    func invitationThread(for item: AgendaEvent) async -> ThreadKey? {
        guard let organizer = item.event.organizer?.email?.lowercased(), item.event.organizer?.isSelf != true else { return nil }
        let account = item.calendar.account
        func matches(_ thread: MailThread) -> Bool {
            thread.messages.contains { message in MailInvite.match(message, candidates: [item], zone: zone)?.event.seriesID == item.event.seriesID }
        }
        // Loaded threads first (the list and the needs-reply scan).
        let loaded = mail.threads.filter { $0.account == account && $0.from?.normalized == organizer }.map(\.key)
        for key in loaded {
            if let thread = try? await mail.thread(key), matches(thread) { return key }
        }
        guard let client = client(for: account),
              let refs = try? await client.threadRefs(query: "from:\(organizer)", limit: 8) else { return loaded.first }
        var first: ThreadKey?
        for ref in refs {
            let key = ThreadKey(account: account, threadID: ref.id)
            if first == nil { first = key }
            if let thread = try? await mail.thread(key), matches(thread) { return key }
        }
        return loaded.first ?? first
    }
}
