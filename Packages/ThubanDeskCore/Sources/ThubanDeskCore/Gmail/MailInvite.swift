import Foundation

/// The invitation card in the mail reader: which calendar invitation a message is about, a one-line summary, and
/// whether the user is free then ("Free then — after PHYS 2102 ends at 2:15").
public enum MailInvite {
    /// The invitation a message refers to: an event the user was invited to (has a `self` attendee, not organized by
    /// the user) whose organizer — or, failing that, a guest — is the message's sender, starting after the message
    /// was sent (minus a day). The soonest such event wins.
    public static func match(_ message: MailMessage, candidates: [AgendaEvent], zone: TimeZone = .current) -> AgendaEvent? {
        guard let sender = message.from?.normalized else { return nil }
        let invited = candidates.filter { item in
            let event = item.event
            guard !event.isCancelled, event.selfAttendee != nil, event.organizer?.isSelf != true, event.selfAttendee?.organizer != true else { return false }
            return item.start(in: zone) >= message.date.addingTimeInterval(-86_400)
        }
        func soonest(_ list: [AgendaEvent]) -> AgendaEvent? { list.min { $0.start(in: zone) < $1.start(in: zone) } }
        if let byOrganizer = soonest(invited.filter { $0.event.organizer?.email?.lowercased() == sender }) { return byOrganizer }
        return soonest(invited.filter { $0.event.attendees?.contains { $0.email.lowercased() == sender && $0.isSelf != true } ?? false })
    }

    /// "3:00 – 3:45 PM · Zoom · Priya Shah, Marcus Lee" (all-day: "All day · …").
    public static func detailLine(_ event: CalendarEvent, zone: TimeZone = .current) -> String {
        var parts: [String] = []
        if event.isAllDay {
            parts.append("All day")
        } else {
            parts.append(timeRange(event.startDate(in: zone), event.endDate(in: zone), zone: zone))
        }
        if let place = place(event) { parts.append(place) }
        let others = (event.attendees ?? []).filter { $0.isSelf != true && $0.resource != true }
        if !others.isEmpty {
            let names = others.prefix(3).map { $0.displayName ?? String($0.email.split(separator: "@").first ?? "") }
            parts.append(names.joined(separator: ", ") + (others.count > 3 ? " +\(others.count - 3)" : ""))
        }
        return parts.joined(separator: " · ")
    }

    /// "Zoom", "Google Meet", "Teams" for a video link, else the location's first line.
    public static func place(_ event: CalendarEvent) -> String? {
        if let link = event.videoLink?.lowercased() {
            if link.contains("zoom.") { return "Zoom" }
            if link.contains("meet.google") { return "Google Meet" }
            if link.contains("teams.") { return "Teams" }
            if let name = event.conferenceData?.conferenceSolution?.name { return name }
            return "Video call"
        }
        guard let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty else { return nil }
        return location.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    /// "3:00 – 3:45 PM", "11:30 AM – 12:15 PM".
    public static func timeRange(_ start: Date, _ end: Date, zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        f.dateFormat = "a"
        let sameHalf = f.string(from: start) == f.string(from: end)
        f.dateFormat = sameHalf ? "h:mm" : "h:mm a"
        let first = f.string(from: start)
        f.dateFormat = "h:mm a"
        return "\(first) – \(f.string(from: end))"
    }

    public enum Availability: Hashable, Sendable {
        /// Nothing overlaps; `after` is the latest earlier event that day (title, end).
        case free(after: String?, endsAt: Date?)
        /// Overlaps these events (titles).
        case conflict([String])
        case allDay
    }

    /// Whether the user is free during `event`, from the other (not declined, not free/transparent) events of that day.
    public static func availability(of event: CalendarEvent, among others: [AgendaEvent], zone: TimeZone = .current) -> Availability {
        if event.isAllDay { return .allDay }
        let start = event.startDate(in: zone), end = event.endDate(in: zone)
        let day = CivilDate(start, in: zone)
        let busy = others.filter { item in
            let e = item.event
            return e.id != event.id && e.seriesID != event.id && !e.isAllDay && !e.isCancelled && !e.isFree
                && e.selfResponse != .declined && CivilDate(item.start(in: zone), in: zone) == day
        }
        let overlapping = busy.filter { $0.start(in: zone) < end && $0.end(in: zone) > start }
        if !overlapping.isEmpty {
            return .conflict(overlapping.sorted { $0.start(in: zone) < $1.start(in: zone) }.map(\.event.title))
        }
        let before = busy.filter { $0.end(in: zone) <= start }.max { $0.end(in: zone) < $1.end(in: zone) }
        return .free(after: before?.event.title, endsAt: before?.end(in: zone))
    }

    /// "PHYS 2102 · Physics II" → "PHYS 2102" (the part before " · ").
    public static func shortTitle(_ title: String) -> String {
        title.components(separatedBy: " · ").first?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? title
    }

    /// "Free then — after PHYS 2102 ends at 2:15", "Free then", "Conflicts with Study group", "All day".
    public static func availabilityText(_ availability: Availability, zone: TimeZone = .current) -> String {
        switch availability {
        case .allDay: return "All day"
        case .conflict(let titles):
            let names = titles.map(shortTitle)
            return "Conflicts with " + (names.count > 2 ? "\(names[0]) and \(names.count - 1) more" : names.joined(separator: " and "))
        case .free(let title?, let end?):
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = zone
            f.dateFormat = "h:mm"
            return "Free then — after \(shortTitle(title)) ends at \(f.string(from: end))"
        case .free:
            return "Free then"
        }
    }
}
