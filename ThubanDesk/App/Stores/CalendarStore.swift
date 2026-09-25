import Foundation
import Observation
import ThubanDeskCore

/// A calendar across accounts, with its local display preferences.
struct CalendarRef: Identifiable, Hashable {
    var key: CalendarKey
    var entry: CalendarListEntry
    var tint: CalendarTint
    var isHidden: Bool

    var id: String { key.description }
    var account: String { key.account }
    var name: String { entry.displayName }
    var canWrite: Bool { entry.canWrite }
    var isPrimary: Bool { entry.isPrimary }
    var zone: TimeZone { entry.zone }
}

/// Calendar data for every linked account: calendar lists, events cached per (calendar, month) on disk and in
/// memory, visible-range loading with neighbour prefetch, and every write (create, edit with recurrence scopes,
/// delete, RSVP). Views read `calendars`, `events(from:to:)`, `pendingInvitations`; `revision` bumps on every change.
@MainActor
@Observable
final class CalendarStore {
    @ObservationIgnored weak var app: AppModel!
    /// The calendar area's view state (range, popover, editor, scope dialog); see `CalendarUIState`.
    @ObservationIgnored private(set) lazy var ui = CalendarUIState(store: self)

    /// account → calendars (Google's order).
    private(set) var calendarLists: [String: [CalendarListEntry]] = [:]
    /// Months loaded per calendar: calendar → month → events (instances, `singleEvents=true`).
    private(set) var months: [CalendarKey: [YearMonth: [CalendarEvent]]] = [:]
    @ObservationIgnored private var monthLoadedAt: [CalendarKey: [YearMonth: Date]] = [:]
    @ObservationIgnored private var inflight: [String: Task<Void, Never>] = [:]
    /// Latest load request per month cache key; a fetch whose generation is older is dropped (a forced reload
    /// after a write always wins over a fetch that started before it).
    @ObservationIgnored private var monthGeneration: [String: Int] = [:]
    @ObservationIgnored private var listFetched: Set<String> = []
    private(set) var isLoading = false
    /// Last failure per account (offline, 403 …).
    private(set) var accountErrors: [String: String] = [:]
    /// Bumped on every data change.
    private(set) var revision = 0
    /// The range the calendar view shows (set by the view; refresh reloads it).
    var visibleRange: DateInterval?

    static let monthTTL: TimeInterval = 180

    // MARK: Calendars

    /// Every calendar, accounts in link order (primary first), each account's primary calendar first.
    var calendars: [CalendarRef] {
        guard let app else { return [] }
        return app.accounts.flatMap { account -> [CalendarRef] in
            let list = calendarLists[account.id] ?? []
            return (list.filter(\.isPrimary) + list.filter { !$0.isPrimary })
                .map { entry in
                    let key = CalendarKey(account: account.id, calendarID: entry.id)
                    return CalendarRef(key: key, entry: entry, tint: tint(for: key, entry: entry), isHidden: app.settings.isHidden(key))
                }
        }
    }

    var visibleCalendars: [CalendarRef] { calendars.filter { !$0.isHidden } }

    func calendar(_ key: CalendarKey) -> CalendarRef? { calendars.first { $0.key == key } }

    func tint(for key: CalendarKey, entry: CalendarListEntry? = nil) -> CalendarTint {
        if let override = app?.settings.calendarTints[key.description] { return override }
        let entry = entry ?? calendarLists[key.account]?.first { $0.id == key.calendarID }
        return entry?.defaultTint ?? .accent
    }

    func setHidden(_ hidden: Bool, _ key: CalendarKey) {
        if hidden { app.settings.hiddenCalendars.insert(key) } else { app.settings.hiddenCalendars.remove(key) }
        revision += 1
    }

    func setTint(_ tint: CalendarTint?, _ key: CalendarKey) {
        app.settings.calendarTints[key.description] = tint
        revision += 1
    }

    /// Where new events go: the chosen default, else the primary account's primary calendar.
    var defaultCalendar: CalendarRef? {
        if let key = app?.settings.defaultCalendar, let ref = calendar(key), ref.canWrite { return ref }
        return calendars.first { $0.isPrimary && $0.canWrite } ?? calendars.first { $0.canWrite }
    }

    /// Loads every account's calendar list (cache first).
    func loadCalendars(force: Bool = false) async {
        guard let app else { return }
        await withTaskGroup(of: Void.self) { group in
            for account in app.activeAccounts {
                group.addTask { await self.loadCalendarList(account: account.id, force: force) }
            }
        }
        revision += 1
    }

    private func loadCalendarList(account: String, force: Bool) async {
        let key = "calendars|\(account)"
        if calendarLists[account] == nil, let entry = await app.cache.entry(for: key),
           let cached = try? GoogleJSON.decoder.decode([CalendarListEntry].self, from: entry.data) {
            calendarLists[account] = cached
        }
        guard force || !listFetched.contains(account) else { return }
        guard let client = app.client(for: account) else { return }
        do {
            let list = try await client.calendarList()
            calendarLists[account] = list
            listFetched.insert(account)
            accountErrors[account] = nil
            if let data = try? GoogleJSON.cacheEncoder.encode(list) { await app.cache.store(data, for: key) }
        } catch {
            accountErrors[account] = error.localizedDescription
        }
    }

    // MARK: Events

    /// Visible events overlapping `[from, to)`, across calendars, sorted by start (all-day first on ties).
    func events(from: Date, to: Date, includeHidden: Bool = false) -> [AgendaEvent] {
        guard let app else { return [] }
        let zone = app.zone
        let wanted = YearMonth.covering(from: from, to: to, in: zone)
        var seen = Set<String>()
        var result: [AgendaEvent] = []
        for ref in (includeHidden ? calendars : visibleCalendars) {
            guard let byMonth = months[ref.key] else { continue }
            for month in wanted {
                for event in byMonth[month] ?? [] where !event.isCancelled {
                    guard event.startDate(in: zone) < to, event.endDate(in: zone) > from else { continue }
                    if !app.settings.showDeclinedEvents, event.selfResponse == .declined { continue }
                    let item = AgendaEvent(calendar: ref.key, event: event, tint: ref.tint)
                    if seen.insert(item.id).inserted { result.append(item) }
                }
            }
        }
        return result.sorted {
            let a = $0.event.startDate(in: zone), b = $1.event.startDate(in: zone)
            if a != b { return a < b }
            if $0.event.isAllDay != $1.event.isAllDay { return $0.event.isAllDay }
            return $0.event.title < $1.event.title
        }
    }

    /// Loads the months covering `[from, to)` for every visible calendar (cache first, then network when stale),
    /// then prefetches one month on each side in the background.
    func ensureEvents(from: Date, to: Date, force: Bool = false) async {
        guard let app else { return }
        let zone = app.zone
        let wanted = YearMonth.covering(from: from, to: to, in: zone)
        isLoading = true
        await load(months: wanted, force: force)
        isLoading = false
        if let first = wanted.first, let last = wanted.last {
            let neighbours = [first.adding(months: -1), last.adding(months: 1)]
            Task { await self.load(months: neighbours, force: false) }
        }
    }

    private func load(months wanted: [YearMonth], force: Bool) async {
        let refs = visibleCalendars
        await withTaskGroup(of: Void.self) { group in
            for ref in refs {
                for month in wanted {
                    group.addTask { await self.loadMonth(month, for: ref, force: force) }
                }
            }
        }
    }

    private func loadMonth(_ month: YearMonth, for ref: CalendarRef, force: Bool) async {
        let cacheKey = "events|\(ref.key)|\(month)"
        // A forced load (after a write) never reuses a running fetch: that one may have started before the write.
        if !force, let running = inflight[cacheKey] { await running.value; return }
        if !force, months[ref.key]?[month] != nil, let loaded = monthLoadedAt[ref.key]?[month],
           Date().timeIntervalSince(loaded) < Self.monthTTL { return }
        // Registered synchronously (before any await), so concurrent callers see it and older results are dropped.
        let generation = (monthGeneration[cacheKey] ?? 0) + 1
        monthGeneration[cacheKey] = generation
        let client = app.client(for: ref.account)
        let interval = month.interval(in: app.zone)
        let task = Task { @MainActor in
            let isCurrent = { self.monthGeneration[cacheKey] == generation }
            if months[ref.key]?[month] == nil, let entry = await app.cache.entry(for: cacheKey),
               let cached = try? GoogleJSON.decoder.decode([CalendarEvent].self, from: entry.data),
               isCurrent(), months[ref.key]?[month] == nil {
                months[ref.key, default: [:]][month] = cached
                revision += 1
            }
            guard let client else { return }
            do {
                let events = try await client.events(calendarID: ref.key.calendarID, from: interval.start, to: interval.end)
                guard isCurrent() else { return }
                months[ref.key, default: [:]][month] = events
                monthLoadedAt[ref.key, default: [:]][month] = Date()
                accountErrors[ref.account] = nil
                revision += 1
                if let data = try? GoogleJSON.cacheEncoder.encode(events) { await app.cache.store(data, for: cacheKey) }
            } catch {
                guard isCurrent() else { return }
                accountErrors[ref.account] = error.localizedDescription
            }
        }
        inflight[cacheKey] = task
        await task.value
        if monthGeneration[cacheKey] == generation { inflight[cacheKey] = nil }
    }

    /// Reloads calendar lists and the visible range (or this month) from the network.
    func refresh() async {
        guard let app else { return }
        await loadCalendars(force: true)
        let range = visibleRange ?? YearMonth(app.now(), in: app.zone).interval(in: app.zone)
        await ensureEvents(from: range.start, to: range.end, force: true)
    }

    /// Re-fetches the months an event touches after a write.
    private func reload(_ key: CalendarKey, around dates: [Date]) async {
        guard let ref = calendar(key) else { return }
        let wanted = Set(dates.map { YearMonth($0, in: app.zone) })
        for month in wanted { await loadMonth(month, for: ref, force: true) }
        if let visibleRange {
            for month in YearMonth.covering(from: visibleRange.start, to: visibleRange.end, in: app.zone) where !wanted.contains(month) {
                await loadMonth(month, for: ref, force: true)
            }
        }
    }

    /// Unanswered invitations from now on, across visible calendars (loaded range only).
    var pendingInvitations: [AgendaEvent] {
        guard let app else { return [] }
        let all = months.flatMap { key, byMonth in
            byMonth.values.flatMap { $0 }.map { AgendaEvent(calendar: key, event: $0, tint: tint(for: key)) }
        }
        return TodayAgenda.pendingInvitations(all.filter { !(app.settings.isHidden($0.calendar)) }, after: app.now(), zone: app.zone)
    }

    /// Drops an account's data (sign-out).
    func forget(account: String) {
        let id = account.lowercased()
        calendarLists[id] = nil
        months = months.filter { $0.key.account != id }
        monthLoadedAt = monthLoadedAt.filter { $0.key.account != id }
        revision += 1
    }

    // MARK: Writes

    /// The recurring master for an instance (fetched), or the event itself.
    func master(of event: CalendarEvent, in key: CalendarKey) async throws -> CalendarEvent {
        guard let client = app.client(for: key.account) else { throw ThubanError.notSignedIn(key.account) }
        return try await client.master(of: event, calendarID: key.calendarID)
    }

    /// The scope choices for editing (or deleting) this event; empty when it does not repeat.
    func scopes(for event: CalendarEvent, in key: CalendarKey, changingRecurrence: Bool = false) async throws -> [RecurrenceScope] {
        guard event.isRecurringInstance || event.isRecurringMaster else { return [] }
        let master = try await master(of: event, in: key)
        return RecurrenceEditPlanner.scopes(master: master, instance: event, zone: calendar(key)?.zone ?? app.zone, changingRecurrence: changingRecurrence)
    }

    @discardableResult
    func create(_ event: CalendarEvent, in key: CalendarKey, sendUpdates: SendUpdates = .none) async throws -> CalendarEvent {
        guard let client = app.client(for: key.account) else { throw ThubanError.notSignedIn(key.account) }
        let created = try await client.insertEvent(event, calendarID: key.calendarID, sendUpdates: sendUpdates)
        await reload(key, around: [created.startDate(in: app.zone), created.endDate(in: app.zone)])
        return created
    }

    /// Saves an edit. For a repeating event pass the scope the user chose (`scopes(for:in:)`); single events ignore it.
    /// Moving an event to another calendar is a separate action (`move`).
    func save(_ patch: EventPatch, to event: CalendarEvent, in key: CalendarKey, scope: RecurrenceScope = .thisEvent,
              sendUpdates: SendUpdates = .none) async throws {
        guard let client = app.client(for: key.account) else { throw ThubanError.notSignedIn(key.account) }
        let master = event.isRecurringInstance || event.isRecurringMaster ? try await client.master(of: event, calendarID: key.calendarID) : nil
        let plan = try RecurrenceEditPlanner.planEdit(master: master, instance: event, patch: patch, scope: scope, calendarID: key.calendarID,
                                                      zone: calendar(key)?.zone ?? app.zone)
        try await client.perform(plan, sendUpdates: sendUpdates)
        await reload(key, around: [event.startDate(in: app.zone), patch.start?.instant(in: app.zone) ?? event.startDate(in: app.zone)])
    }

    /// Deletes (irreversible — only from a confirmed ConfirmWriteSheet).
    func delete(_ event: CalendarEvent, in key: CalendarKey, scope: RecurrenceScope = .thisEvent, sendUpdates: SendUpdates = .none,
                confirmed: Confirmed) async throws {
        guard let client = app.client(for: key.account) else { throw ThubanError.notSignedIn(key.account) }
        let master = event.isRecurringInstance || event.isRecurringMaster ? try await client.master(of: event, calendarID: key.calendarID) : nil
        let plan = try RecurrenceEditPlanner.planDelete(master: master, instance: event, scope: scope, calendarID: key.calendarID,
                                                        zone: calendar(key)?.zone ?? app.zone)
        try await client.perform(plan, sendUpdates: sendUpdates)
        await reload(key, around: [event.startDate(in: app.zone)])
    }

    /// Yes / Maybe / No on an invitation (guests are notified, as in Google Calendar).
    func rsvp(_ status: ResponseStatus, to event: CalendarEvent, in key: CalendarKey) async throws {
        guard let client = app.client(for: key.account) else { throw ThubanError.notSignedIn(key.account) }
        _ = try await client.rsvp(status, to: event, calendarID: key.calendarID, selfEmail: key.account)
        // A repeating invitation is answered for the whole series: every loaded month of this calendar changes.
        let loaded = event.isRecurringInstance ? (months[key].map { Array($0.keys) } ?? []).map { $0.interval(in: app.zone).start } : []
        await reload(key, around: [event.startDate(in: app.zone)] + loaded)
    }

    /// Finds (or creates) a dedicated calendar by name in an account; returns its key.
    func findOrCreateCalendar(named name: String, account: String) async throws -> CalendarKey {
        guard let client = app.client(for: account) else { throw ThubanError.notSignedIn(account) }
        let id = try await client.findOrCreateCalendar(named: name, timeZone: app.zone.identifier)
        await loadCalendarList(account: account.lowercased(), force: true)
        revision += 1
        return CalendarKey(account: account, calendarID: id)
    }
}
