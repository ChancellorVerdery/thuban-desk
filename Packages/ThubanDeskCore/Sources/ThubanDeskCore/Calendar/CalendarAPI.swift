import Foundation

/// Typed Google Calendar v3 requests. Building a request never performs it (tests assert on them); the
/// `GoogleClient` extension below performs them.
public enum CalendarEndpoints {
    static var base: URL { GoogleEndpoints.calendar }

    public static func calendarList(pageToken: String? = nil) -> GoogleRequest {
        .get(base, ["users", "me", "calendarList"], query: [("maxResults", "250"), ("pageToken", pageToken)])
    }

    /// Events overlapping `[from, to)`. `singleEvents: true` expands recurring series into instances (what views
    /// draw); edits to a series need the master — fetch it with `event(calendarID:eventID: instance.recurringEventId)`.
    public static func events(calendarID: String, from: Date, to: Date, singleEvents: Bool = true, query: String? = nil,
                              pageToken: String? = nil, maxResults: Int = 2500) -> GoogleRequest {
        .get(base, ["calendars", calendarID, "events"], query: [
            ("timeMin", RFC3339.string(from: from)),
            ("timeMax", RFC3339.string(from: to)),
            ("singleEvents", singleEvents ? "true" : "false"),
            ("orderBy", singleEvents ? "startTime" : nil),
            ("q", query?.isEmpty == false ? query : nil),
            ("maxResults", String(maxResults)),
            ("pageToken", pageToken),
        ])
    }

    public static func event(calendarID: String, eventID: String) -> GoogleRequest {
        .get(base, ["calendars", calendarID, "events", eventID])
    }

    public static func instances(calendarID: String, eventID: String, from: Date? = nil, to: Date? = nil, pageToken: String? = nil) -> GoogleRequest {
        .get(base, ["calendars", calendarID, "events", eventID, "instances"], query: [
            ("timeMin", from.map(RFC3339.string(from:))),
            ("timeMax", to.map(RFC3339.string(from:))),
            ("maxResults", "2500"),
            ("pageToken", pageToken),
        ])
    }

    public static func insert(_ event: CalendarEvent, calendarID: String, sendUpdates: SendUpdates = .none) -> GoogleRequest {
        .json("POST", base, ["calendars", calendarID, "events"], query: [("sendUpdates", sendUpdates.rawValue)], body: event)
    }

    public static func patch(_ patch: EventPatch, eventID: String, calendarID: String, sendUpdates: SendUpdates = .none) -> GoogleRequest {
        .json("PATCH", base, ["calendars", calendarID, "events", eventID], query: [("sendUpdates", sendUpdates.rawValue)], body: patch)
    }

    public static func delete(eventID: String, calendarID: String, sendUpdates: SendUpdates = .none) -> GoogleRequest {
        .bodiless("DELETE", base, ["calendars", calendarID, "events", eventID], query: [("sendUpdates", sendUpdates.rawValue)])
    }

    /// Creates a secondary calendar (it is added to the account's calendar list automatically).
    public static func createCalendar(_ calendar: NewCalendar) -> GoogleRequest {
        .json("POST", base, ["calendars"], body: calendar)
    }

    public static func request(for mutation: CalendarMutation, sendUpdates: SendUpdates = .none) -> GoogleRequest {
        switch mutation {
        case .insert(let calendarID, let event): return insert(event, calendarID: calendarID, sendUpdates: sendUpdates)
        case .patch(let calendarID, let eventID, let patch): return self.patch(patch, eventID: eventID, calendarID: calendarID, sendUpdates: sendUpdates)
        case .delete(let calendarID, let eventID): return delete(eventID: eventID, calendarID: calendarID, sendUpdates: sendUpdates)
        }
    }

    /// The attendee list with the signed-in user's `responseStatus` changed (RSVP is a patch of `attendees`).
    /// Returns nil when the user is not on the guest list.
    public static func rsvpPatch(for event: CalendarEvent, status: ResponseStatus, selfEmail: String) -> EventPatch? {
        guard var attendees = event.attendees else { return nil }
        guard let index = attendees.firstIndex(where: { $0.isSelf == true }) ?? attendees.firstIndex(where: { $0.email.lowercased() == selfEmail.lowercased() })
        else { return nil }
        attendees[index].responseStatus = status
        return EventPatch(attendees: attendees)
    }
}

extension GoogleClient {
    // MARK: Calendars

    public func calendarList() async throws -> [CalendarListEntry] {
        try await paginate(CalendarListPage.self) { CalendarEndpoints.calendarList(pageToken: $0) }
            .filter { $0.deleted != true }
    }

    public func createCalendar(_ calendar: NewCalendar) async throws -> CalendarResource {
        try await decode(CalendarResource.self, CalendarEndpoints.createCalendar(calendar))
    }

    /// The owned calendar named `summary` (case-insensitive), creating it when missing — for dedicated calendars
    /// ("Thuban", "Classes", …). Returns the calendar id.
    @discardableResult
    public func findOrCreateCalendar(named summary: String, timeZone: String? = TimeZone.current.identifier, description: String? = nil) async throws -> String {
        let wanted = summary.trimmingCharacters(in: .whitespaces).lowercased()
        if let existing = try await calendarList().first(where: { $0.canWrite && ($0.summary ?? "").lowercased() == wanted }) {
            return existing.id
        }
        return try await createCalendar(NewCalendar(summary: summary, timeZone: timeZone, description: description)).id
    }

    // MARK: Events

    public func events(calendarID: String, from: Date, to: Date, singleEvents: Bool = true, query: String? = nil) async throws -> [CalendarEvent] {
        try await paginate(EventsPage.self) {
            CalendarEndpoints.events(calendarID: calendarID, from: from, to: to, singleEvents: singleEvents, query: query, pageToken: $0)
        }
    }

    public func event(calendarID: String, eventID: String) async throws -> CalendarEvent {
        try await decode(CalendarEvent.self, CalendarEndpoints.event(calendarID: calendarID, eventID: eventID))
    }

    /// The recurring master for an instance (or the event itself when it is not an instance).
    public func master(of event: CalendarEvent, calendarID: String) async throws -> CalendarEvent {
        guard let masterID = event.recurringEventId else { return event }
        return try await self.event(calendarID: calendarID, eventID: masterID)
    }

    public func instances(calendarID: String, eventID: String, from: Date? = nil, to: Date? = nil) async throws -> [CalendarEvent] {
        try await paginate(EventsPage.self) { CalendarEndpoints.instances(calendarID: calendarID, eventID: eventID, from: from, to: to, pageToken: $0) }
    }

    @discardableResult
    public func insertEvent(_ event: CalendarEvent, calendarID: String, sendUpdates: SendUpdates = .none) async throws -> CalendarEvent {
        try await decode(CalendarEvent.self, CalendarEndpoints.insert(event, calendarID: calendarID, sendUpdates: sendUpdates))
    }

    @discardableResult
    public func patchEvent(_ patch: EventPatch, eventID: String, calendarID: String, sendUpdates: SendUpdates = .none) async throws -> CalendarEvent {
        try await decode(CalendarEvent.self, CalendarEndpoints.patch(patch, eventID: eventID, calendarID: calendarID, sendUpdates: sendUpdates))
    }

    /// Deletes an event (an already-deleted event — 404 / 410 — counts as done).
    public func deleteEvent(eventID: String, calendarID: String, sendUpdates: SendUpdates = .none) async throws {
        do {
            try await data(CalendarEndpoints.delete(eventID: eventID, calendarID: calendarID, sendUpdates: sendUpdates))
        } catch let error as ThubanError where error.isNotFound {
            return
        }
    }

    /// Runs a plan from `RecurrenceEditPlanner` in order. Returns the events Google sent back (inserts and patches).
    @discardableResult
    public func perform(_ mutations: [CalendarMutation], sendUpdates: SendUpdates = .none) async throws -> [CalendarEvent] {
        var results: [CalendarEvent] = []
        for mutation in mutations {
            switch mutation {
            case .insert(let calendarID, let event):
                results.append(try await insertEvent(event, calendarID: calendarID, sendUpdates: sendUpdates))
            case .patch(let calendarID, let eventID, let patch):
                results.append(try await patchEvent(patch, eventID: eventID, calendarID: calendarID, sendUpdates: sendUpdates))
            case .delete(let calendarID, let eventID):
                try await deleteEvent(eventID: eventID, calendarID: calendarID, sendUpdates: sendUpdates)
            }
        }
        return results
    }

    /// Answers an invitation (Yes / Maybe / No) by patching the user's own attendee entry. For an occurrence of a
    /// repeating invitation the answer covers the whole series (as Google Calendar's invitation buttons do): the
    /// master's attendee list is patched, then the occurrence is re-read and patched too only when it is an
    /// exception that kept its own answer. Returns the answered occurrence (or event).
    @discardableResult
    public func rsvp(_ status: ResponseStatus, to event: CalendarEvent, calendarID: String, selfEmail: String,
                     sendUpdates: SendUpdates = .all) async throws -> CalendarEvent {
        let notOnList = ThubanError.http(status: 400, message: "You are not on this event's guest list.", reason: "notAnAttendee")
        if event.recurringEventId != nil {
            let master = try await master(of: event, calendarID: calendarID)
            guard let seriesPatch = CalendarEndpoints.rsvpPatch(for: master, status: status, selfEmail: selfEmail) else { throw notOnList }
            try await patchEvent(seriesPatch, eventID: master.id, calendarID: calendarID, sendUpdates: sendUpdates)
            let occurrence = (try? await self.event(calendarID: calendarID, eventID: event.id)) ?? event
            if occurrence.selfResponse == status { return occurrence }
            guard let patch = CalendarEndpoints.rsvpPatch(for: occurrence, status: status, selfEmail: selfEmail) else { return occurrence }
            return try await patchEvent(patch, eventID: event.id, calendarID: calendarID, sendUpdates: .none)
        }
        guard let patch = CalendarEndpoints.rsvpPatch(for: event, status: status, selfEmail: selfEmail) else { throw notOnList }
        return try await patchEvent(patch, eventID: event.id, calendarID: calendarID, sendUpdates: sendUpdates)
    }
}

// MARK: - Month windows (cache + prefetch granularity)

/// A calendar month; the calendar caches events per (calendar, month) and prefetches neighbouring months.
public struct YearMonth: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int

    public init(year: Int, month: Int) {
        let index = year * 12 + (month - 1)
        self.year = Int((Double(index) / 12).rounded(.down))
        self.month = index - self.year * 12 + 1
    }

    public init(_ date: CivilDate) { self.init(year: date.year, month: date.month) }
    public init(_ date: Date, in zone: TimeZone) { self.init(CivilDate(date, in: zone)) }

    public var description: String { String(format: "%04d-%02d", year, month) }
    public static func < (a: YearMonth, b: YearMonth) -> Bool { (a.year, a.month) < (b.year, b.month) }

    public func adding(months: Int) -> YearMonth { YearMonth(year: year, month: month + months) }
    public var firstDay: CivilDate { CivilDate(year: year, month: month, day: 1) }

    /// `[start of month, start of next month)` in `zone`.
    public func interval(in zone: TimeZone) -> DateInterval {
        DateInterval(start: firstDay.startDate(in: zone), end: adding(months: 1).firstDay.startDate(in: zone))
    }

    /// Every month overlapping `[from, to)`.
    public static func covering(from: Date, to: Date, in zone: TimeZone) -> [YearMonth] {
        let first = YearMonth(from, in: zone)
        let last = YearMonth(to.addingTimeInterval(-1), in: zone)
        var months: [YearMonth] = []
        var cursor = first
        while cursor <= last, months.count < 240 {
            months.append(cursor)
            cursor = cursor.adding(months: 1)
        }
        return months
    }
}
