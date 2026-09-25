import Foundation

/// Ties "needs a reply" threads to the calendar (Today): Priya's thread is "About the invitation for Fri 3:00 PM —
/// answer it below"; Maya's is "For Study group tonight at 7:00 PM", and the Study group row shows her question.
/// Also the small phrases the Today cards print (clock labels, conflicts, guest names). Pure and testable.
public enum TodayLinks {
    public struct Link: Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            /// The sender invited you and you have not answered.
            case invitation
            /// The sender is a guest or the organizer of an upcoming event.
            case event
        }

        public var kind: Kind
        public var event: AgendaEvent

        public init(kind: Kind, event: AgendaEvent) {
            self.kind = kind
            self.event = event
        }
    }

    /// Everyone on an event other than the user: the organizer and the guests (lower-cased addresses).
    public static func participants(of event: CalendarEvent, own: Set<String>) -> Set<String> {
        let own = Set(own.map { $0.lowercased() })
        var people = Set((event.attendees ?? []).filter { $0.isSelf != true && $0.resource != true }.map { $0.email.lowercased() })
        if let organizer = event.organizer, organizer.isSelf != true, let email = organizer.email { people.insert(email.lowercased()) }
        return people.subtracting(own)
    }

    /// The event a thread from `sender` is most likely about: an unanswered invitation from them first, else the
    /// soonest upcoming (not finished) event they are on, within `horizon` of now.
    public static func link(sender: String, events: [AgendaEvent], invitations: [AgendaEvent], own: Set<String>, now: Date,
                            zone: TimeZone, horizon: TimeInterval = 3 * 86_400) -> Link? {
        let who = sender.lowercased()
        let limit = now.addingTimeInterval(horizon)
        func relevant(_ item: AgendaEvent) -> Bool {
            item.end(in: zone) > now && item.start(in: zone) < limit && !item.event.isCancelled
                && participants(of: item.event, own: own).contains(who)
        }
        if let invite = invitations.filter(relevant).min(by: { $0.start(in: zone) < $1.start(in: zone) }) {
            return Link(kind: .invitation, event: invite)
        }
        if let event = events.filter({ relevant($0) && !$0.event.needsResponse && $0.event.selfResponse != .declined })
            .min(by: { $0.start(in: zone) < $1.start(in: zone) }) {
            return Link(kind: .event, event: event)
        }
        return nil
    }

    /// "About the invitation for Fri 3:00 PM — answer it below" / "For Study group tonight at 7:00 PM".
    public static func phrase(for link: Link, now: Date, zone: TimeZone) -> String {
        let start = link.event.start(in: zone)
        switch link.kind {
        case .invitation:
            let when = link.event.event.isAllDay ? weekday(start, zone: zone) : "\(weekday(start, zone: zone)) \(clock(start, zone: zone))"
            return "About the invitation for \(when) — answer it below"
        case .event:
            return "For \(shortTitle(link.event.event.title)) \(relativeTime(start, isAllDay: link.event.event.isAllDay, now: now, zone: zone))"
        }
    }

    /// "Study group · MATH 2210" → "Study group" (the part before the first " · ").
    public static func shortTitle(_ title: String) -> String {
        guard let range = title.range(of: " · ") else { return title }
        let head = title[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        return head.isEmpty ? title : head
    }

    /// "tonight at 7:00 PM", "today at 11:30 AM", "tomorrow at 10:10 AM", "on Fri at 3:00 PM", "tomorrow" (all-day).
    public static func relativeTime(_ date: Date, isAllDay: Bool = false, now: Date, zone: TimeZone) -> String {
        let days = CivilDate(now, in: zone).days(to: CivilDate(date, in: zone))
        let hour = Calendar.gregorian(zone).component(.hour, from: date)
        let time = clock(date, zone: zone)
        switch days {
        case 0: return isAllDay ? "today" : (hour >= 17 ? "tonight at \(time)" : "today at \(time)")
        case 1: return isAllDay ? "tomorrow" : "tomorrow at \(time)"
        default: return isAllDay ? "on \(weekday(date, zone: zone))" : "on \(weekday(date, zone: zone)) at \(time)"
        }
    }

    /// "3:00 PM".
    public static func clock(_ date: Date, zone: TimeZone) -> String {
        format(date, zone: zone, "h:mm a")
    }

    /// "3:00" (no meridiem — the agenda's start column).
    public static func shortClock(_ date: Date, zone: TimeZone) -> String {
        format(date, zone: zone, "h:mm")
    }

    /// "3:00 – 3:45 PM", or "11:30 AM – 12:45 PM" across noon.
    public static func range(_ start: Date, _ end: Date, zone: TimeZone) -> String {
        let calendar = Calendar.gregorian(zone)
        let sameHalf = (calendar.component(.hour, from: start) < 12) == (calendar.component(.hour, from: end) < 12)
            && CivilDate(start, in: zone) == CivilDate(end, in: zone)
        return sameHalf ? "\(shortClock(start, zone: zone)) – \(clock(end, zone: zone))" : "\(clock(start, zone: zone)) – \(clock(end, zone: zone))"
    }

    /// "Fri".
    public static func weekday(_ date: Date, zone: TimeZone) -> String { CivilDate(date, in: zone).weekday.shortName }

    /// Timed events that overlap `item` (other than itself, declined and free-time events).
    public static func conflicts(of item: AgendaEvent, among events: [AgendaEvent], zone: TimeZone) -> [AgendaEvent] {
        guard !item.event.isAllDay else { return [] }
        let start = item.start(in: zone), end = item.end(in: zone)
        return events.filter { other in
            other.id != item.id && other.event.iCalUID.map { $0 != item.event.iCalUID } ?? true
                && !other.event.isAllDay && !other.event.isCancelled && !other.event.isFree
                && other.event.selfResponse != .declined
                && other.start(in: zone) < end && other.end(in: zone) > start
        }
    }

    /// "with Maya, Sam, Leah" — first names of the other guests (up to `limit`, then "+2").
    public static func guestLine(of event: CalendarEvent, limit: Int = 3) -> String? {
        let others = (event.attendees ?? []).filter { $0.isSelf != true && $0.resource != true && $0.responseStatus != .declined }
        guard !others.isEmpty else { return nil }
        let names = others.map { attendee -> String in
            let name = attendee.displayName?.trimmingCharacters(in: .whitespaces) ?? ""
            if let first = name.split(separator: " ").first { return String(first) }
            return String(attendee.email.split(separator: "@").first ?? Substring(attendee.email))
        }
        let shown = names.prefix(limit).joined(separator: ", ")
        return names.count > limit ? "with \(shown) +\(names.count - limit)" : "with \(shown)"
    }

    /// The asking sentence plus the one after it when that is a whole sentence and the pair stays short — the
    /// Today card's quote ("What time are you coming Saturday? Aunt Carol wants to do lunch at 1.").
    public static func excerpt(of thread: MailThread, verdict: NeedsReply.Verdict, maxLength: Int = 170) -> String? {
        guard let question = verdict.question else { return nil }
        guard let message = thread.messages.first(where: { $0.id == verdict.messageID }) ?? thread.messages.last(where: { !$0.isDraft }) else { return question }
        let sentences = NeedsReply.splitSentences(NeedsReply.newText(of: message))
        guard let index = sentences.firstIndex(of: question), index + 1 < sentences.count else { return question }
        let next = sentences[index + 1]
        guard let last = next.last, ".?!".contains(last) else { return question }
        let joined = "\(question) \(next)"
        return joined.count <= maxLength ? joined : question
    }

    /// "26 min ago", "3 h ago", "Yesterday", "2 days ago" (calendar days, as people count them).
    public static func age(_ date: Date, now: Date, zone: TimeZone) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let days = CivilDate(date, in: zone).days(to: CivilDate(now, in: zone))
        if days <= 0 { return "\(minutes / 60) h ago" }
        return days == 1 ? "Yesterday" : "\(days) days ago"
    }

    /// Who sent an invitation: organizer's name, else address.
    public static func inviter(of event: CalendarEvent) -> String? {
        if let name = event.organizer?.displayName, !name.isEmpty { return name }
        if let organizer = event.attendees?.first(where: { $0.organizer == true }) { return organizer.displayName ?? organizer.email }
        return event.organizer?.email
    }

    /// The fraction of an event that has passed (0…1) — the Now row's progress bar.
    public static func progress(of item: AgendaEvent, now: Date, zone: TimeZone) -> Double {
        let start = item.start(in: zone), end = item.end(in: zone)
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    private static func format(_ date: Date, zone: TimeZone, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter.string(from: date)
    }
}
