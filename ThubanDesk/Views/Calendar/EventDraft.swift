import Foundation
import ThubanDeskCore

/// The event editor's working copy (design: EventEditor). Built from an instance (+ its recurring master) or for
/// a new event; produces the inserted event or the patch of what changed. Times are wall-clock minutes in the
/// viewer's zone; all-day events use whole dates (end inclusive here, exclusive in Google).
struct EventDraft: Identifiable {
    enum RepeatKind: String, CaseIterable, Identifiable {
        case never, daily, weekly, monthly, yearly, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .never: return "Never"
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            case .custom: return "Custom"
            }
        }
    }

    enum EndKind: Hashable { case never, onDate, after }

    let id = UUID()
    /// The event being edited (nil for a new event).
    var original: AgendaEvent?
    var master: CalendarEvent?
    var zone: TimeZone
    var canEdit: Bool

    var calendar: CalendarKey
    var title: String
    var isAllDay: Bool
    var startDay: CivilDate
    var startMinute: Int
    var endDay: CivilDate
    var endMinute: Int
    var location: String

    var repeatKind: RepeatKind
    var interval: Int
    var weekdays: Set<Weekday>
    var monthlyByWeekday: Bool
    var endKind: EndKind
    var untilDay: CivilDate
    var count: Int
    private var initialRepeat: RecurrenceBuilder?
    private var initialKind: RepeatKind

    var attendees: [EventAttendee]
    var newGuest = ""
    /// Current description HTML (updated by the rich-text editor).
    var descriptionHTML: String
    var descriptionEdited = false
    /// The user's own reply (invitations).
    var rsvp: ResponseStatus?

    var isNew: Bool { original == nil }

    // MARK: Init

    init(newOn day: CivilDate, startMinute: Int, endMinute: Int, allDay: Bool, calendar: CalendarKey, zone: TimeZone) {
        self.zone = zone
        canEdit = true
        self.calendar = calendar
        title = ""
        isAllDay = allDay
        startDay = day
        self.startMinute = startMinute
        endDay = day
        self.endMinute = endMinute
        location = ""
        repeatKind = .never
        initialKind = .never
        interval = 1
        weekdays = [day.weekday]
        monthlyByWeekday = false
        endKind = .never
        untilDay = day.adding(days: 90)
        count = 10
        attendees = []
        descriptionHTML = ""
    }

    init(item: AgendaEvent, master: CalendarEvent?, zone: TimeZone, canEdit: Bool) {
        let event = item.event
        original = item
        self.master = master
        self.zone = zone
        self.canEdit = canEdit
        calendar = item.calendar
        title = event.summary ?? ""
        isAllDay = event.isAllDay
        if event.isAllDay {
            startDay = event.start.civilDate(in: zone)
            endDay = max(startDay, event.end.civilDate(in: zone).adding(days: -1))
            startMinute = 9 * 60
            endMinute = 10 * 60
        } else {
            let start = event.startDate(in: zone), end = event.endDate(in: zone)
            startDay = CivilDate(start, in: zone)
            startMinute = Int(EventLayout.minutes(of: start, from: startDay, zone: zone).rounded())
            endDay = CivilDate(end, in: zone)
            endMinute = Int(EventLayout.minutes(of: end, from: endDay, zone: zone).rounded())
        }
        location = event.location ?? ""
        attendees = event.attendees ?? []
        descriptionHTML = HTMLSanitizer.eventDescription(event.description)
        rsvp = event.selfResponse

        interval = 1
        weekdays = [startDay.weekday]
        monthlyByWeekday = false
        endKind = .never
        untilDay = startDay.adding(days: 90)
        count = 10
        repeatKind = .never
        initialKind = .never
        let recurring = event.isRecurringInstance || event.isRecurringMaster
        if recurring, let master {
            let seriesZone = master.start.zone ?? zone
            if let builder = RecurrenceBuilder(recurrence: master.recurrence, start: master.start.civilDate(in: seriesZone), zone: seriesZone) {
                initialRepeat = builder
                apply(builder)
                if case .onDate = builder.end {
                    // "After N times" starts at what is left from this occurrence to the end date.
                    let rule = builder.rrule(isAllDay: event.isAllDay, zone: seriesZone)
                    let from = event.startDate(in: zone)
                    count = max(1, rule.occurrences(start: master.startDate(in: seriesZone), zone: seriesZone, isAllDay: event.isAllDay, limit: 2000)
                        .filter { $0 >= from }.count)
                }
            } else {
                repeatKind = .custom
            }
        } else if recurring {
            repeatKind = .custom
        }
        initialKind = repeatKind
    }

    private mutating func apply(_ builder: RecurrenceBuilder) {
        interval = builder.interval
        switch builder.pattern {
        case .daily: repeatKind = .daily
        case .weekly(let days): repeatKind = .weekly; weekdays = days.isEmpty ? [startDay.weekday] : days
        case .monthlyByDate: repeatKind = .monthly; monthlyByWeekday = false
        case .monthlyByWeekday: repeatKind = .monthly; monthlyByWeekday = true
        case .yearly: repeatKind = .yearly
        }
        switch builder.end {
        case .never: endKind = .never
        case .onDate(let date): endKind = .onDate; untilDay = date
        case .after(let n): endKind = .after; count = n
        }
    }

    /// Turns an existing event's draft into a new one (Duplicate).
    mutating func makeCopy(calendar: CalendarKey) {
        original = nil
        master = nil
        canEdit = true
        self.calendar = calendar
        attendees = attendees.map { var a = $0; a.responseStatus = a.isSelf == true ? .accepted : .needsAction; return a }
        if repeatKind == .custom { repeatKind = .never }
        initialRepeat = nil
        initialKind = .never
        descriptionEdited = true
    }

    // MARK: Derived

    var startDate: Date { isAllDay ? startDay.startDate(in: zone) : EventLayout.date(on: startDay, minutes: startMinute, zone: zone) }
    var endDate: Date { isAllDay ? endDay.adding(days: 1).startDate(in: zone) : EventLayout.date(on: endDay, minutes: endMinute, zone: zone) }
    var durationMinutes: Int { Int(endDate.timeIntervalSince(startDate) / 60) }
    var isValid: Bool { endDate > startDate }

    var startValue: EventDateTime { isAllDay ? .allDay(startDay) : .timed(startDate, timeZone: zone.identifier) }
    var endValue: EventDateTime { isAllDay ? .allDay(endDay.adding(days: 1)) : .timed(endDate, timeZone: zone.identifier) }

    /// Moves the start, keeping the duration (like Google Calendar).
    mutating func setStart(day: CivilDate? = nil, minute: Int? = nil) {
        let duration = endDate.timeIntervalSince(startDate)
        let dayShift = day.map { startDay.days(to: $0) } ?? 0
        if let day { startDay = day }
        if let minute { startMinute = max(0, min(24 * 60 - 1, minute)) }
        if isAllDay {
            endDay = endDay.adding(days: dayShift)
        } else {
            let end = startDate.addingTimeInterval(max(15 * 60, duration))
            endDay = CivilDate(end, in: zone)
            endMinute = Int(EventLayout.minutes(of: end, from: endDay, zone: zone).rounded())
        }
        if case .weekly = repeatKind, weekdays.count == 1 { weekdays = [startDay.weekday] }
    }

    /// The Repeat model as a builder (nil for Never / Custom).
    var builder: RecurrenceBuilder? {
        let pattern: RecurrenceBuilder.Pattern
        switch repeatKind {
        case .never, .custom: return nil
        case .daily: pattern = .daily
        case .weekly: pattern = .weekly(weekdays.isEmpty ? [startDay.weekday] : weekdays)
        case .monthly:
            if monthlyByWeekday {
                let position = RecurrenceBuilder.weekdayPosition(of: startDay)
                pattern = .monthlyByWeekday(ordinal: position.ordinal > 4 ? -1 : position.ordinal, weekday: startDay.weekday)
            } else {
                pattern = .monthlyByDate(startDay.day)
            }
        case .yearly: pattern = .yearly
        }
        let end: RecurrenceBuilder.End
        switch endKind {
        case .never: end = .never
        case .onDate: end = .onDate(untilDay)
        case .after: end = .after(max(1, count))
        }
        return RecurrenceBuilder(pattern: pattern, interval: interval, end: end)
    }

    var repeatChanged: Bool {
        if repeatKind == .custom { return false }
        if repeatKind != initialKind { return true }
        return builder != initialRepeat
    }

    /// "Weekly on Thursday until Dec 10 · 12 left".
    func repeatSummary(now: Date) -> String? {
        guard let builder else { return repeatKind == .custom ? "Repeats on a custom schedule (kept as is)" : nil }
        var text = builder.summary
        if builder.end != .never {
            let seriesStart: Date
            if !repeatChanged, let master { seriesStart = master.startDate(in: zone) } else { seriesStart = startDate }
            let rule = builder.rrule(isAllDay: isAllDay, zone: zone)
            let left = rule.occurrences(start: seriesStart, zone: zone, isAllDay: isAllDay, limit: 1000).filter { $0 > now }.count
            text += " · \(left) left"
        }
        return text
    }

    var monthlyLabels: (byDate: String, byWeekday: String) {
        let position = RecurrenceBuilder.weekdayPosition(of: startDay)
        let ordinal = position.ordinal > 4 ? "last" : ["first", "second", "third", "fourth"][position.ordinal - 1]
        return ("On day \(startDay.day)", "On the \(ordinal) \(startDay.weekday.name)")
    }

    // MARK: Guests

    var organizerName: String? {
        guard let event = original?.event else { return nil }
        return event.organizer?.displayName ?? attendees.first { $0.organizer == true }?.displayName ?? event.organizer?.email
    }

    /// Invited by someone else (shows the RSVP bar).
    var isInvitation: Bool {
        guard let event = original?.event, let me = event.selfAttendee else { return false }
        return me.organizer != true && !event.isOrganizedBySelf
    }

    mutating func addGuests(from text: String) {
        let pieces = text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " || $0 == "\n" })
        for piece in pieces {
            let address = EmailAddress.parseList(String(piece)).first?.email ?? String(piece)
            let email = address.trimmingCharacters(in: CharacterSet(charactersIn: "<> ")).lowercased()
            guard email.contains("@"), email.contains("."), !attendees.contains(where: { $0.email.lowercased() == email }) else { continue }
            attendees.append(EventAttendee(email: email, responseStatus: .needsAction))
        }
        newGuest = ""
    }

    mutating func removeGuest(_ email: String) {
        attendees.removeAll { $0.email.lowercased() == email.lowercased() }
    }

    // MARK: Output

    /// The event to insert (new / duplicate).
    func newEvent() -> CalendarEvent {
        let html = descriptionHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        var event = CalendarEvent(summary: title.trimmingCharacters(in: .whitespaces), start: startValue, end: endValue,
                                  description: html.isEmpty ? nil : html,
                                  location: location.trimmingCharacters(in: .whitespaces).isEmpty ? nil : location.trimmingCharacters(in: .whitespaces),
                                  recurrence: builder.map { $0.recurrenceLines(isAllDay: isAllDay, zone: zone) },
                                  attendees: attendees.isEmpty ? nil : attendees, reminders: EventReminders(useDefault: true))
        event.status = nil
        return event
    }

    /// What changed, as a patch against the edited instance.
    func patch() -> EventPatch {
        guard let event = original?.event else { return EventPatch() }
        var patch = EventPatch()
        let newTitle = title.trimmingCharacters(in: .whitespaces)
        if newTitle != (event.summary ?? "") { patch.summary = newTitle }
        let newLocation = location.trimmingCharacters(in: .whitespaces)
        if newLocation != (event.location ?? "") { patch.location = newLocation }
        if descriptionEdited, descriptionHTML != HTMLSanitizer.eventDescription(event.description) { patch.description = descriptionHTML }
        if attendees != (event.attendees ?? []) { patch.attendees = attendees }
        let timesChanged: Bool
        if isAllDay != event.isAllDay {
            timesChanged = true
        } else if isAllDay {
            timesChanged = startValue.date != event.start.date || endValue.date != event.end.date
        } else {
            timesChanged = abs(startDate.timeIntervalSince(event.startDate(in: zone))) > 1 || abs(endDate.timeIntervalSince(event.endDate(in: zone))) > 1
        }
        if timesChanged {
            patch.start = startValue
            patch.end = endValue
        }
        if repeatChanged {
            patch.recurrence = builder.map { $0.recurrenceLines(isAllDay: isAllDay, zone: zone, keeping: master?.recurrence) } ?? []
        }
        return patch
    }
}
