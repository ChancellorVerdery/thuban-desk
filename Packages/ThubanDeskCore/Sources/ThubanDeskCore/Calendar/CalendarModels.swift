import Foundation

// MARK: - Calendar list

/// `calendarList` entry (a calendar the account can see).
public struct CalendarListEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var summary: String?
    public var summaryOverride: String?
    public var description: String?
    public var location: String?
    public var timeZone: String?
    public var colorId: String?
    public var backgroundColor: String?
    public var foregroundColor: String?
    public var hidden: Bool?
    public var selected: Bool?
    /// owner / writer / reader / freeBusyReader
    public var accessRole: String?
    public var primary: Bool?
    public var deleted: Bool?
    public var defaultReminders: [ReminderOverride]?

    public init(id: String, summary: String? = nil, timeZone: String? = nil, backgroundColor: String? = nil, accessRole: String? = "owner",
                primary: Bool? = nil, selected: Bool? = true) {
        self.id = id
        self.summary = summary
        self.timeZone = timeZone
        self.backgroundColor = backgroundColor
        self.accessRole = accessRole
        self.primary = primary
        self.selected = selected
    }

    public var displayName: String { summaryOverride ?? summary ?? id }
    public var isPrimary: Bool { primary ?? false }
    /// Events can be created / edited here.
    public var canWrite: Bool { accessRole == "owner" || accessRole == "writer" }
    public var zone: TimeZone { timeZone.flatMap(TimeZone.init(identifier:)) ?? .current }
    /// Colour role derived from Google's colour (the app may override it per calendar).
    public var defaultTint: CalendarTint { CalendarTint.from(googleHex: backgroundColor) }
}

public struct CalendarListPage: GooglePage {
    public var items: [CalendarListEntry]?
    public var nextPageToken: String?
    public var pageItems: [CalendarListEntry] { items ?? [] }
}

/// Body for `POST /calendars` (secondary calendar).
public struct NewCalendar: Codable, Sendable, Equatable {
    public var summary: String
    public var timeZone: String?
    public var description: String?

    public init(summary: String, timeZone: String? = nil, description: String? = nil) {
        self.summary = summary
        self.timeZone = timeZone
        self.description = description
    }
}

/// `calendars` resource (response of `POST /calendars`).
public struct CalendarResource: Codable, Sendable, Equatable {
    public var id: String
    public var summary: String?
    public var timeZone: String?
}

// MARK: - Event times

/// `start` / `end`: `date` for all-day events (end is exclusive), `dateTime` + `timeZone` for timed ones.
/// Encoding writes the unused field as `null` so a patch can switch between all-day and timed.
public struct EventDateTime: Codable, Hashable, Sendable {
    public var date: CivilDate?
    public var dateTime: Date?
    public var timeZone: String?

    public init(date: CivilDate? = nil, dateTime: Date? = nil, timeZone: String? = nil) {
        self.date = date
        self.dateTime = dateTime
        self.timeZone = timeZone
    }

    public static func allDay(_ date: CivilDate) -> EventDateTime { EventDateTime(date: date) }
    public static func timed(_ date: Date, timeZone: String?) -> EventDateTime { EventDateTime(dateTime: date, timeZone: timeZone) }

    public var isAllDay: Bool { date != nil && dateTime == nil }
    public var zone: TimeZone? { timeZone.flatMap(TimeZone.init(identifier:)) }

    /// The instant: `dateTime`, or midnight of `date` in `fallback` (all-day events float in the viewer's zone).
    public func instant(in fallback: TimeZone = .current) -> Date {
        if let dateTime { return dateTime }
        return date?.startDate(in: fallback) ?? Date(timeIntervalSince1970: 0)
    }

    /// The calendar date in `zone` (timed) or the stored date (all-day).
    public func civilDate(in zone: TimeZone = .current) -> CivilDate {
        if let date, dateTime == nil { return date }
        return CivilDate(dateTime ?? Date(timeIntervalSince1970: 0), in: zone)
    }

    enum CodingKeys: String, CodingKey { case date, dateTime, timeZone }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(CivilDate.self, forKey: .date)
        if let text = try c.decodeIfPresent(String.self, forKey: .dateTime) {
            guard let parsed = RFC3339.date(from: text) else {
                throw DecodingError.dataCorruptedError(forKey: .dateTime, in: c, debugDescription: "Bad dateTime \(text)")
            }
            dateTime = parsed
        }
        timeZone = try c.decodeIfPresent(String.self, forKey: .timeZone)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let dateTime {
            let zone = self.zone ?? TimeZone(identifier: "UTC")!
            try c.encode(RFC3339.string(from: dateTime, in: zone), forKey: .dateTime)
            try c.encodeNil(forKey: .date)
            try c.encodeIfPresent(timeZone, forKey: .timeZone)
        } else if let date {
            try c.encode(date, forKey: .date)
            try c.encodeNil(forKey: .dateTime)
            try c.encodeIfPresent(timeZone, forKey: .timeZone)
        }
    }
}

// MARK: - Attendees, reminders

public enum ResponseStatus: String, Codable, CaseIterable, Sendable {
    case needsAction, declined, tentative, accepted

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ResponseStatus(rawValue: raw) ?? .needsAction
    }

    public var label: String {
        switch self {
        case .needsAction: return "Not answered"
        case .declined: return "No"
        case .tentative: return "Maybe"
        case .accepted: return "Yes"
        }
    }
}

public struct EventAttendee: Codable, Hashable, Sendable {
    public var email: String
    public var displayName: String?
    public var organizer: Bool?
    public var isSelf: Bool?
    public var resource: Bool?
    public var optional: Bool?
    public var responseStatus: ResponseStatus?
    public var comment: String?
    public var additionalGuests: Int?

    enum CodingKeys: String, CodingKey {
        case email, displayName, organizer, isSelf = "self", resource, optional, responseStatus, comment, additionalGuests
    }

    public init(email: String, displayName: String? = nil, organizer: Bool? = nil, isSelf: Bool? = nil, optional: Bool? = nil,
                responseStatus: ResponseStatus? = .needsAction) {
        self.email = email
        self.displayName = displayName
        self.organizer = organizer
        self.isSelf = isSelf
        self.optional = optional
        self.responseStatus = responseStatus
    }

    public var name: String { displayName ?? email }
}

public struct EventPerson: Codable, Hashable, Sendable {
    public var email: String?
    public var displayName: String?
    public var isSelf: Bool?

    enum CodingKeys: String, CodingKey { case email, displayName, isSelf = "self" }

    public init(email: String?, displayName: String? = nil, isSelf: Bool? = nil) {
        self.email = email
        self.displayName = displayName
        self.isSelf = isSelf
    }
}

public struct ReminderOverride: Codable, Hashable, Sendable {
    /// "popup" or "email".
    public var method: String
    public var minutes: Int

    public init(method: String = "popup", minutes: Int) {
        self.method = method
        self.minutes = minutes
    }
}

public struct EventReminders: Codable, Hashable, Sendable {
    public var useDefault: Bool
    public var overrides: [ReminderOverride]?

    public init(useDefault: Bool = true, overrides: [ReminderOverride]? = nil) {
        self.useDefault = useDefault
        self.overrides = overrides
    }
}

public struct ConferenceEntryPoint: Codable, Hashable, Sendable {
    public var entryPointType: String?
    public var uri: String?
    public var label: String?
}

public struct ConferenceData: Codable, Hashable, Sendable {
    public var entryPoints: [ConferenceEntryPoint]?
    public var conferenceSolution: ConferenceSolution?

    public struct ConferenceSolution: Codable, Hashable, Sendable { public var name: String? }

    /// The video link, if any.
    public var videoURI: String? { entryPoints?.first { $0.entryPointType == "video" }?.uri }
}

// MARK: - Event

/// A Google Calendar event (an instance when listed with `singleEvents=true`, or a recurring master).
public struct CalendarEvent: Codable, Hashable, Sendable, Identifiable {
    /// Empty for an event not yet inserted (omitted when encoding).
    public var id: String
    /// confirmed / tentative / cancelled
    public var status: String?
    public var htmlLink: String?
    public var created: Date?
    public var updated: Date?
    public var summary: String?
    /// HTML or plain text; sanitize before display (`HTMLSanitizer.eventDescription`).
    public var description: String?
    public var location: String?
    public var colorId: String?
    public var creator: EventPerson?
    public var organizer: EventPerson?
    public var start: EventDateTime
    public var end: EventDateTime
    public var endTimeUnspecified: Bool?
    /// RRULE / EXRULE / RDATE / EXDATE lines (masters only).
    public var recurrence: [String]?
    /// Set on instances of a recurring event: the master's id.
    public var recurringEventId: String?
    /// Set on instances: the unmodified start of this occurrence (identifies it within the series).
    public var originalStartTime: EventDateTime?
    /// opaque (busy) / transparent (free)
    public var transparency: String?
    public var visibility: String?
    public var iCalUID: String?
    public var sequence: Int?
    public var attendees: [EventAttendee]?
    public var attendeesOmitted: Bool?
    public var hangoutLink: String?
    public var conferenceData: ConferenceData?
    public var reminders: EventReminders?
    /// default / outOfOffice / focusTime / workingLocation / birthday / fromGmail
    public var eventType: String?
    public var guestsCanModify: Bool?
    public var guestsCanInviteOthers: Bool?
    public var guestsCanSeeOtherGuests: Bool?

    public init(id: String = "", summary: String?, start: EventDateTime, end: EventDateTime, description: String? = nil, location: String? = nil,
                recurrence: [String]? = nil, attendees: [EventAttendee]? = nil, reminders: EventReminders? = nil, status: String? = "confirmed") {
        self.id = id
        self.summary = summary
        self.start = start
        self.end = end
        self.description = description
        self.location = location
        self.recurrence = recurrence
        self.attendees = attendees
        self.reminders = reminders
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id, status, htmlLink, created, updated, summary, description, location, colorId, creator, organizer, start, end,
             endTimeUnspecified, recurrence, recurringEventId, originalStartTime, transparency, visibility, iCalUID, sequence,
             attendees, attendeesOmitted, hangoutLink, conferenceData, reminders, eventType, guestsCanModify, guestsCanInviteOthers,
             guestsCanSeeOtherGuests
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status)
        htmlLink = try c.decodeIfPresent(String.self, forKey: .htmlLink)
        created = try c.decodeIfPresent(Date.self, forKey: .created)
        updated = try c.decodeIfPresent(Date.self, forKey: .updated)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        colorId = try c.decodeIfPresent(String.self, forKey: .colorId)
        creator = try c.decodeIfPresent(EventPerson.self, forKey: .creator)
        organizer = try c.decodeIfPresent(EventPerson.self, forKey: .organizer)
        // Cancelled instances in an incremental list carry no start/end.
        start = try c.decodeIfPresent(EventDateTime.self, forKey: .start) ?? EventDateTime()
        end = try c.decodeIfPresent(EventDateTime.self, forKey: .end) ?? EventDateTime()
        endTimeUnspecified = try c.decodeIfPresent(Bool.self, forKey: .endTimeUnspecified)
        recurrence = try c.decodeIfPresent([String].self, forKey: .recurrence)
        recurringEventId = try c.decodeIfPresent(String.self, forKey: .recurringEventId)
        originalStartTime = try c.decodeIfPresent(EventDateTime.self, forKey: .originalStartTime)
        transparency = try c.decodeIfPresent(String.self, forKey: .transparency)
        visibility = try c.decodeIfPresent(String.self, forKey: .visibility)
        iCalUID = try c.decodeIfPresent(String.self, forKey: .iCalUID)
        sequence = try c.decodeIfPresent(Int.self, forKey: .sequence)
        attendees = try c.decodeIfPresent([EventAttendee].self, forKey: .attendees)
        attendeesOmitted = try c.decodeIfPresent(Bool.self, forKey: .attendeesOmitted)
        hangoutLink = try c.decodeIfPresent(String.self, forKey: .hangoutLink)
        conferenceData = try c.decodeIfPresent(ConferenceData.self, forKey: .conferenceData)
        reminders = try c.decodeIfPresent(EventReminders.self, forKey: .reminders)
        eventType = try c.decodeIfPresent(String.self, forKey: .eventType)
        guestsCanModify = try c.decodeIfPresent(Bool.self, forKey: .guestsCanModify)
        guestsCanInviteOthers = try c.decodeIfPresent(Bool.self, forKey: .guestsCanInviteOthers)
        guestsCanSeeOtherGuests = try c.decodeIfPresent(Bool.self, forKey: .guestsCanSeeOtherGuests)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !id.isEmpty { try c.encode(id, forKey: .id) }
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(htmlLink, forKey: .htmlLink)
        try c.encodeIfPresent(created, forKey: .created)
        try c.encodeIfPresent(updated, forKey: .updated)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(colorId, forKey: .colorId)
        try c.encodeIfPresent(creator, forKey: .creator)
        try c.encodeIfPresent(organizer, forKey: .organizer)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encodeIfPresent(endTimeUnspecified, forKey: .endTimeUnspecified)
        try c.encodeIfPresent(recurrence, forKey: .recurrence)
        try c.encodeIfPresent(recurringEventId, forKey: .recurringEventId)
        try c.encodeIfPresent(originalStartTime, forKey: .originalStartTime)
        try c.encodeIfPresent(transparency, forKey: .transparency)
        try c.encodeIfPresent(visibility, forKey: .visibility)
        try c.encodeIfPresent(iCalUID, forKey: .iCalUID)
        try c.encodeIfPresent(sequence, forKey: .sequence)
        try c.encodeIfPresent(attendees, forKey: .attendees)
        try c.encodeIfPresent(attendeesOmitted, forKey: .attendeesOmitted)
        try c.encodeIfPresent(hangoutLink, forKey: .hangoutLink)
        try c.encodeIfPresent(conferenceData, forKey: .conferenceData)
        try c.encodeIfPresent(reminders, forKey: .reminders)
        try c.encodeIfPresent(eventType, forKey: .eventType)
        try c.encodeIfPresent(guestsCanModify, forKey: .guestsCanModify)
        try c.encodeIfPresent(guestsCanInviteOthers, forKey: .guestsCanInviteOthers)
        try c.encodeIfPresent(guestsCanSeeOtherGuests, forKey: .guestsCanSeeOtherGuests)
    }

    // MARK: Derived

    public var title: String { (summary?.isEmpty == false ? summary : nil) ?? "(No title)" }
    public var isAllDay: Bool { start.isAllDay }
    public var isCancelled: Bool { status == "cancelled" }
    public var isRecurringInstance: Bool { recurringEventId != nil }
    public var isRecurringMaster: Bool { recurrence?.contains { $0.hasPrefix("RRULE") } ?? false }
    /// The master's id for an instance, else the event's own id.
    public var seriesID: String { recurringEventId ?? id }
    public var isFree: Bool { transparency == "transparent" }

    /// The signed-in user's attendee entry (Google marks it `self: true`).
    public var selfAttendee: EventAttendee? { attendees?.first { $0.isSelf == true } }
    public var selfResponse: ResponseStatus? { selfAttendee?.responseStatus }
    /// An invitation the user has not answered and did not organize.
    public var needsResponse: Bool { selfAttendee.map { $0.responseStatus == .needsAction && $0.organizer != true } ?? false }
    public var isOrganizedBySelf: Bool { organizer?.isSelf ?? (attendees == nil) }

    /// The RRULE of a master, parsed.
    public var rrule: RRule? { recurrence?.lazy.compactMap { RRule(line: $0) }.first }

    public func startDate(in zone: TimeZone = .current) -> Date { start.instant(in: zone) }
    public func endDate(in zone: TimeZone = .current) -> Date { end.instant(in: zone) }
    public var duration: TimeInterval { end.instant(in: .current).timeIntervalSince(start.instant(in: .current)) }
    /// Video call link: Meet (`hangoutLink`) or a conference entry point.
    public var videoLink: String? { hangoutLink ?? conferenceData?.videoURI }
}

public struct EventsPage: GooglePage {
    public var items: [CalendarEvent]?
    public var nextPageToken: String?
    public var nextSyncToken: String?
    public var timeZone: String?
    public var summary: String?
    public var accessRole: String?
    public var defaultReminders: [ReminderOverride]?
    public var pageItems: [CalendarEvent] { items ?? [] }
}

/// A partial event for `PATCH`: only the fields that are set are sent. For recurring-edit plans, `start` / `end`
/// describe the edited instance's new times.
public struct EventPatch: Codable, Hashable, Sendable {
    public var summary: String?
    public var description: String?
    public var location: String?
    public var colorId: String?
    public var start: EventDateTime?
    public var end: EventDateTime?
    public var recurrence: [String]?
    public var attendees: [EventAttendee]?
    public var reminders: EventReminders?
    public var transparency: String?
    public var visibility: String?
    public var status: String?

    public init(summary: String? = nil, description: String? = nil, location: String? = nil, colorId: String? = nil,
                start: EventDateTime? = nil, end: EventDateTime? = nil, recurrence: [String]? = nil, attendees: [EventAttendee]? = nil,
                reminders: EventReminders? = nil, transparency: String? = nil, visibility: String? = nil, status: String? = nil) {
        self.summary = summary
        self.description = description
        self.location = location
        self.colorId = colorId
        self.start = start
        self.end = end
        self.recurrence = recurrence
        self.attendees = attendees
        self.reminders = reminders
        self.transparency = transparency
        self.visibility = visibility
        self.status = status
    }

    public var isEmpty: Bool { self == EventPatch() }
    public var changesTime: Bool { start != nil || end != nil }

    /// Applies the non-time fields to an event (times are handled by the caller).
    public func applyingFields(to event: CalendarEvent) -> CalendarEvent {
        var copy = event
        if let summary { copy.summary = summary }
        if let description { copy.description = description }
        if let location { copy.location = location }
        if let colorId { copy.colorId = colorId }
        if let attendees { copy.attendees = attendees }
        if let reminders { copy.reminders = reminders }
        if let transparency { copy.transparency = transparency }
        if let visibility { copy.visibility = visibility }
        if let status { copy.status = status }
        if let recurrence { copy.recurrence = recurrence }
        return copy
    }

    /// Everything the editor can change, as a patch (used to turn a full edited event into a patch).
    public static func diff(from old: CalendarEvent, to new: CalendarEvent) -> EventPatch {
        var patch = EventPatch()
        if old.summary != new.summary { patch.summary = new.summary ?? "" }
        if old.description != new.description { patch.description = new.description ?? "" }
        if old.location != new.location { patch.location = new.location ?? "" }
        if old.colorId != new.colorId { patch.colorId = new.colorId }
        if old.start != new.start { patch.start = new.start }
        if old.end != new.end { patch.end = new.end }
        if old.attendees != new.attendees { patch.attendees = new.attendees ?? [] }
        if old.reminders != new.reminders { patch.reminders = new.reminders }
        if old.transparency != new.transparency { patch.transparency = new.transparency }
        if old.visibility != new.visibility { patch.visibility = new.visibility }
        if old.recurrence != new.recurrence { patch.recurrence = new.recurrence ?? [] }
        return patch
    }
}

/// `sendUpdates` for inserts / patches / deletes that touch guests.
public enum SendUpdates: String, Sendable {
    case all, externalOnly, none
}
