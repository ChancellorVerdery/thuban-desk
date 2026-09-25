import Foundation
import Observation
import ThubanDeskCore

/// A drag that has been dropped: the event is drawn at its new times (with a dashed ghost at the old ones) until
/// the save finishes or the scope dialog is cancelled.
struct PendingMove: Equatable {
    var item: AgendaEvent
    var start: EventDateTime
    var end: EventDateTime
}

/// "Change a repeating event" / "Delete a repeating event" (design: RecurringScope).
struct ScopePrompt: Identifiable {
    let id = UUID()
    var item: AgendaEvent
    var master: CalendarEvent?
    var scopes: [RecurrenceScope]
    var selected: RecurrenceScope
    var action: CalendarText.ScopeAction
    /// The change for move / edit (nil for delete).
    var patch: EventPatch?
    var sendUpdates: SendUpdates
}

/// The calendar area's view state: which day / range is shown, the open popover, editor and scope dialog, drags
/// in flight, and the recurring masters fetched for popovers and the editor. Lives on `CalendarStore.ui` so smoke
/// scenes can put the calendar in any state.
@MainActor
@Observable
final class CalendarUIState {
    @ObservationIgnored unowned let store: CalendarStore

    /// The day the view is anchored on (nil = today).
    var focus: CivilDate?
    /// The month the sidebar's mini calendar shows (nil = the focus month).
    var miniMonth: YearMonth?
    /// The event whose popover is open (`AgendaEvent.id`).
    var selectedID: String?
    /// Snapshot of the selected event (the popover keeps showing it while data reloads).
    var selectedItem: AgendaEvent?
    var editor: EventDraft?
    var scope: ScopePrompt?
    var pendingMove: PendingMove?
    /// Last failure of a write, shown as a banner.
    var errorMessage: String?
    /// Recurring masters by "calendar|seriesID".
    var masters: [String: CalendarEvent] = [:]
    /// Bumped to scroll the time grid (Today, new range).
    var scrollRequest = 0
    var isWorking = false

    init(store: CalendarStore) {
        self.store = store
    }

    var app: AppModel { store.app }
    var zone: TimeZone { app.zone }
    var today: CivilDate { CivilDate(app.now(), in: zone) }
    var focusDay: CivilDate { focus ?? today }
    var mode: CalendarViewMode {
        get { app.settings.calendarViewMode }
        set { app.settings.calendarViewMode = newValue }
    }
    var firstWeekday: Weekday { app.settings.weekStartsOnMonday ? .monday : .sunday }

    // MARK: Ranges

    func weekStart(of day: CivilDate) -> CivilDate {
        let offset = (day.weekday.calendarWeekday - firstWeekday.calendarWeekday + 7) % 7
        return day.adding(days: -offset)
    }

    /// The days the week / day grid shows.
    var gridDays: [CivilDate] {
        switch mode {
        case .day: return [focusDay]
        case .week, .month:
            let start = weekStart(of: focusDay)
            return (0..<7).map { start.adding(days: $0) }
        }
    }

    var focusMonth: YearMonth { YearMonth(focusDay) }

    /// The weeks of the month grid (5 or 6 rows of 7 days).
    func monthWeeks(_ month: YearMonth) -> [[CivilDate]] {
        let first = month.firstDay
        let start = weekStart(of: first)
        let length = EventLayout.daysInMonth(year: month.year, month: month.month)
        let rows = Int(ceil(Double(start.days(to: first) + length) / 7))
        return (0..<rows).map { row in (0..<7).map { start.adding(days: row * 7 + $0) } }
    }

    /// The instant range currently shown.
    var visibleRange: DateInterval {
        let days: [CivilDate]
        switch mode {
        case .month: days = monthWeeks(focusMonth).flatMap { $0 }
        default: days = gridDays
        }
        let first = days.first ?? focusDay, last = days.last ?? focusDay
        return DateInterval(start: first.startDate(in: zone), end: last.adding(days: 1).startDate(in: zone))
    }

    var title: String {
        switch mode {
        case .day: return CalendarText.dayTitle(focusDay)
        case .week:
            let days = gridDays
            return CalendarText.rangeTitle(from: days.first ?? focusDay, to: days.last ?? focusDay)
        case .month: return CalendarText.monthTitle(year: focusMonth.year, month: focusMonth.month)
        }
    }

    // MARK: Navigation

    func step(_ direction: Int) {
        closePopover()
        switch mode {
        case .day: focus = focusDay.adding(days: direction)
        case .week: focus = focusDay.adding(days: 7 * direction)
        case .month:
            let month = focusMonth.adding(months: direction)
            let length = EventLayout.daysInMonth(year: month.year, month: month.month)
            focus = CivilDate(year: month.year, month: month.month, day: min(focusDay.day, length))
        }
        miniMonth = nil
    }

    func goToday() {
        closePopover()
        focus = nil
        miniMonth = nil
        scrollRequest += 1
    }

    func show(_ day: CivilDate, mode newMode: CalendarViewMode? = nil) {
        closePopover()
        focus = day
        if let newMode { mode = newMode }
        miniMonth = nil
    }

    func setMode(_ newMode: CalendarViewMode) {
        closePopover()
        mode = newMode
    }

    // MARK: Events

    /// Visible events in `[from, to)`, filtered by the title-bar search, with a dropped drag shown at its new time.
    func events(from: Date, to: Date) -> [AgendaEvent] {
        var items = store.events(from: from, to: to)
        let query = app.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            items = items.filter {
                $0.event.title.lowercased().contains(query) || ($0.event.location ?? "").lowercased().contains(query)
            }
        }
        return items
    }

    func item(id: String) -> AgendaEvent? {
        guard let snapshot = selectedItem, snapshot.id == id else { return nil }
        let range = DateInterval(start: snapshot.event.startDate(in: zone).addingTimeInterval(-86_400 * 2),
                                 end: snapshot.event.endDate(in: zone).addingTimeInterval(86_400 * 2))
        return store.events(from: range.start, to: range.end, includeHidden: true).first { $0.id == id } ?? snapshot
    }

    func masterKey(_ item: AgendaEvent) -> String { "\(item.calendar)|\(item.event.seriesID)" }

    func master(for item: AgendaEvent) -> CalendarEvent? {
        if item.event.isRecurringMaster { return item.event }
        return masters[masterKey(item)]
    }

    /// Fetches (once) the recurring master of an instance.
    @discardableResult
    func loadMaster(for item: AgendaEvent) async -> CalendarEvent? {
        guard item.event.isRecurringInstance else { return item.event.isRecurringMaster ? item.event : nil }
        if let cached = masters[masterKey(item)] { return cached }
        guard let master = try? await store.master(of: item.event, in: item.calendar) else { return nil }
        masters[masterKey(item)] = master
        return master
    }

    /// "Weekly on Thursday until Dec 10" for a repeating event (nil when it does not repeat or is not loaded yet).
    func repeatSummary(for item: AgendaEvent) -> String? {
        guard item.event.isRecurringInstance || item.event.isRecurringMaster else { return nil }
        guard let master = master(for: item) else { return "Repeats" }
        let seriesZone = master.start.zone ?? zone
        if let builder = RecurrenceBuilder(recurrence: master.recurrence, start: master.start.civilDate(in: seriesZone), zone: seriesZone) {
            return builder.summary
        }
        return "Repeats on a custom schedule"
    }

    /// Whether the user may change this event (calendar writable; own event or guests may modify).
    func canEdit(_ item: AgendaEvent) -> Bool {
        guard let ref = store.calendar(item.calendar), ref.canWrite else { return false }
        let event = item.event
        return event.isOrganizedBySelf || event.guestsCanModify == true || event.organizer?.email?.lowercased() == item.calendar.calendarID.lowercased()
    }

    func canDelete(_ item: AgendaEvent) -> Bool {
        store.calendar(item.calendar)?.canWrite ?? false
    }

    // MARK: Popover

    func select(_ item: AgendaEvent) {
        selectedID = item.id
        selectedItem = item
        Task { await loadMaster(for: item) }
    }

    func closePopover() {
        selectedID = nil
        selectedItem = nil
    }

    /// Closes the top-most thing (Escape).
    func dismissTop() -> Bool {
        if scope != nil { cancelScope(); return true }
        if editor != nil { editor = nil; return true }
        if selectedID != nil { closePopover(); return true }
        return false
    }

    // MARK: Editor

    func edit(_ item: AgendaEvent) {
        closePopover()
        Task {
            let master = await loadMaster(for: item)
            editor = EventDraft(item: item, master: master, zone: zone, canEdit: canEdit(item))
        }
    }

    func newEvent(on day: CivilDate? = nil, startMinute: Int? = nil, endMinute: Int? = nil, allDay: Bool = false) {
        closePopover()
        guard let calendar = store.defaultCalendar else {
            errorMessage = "No calendar you can add events to."
            return
        }
        let day = day ?? focusDay
        var start = startMinute ?? defaultStartMinute(on: day)
        start = min(start, 23 * 60)
        let end = max(start + 15, endMinute ?? (start + 60))
        editor = EventDraft(newOn: day, startMinute: start, endMinute: min(end, 24 * 60 - 1), allDay: allDay, calendar: calendar.key, zone: zone)
    }

    /// Next whole hour for today, 9 AM for other days.
    func defaultStartMinute(on day: CivilDate) -> Int {
        guard day == today else { return 9 * 60 }
        let now = EventLayout.minutes(of: app.now(), from: day, zone: zone)
        return min(23 * 60, (Int(now) / 60 + 1) * 60)
    }

    func duplicate(_ item: AgendaEvent) {
        closePopover()
        Task {
            let master = await loadMaster(for: item)
            var draft = EventDraft(item: item, master: master, zone: zone, canEdit: true)
            draft.makeCopy(calendar: canEdit(item) ? item.calendar : (store.defaultCalendar?.key ?? item.calendar))
            editor = draft
        }
    }

    /// Save pressed in the editor.
    func save(_ draft: EventDraft) {
        errorMessage = nil
        if draft.isNew {
            let event = draft.newEvent()
            let updates: SendUpdates = (event.attendees?.isEmpty ?? true) ? .none : .all
            run {
                try await self.store.create(event, in: draft.calendar, sendUpdates: updates)
                self.editor = nil
            }
            return
        }
        guard let item = draft.original else { return }
        let patch = draft.patch()
        guard !patch.isEmpty else { editor = nil; return }
        let updates: SendUpdates = (item.event.attendees?.isEmpty ?? true) ? .none : .all
        if item.event.isRecurringInstance || item.event.isRecurringMaster {
            let action: CalendarText.ScopeAction = patch.changesTime && patch.summary == nil && patch.description == nil && patch.location == nil
                && patch.recurrence == nil && patch.attendees == nil
                ? .move(start: patch.start ?? item.event.start, end: patch.end ?? item.event.end) : .edit
            askScope(for: item, action: action, patch: patch, sendUpdates: updates, changingRecurrence: patch.recurrence != nil)
            return
        }
        run {
            try await self.store.save(patch, to: item.event, in: item.calendar, sendUpdates: updates)
            self.editor = nil
        }
    }

    // MARK: Delete

    func requestDelete(_ item: AgendaEvent) {
        closePopover()
        let updates: SendUpdates = (item.event.attendees?.isEmpty ?? true) || !item.event.isOrganizedBySelf ? .none : .all
        if item.event.isRecurringInstance || item.event.isRecurringMaster {
            askScope(for: item, action: .delete, patch: nil, sendUpdates: updates, changingRecurrence: false)
        } else {
            confirmDelete(item, scope: .thisEvent, sendUpdates: updates)
        }
    }

    private func confirmDelete(_ item: AgendaEvent, scope: RecurrenceScope, sendUpdates: SendUpdates) {
        let what: String
        switch scope {
        case .thisEvent: what = "“\(item.event.title)” on \(CalendarText.longDay(item.event.start.civilDate(in: zone)))"
        case .everyWeekday(let day): what = "every \(day.name) of “\(item.event.title)” from here on"
        case .thisAndFollowing: what = "this and every later “\(item.event.title)”"
        case .allEvents: what = "every “\(item.event.title)”, past ones included"
        }
        let calendarName = store.calendar(item.calendar)?.name ?? "the calendar"
        let store = self.store
        app.confirm(ConfirmRequest(
            title: "Delete this event?",
            message: "This deletes \(what) from \(calendarName) in Google Calendar\(sendUpdates == .all ? " and tells the guests" : ""). It can’t be undone here.",
            actionLabel: "Delete event", destructive: true, workingLabel: "Deleting…"
        ) { confirmed in
            try await store.delete(item.event, in: item.calendar, scope: scope, sendUpdates: sendUpdates, confirmed: confirmed)
            store.ui.editor = nil
        })
    }

    // MARK: Drag

    /// A drag ended: save right away (single event) or ask which events of the series move.
    func commitMove(_ item: AgendaEvent, start: EventDateTime, end: EventDateTime) {
        guard start != item.event.start || end != item.event.end else { return }
        closePopover()
        pendingMove = PendingMove(item: item, start: start, end: end)
        let patch = EventPatch(start: start, end: end)
        let updates: SendUpdates = (item.event.attendees?.isEmpty ?? true) ? .none : .all
        if item.event.isRecurringInstance || item.event.isRecurringMaster {
            askScope(for: item, action: .move(start: start, end: end), patch: patch, sendUpdates: updates, changingRecurrence: false)
            return
        }
        run {
            defer { self.pendingMove = nil }
            try await self.store.save(patch, to: item.event, in: item.calendar, sendUpdates: updates)
        } onError: {
            self.pendingMove = nil
        }
    }

    // MARK: Scope dialog

    private func askScope(for item: AgendaEvent, action: CalendarText.ScopeAction, patch: EventPatch?, sendUpdates: SendUpdates, changingRecurrence: Bool) {
        Task {
            isWorking = true
            defer { isWorking = false }
            let master = await loadMaster(for: item)
            let scopes: [RecurrenceScope]
            if let master {
                scopes = RecurrenceEditPlanner.scopes(master: master, instance: item.event, zone: store.calendar(item.calendar)?.zone ?? zone,
                                                      changingRecurrence: changingRecurrence)
            } else {
                scopes = changingRecurrence ? [.thisAndFollowing, .allEvents] : [.thisEvent, .thisAndFollowing, .allEvents]
            }
            let preferred: RecurrenceScope = scopes.first { if case .everyWeekday = $0 { return true } else { return false } } ?? scopes.first ?? .thisEvent
            let selected: RecurrenceScope
            switch action {
            case .move: selected = preferred
            default: selected = scopes.first ?? .thisEvent
            }
            scope = ScopePrompt(item: item, master: master, scopes: scopes.isEmpty ? [.thisEvent] : scopes, selected: selected,
                                action: action, patch: patch, sendUpdates: sendUpdates)
        }
    }

    func cancelScope() {
        scope = nil
        pendingMove = nil
    }

    func confirmScope() {
        guard let prompt = scope else { return }
        let chosen = prompt.selected
        switch prompt.action {
        case .delete:
            scope = nil
            confirmDelete(prompt.item, scope: chosen, sendUpdates: prompt.sendUpdates)
        case .move, .edit:
            guard let patch = prompt.patch else { scope = nil; return }
            run {
                try await self.store.save(patch, to: prompt.item.event, in: prompt.item.calendar, scope: chosen, sendUpdates: prompt.sendUpdates)
                self.scope = nil
                self.pendingMove = nil
                self.editor = nil
            } onError: {
                self.scope = nil
                self.pendingMove = nil
            }
        }
    }

    // MARK: RSVP

    func rsvp(_ status: ResponseStatus, _ item: AgendaEvent) {
        run {
            try await self.store.rsvp(status, to: item.event, in: item.calendar)
            if var draft = self.editor, draft.original?.id == item.id { draft.rsvp = status; self.editor = draft }
            if self.selectedID == item.id, let fresh = self.item(id: item.id) { self.selectedItem = fresh }
        }
    }

    // MARK: Running writes

    private func run(_ work: @escaping @MainActor () async throws -> Void, onError: (@MainActor () -> Void)? = nil) {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
                onError?()
            }
        }
    }
}
