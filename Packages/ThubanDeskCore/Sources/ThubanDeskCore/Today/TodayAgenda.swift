import Foundation

/// An event placed on a day, tagged with where it lives (for colour and editing).
public struct AgendaEvent: Hashable, Sendable, Identifiable {
    public var calendar: CalendarKey
    public var event: CalendarEvent
    public var tint: CalendarTint

    public init(calendar: CalendarKey, event: CalendarEvent, tint: CalendarTint = .accent) {
        self.calendar = calendar
        self.event = event
        self.tint = tint
    }

    public var id: String { "\(calendar)|\(event.id)" }
    public func start(in zone: TimeZone) -> Date { event.startDate(in: zone) }
    public func end(in zone: TimeZone) -> Date { event.endDate(in: zone) }
}

/// Today's agenda (design: "Today · 4 events", Done / Now · 65 min left / in 4 h 20 m, "Free 3:45 – 7:00 PM · 3 h 15 m").
public enum TodayAgenda {
    public enum Status: Hashable, Sendable {
        case done
        /// Happening now; seconds left.
        case now(remaining: TimeInterval)
        /// Starts later; seconds until.
        case upcoming(startsIn: TimeInterval)
    }

    public enum Entry: Hashable, Sendable, Identifiable {
        case allDay(AgendaEvent)
        case event(AgendaEvent, Status)
        case free(DateInterval)
        /// Where "now" falls between two entries when nothing is happening.
        case nowMarker(Date)

        public var id: String {
            switch self {
            case .allDay(let item): return "allday|\(item.id)"
            case .event(let item, _): return "event|\(item.id)"
            case .free(let interval): return "free|\(interval.start.timeIntervalSince1970)"
            case .nowMarker: return "now"
            }
        }
    }

    /// Builds the day's entries: all-day first, then timed events in order with their status; free gaps of at least
    /// `minimumGap` between events that end after `now` (between the day's first and last timed events); a now
    /// marker when now is between events. Cancelled and declined events are skipped.
    public static func build(events: [AgendaEvent], day: CivilDate, now: Date, zone: TimeZone = .current,
                             minimumGap: TimeInterval = 30 * 60) -> [Entry] {
        let dayStart = day.startDate(in: zone)
        let dayEnd = day.adding(days: 1).startDate(in: zone)
        let visible = events.filter { !$0.event.isCancelled && $0.event.selfResponse != .declined }
        let allDay = visible.filter { item in
            item.event.isAllDay && (item.event.start.date ?? day) <= day && (item.event.end.date ?? day.adding(days: 1)) > day
        }
        let timed = visible
            .filter { !$0.event.isAllDay && $0.start(in: zone) < dayEnd && $0.end(in: zone) > dayStart }
            .sorted { ($0.start(in: zone), $0.event.title) < ($1.start(in: zone), $1.event.title) }

        var entries: [Entry] = allDay.map { .allDay($0) }
        var cursor: Date?
        var placedNow = now < dayStart || now >= dayEnd
        for item in timed {
            let start = item.start(in: zone), end = item.end(in: zone)
            if let cursor, start.timeIntervalSince(cursor) >= minimumGap, start > now {
                let gapStart = max(cursor, now)
                if !placedNow, now >= cursor, now < start {
                    entries.append(.nowMarker(now))
                    placedNow = true
                }
                if start.timeIntervalSince(gapStart) >= minimumGap { entries.append(.free(DateInterval(start: gapStart, end: start))) }
            } else if !placedNow, now < start, cursor.map({ now >= $0 }) ?? true {
                entries.append(.nowMarker(now))
                placedNow = true
            }
            let status: Status
            if end <= now { status = .done } else if start <= now { status = .now(remaining: end.timeIntervalSince(now)); placedNow = true } else { status = .upcoming(startsIn: start.timeIntervalSince(now)) }
            entries.append(.event(item, status))
            cursor = max(cursor ?? end, end)
        }
        if !placedNow { entries.append(.nowMarker(now)) }
        return entries
    }

    /// "3 h 15 m", "65 min", "4 h 20 m".
    public static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 90, minutes % 60 != 0 || minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) m"
    }

    /// Invitations the user has not answered, upcoming first (Today's "Invitation" card and the Calendar sidebar).
    public static func pendingInvitations(_ events: [AgendaEvent], after now: Date, zone: TimeZone = .current) -> [AgendaEvent] {
        var seen = Set<String>()
        return events
            .filter { $0.event.needsResponse && !$0.event.isCancelled && $0.end(in: zone) > now }
            .sorted { $0.start(in: zone) < $1.start(in: zone) }
            .filter { seen.insert($0.event.iCalUID ?? $0.id).inserted }
    }
}
