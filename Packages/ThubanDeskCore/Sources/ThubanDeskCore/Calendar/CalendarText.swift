import Foundation

/// The calendar's words and clock strings (design: "7:00 – 8:30 PM", "September 20 – 26, 2026",
/// "4 guests · 3 going, 1 no reply", the repeating-event scope texts). en_US, in the viewer's zone.
public enum CalendarText {
    // MARK: Clock

    static func formatter(_ format: String, _ zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar.gregorian(zone)
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter
    }

    static func parts(_ date: Date, _ zone: TimeZone) -> (hour: Int, minute: Int) {
        let c = Calendar.gregorian(zone).dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0, c.minute ?? 0)
    }

    /// "7:00 PM" (or "7:00" without the suffix).
    public static func clock(_ date: Date, zone: TimeZone, suffix: Bool = true) -> String {
        let (h, m) = parts(date, zone)
        return clock(hour: h, minute: m, suffix: suffix)
    }

    public static func clock(hour: Int, minute: Int, suffix: Bool = true) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d", h12, minute) + (suffix ? (hour < 12 ? " AM" : " PM") : "")
    }

    /// Minutes since midnight → "7:30 PM".
    public static func clock(minutes: Int, suffix: Bool = true) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return clock(hour: m / 60, minute: m % 60, suffix: suffix)
    }

    /// "7:00 – 8:30 PM"; "11:30 AM – 12:45 PM" when the halves of the day differ.
    public static func timeRange(_ start: Date, _ end: Date, zone: TimeZone) -> String {
        let a = parts(start, zone), b = parts(end, zone)
        let same = (a.hour < 12) == (b.hour < 12)
        return "\(clock(hour: a.hour, minute: a.minute, suffix: !same)) – \(clock(hour: b.hour, minute: b.minute))"
    }

    /// Month cells: "7am", "10:10am", "1:25pm".
    public static func compactTime(_ date: Date, zone: TimeZone) -> String {
        let (h, m) = parts(date, zone)
        let h12 = h % 12 == 0 ? 12 : h % 12
        return (m == 0 ? "\(h12)" : String(format: "%d:%02d", h12, m)) + (h < 12 ? "am" : "pm")
    }

    /// Grid labels: "8 AM", "12 PM".
    public static func hourLabel(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        return "\(h % 12 == 0 ? 12 : h % 12) \(h < 12 ? "AM" : "PM")"
    }

    /// "1 h 30 m", "45 m", "2 h", "1 d".
    public static func duration(minutes: Int) -> String {
        guard minutes > 0 else { return "0 m" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) d" }
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) m" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) m"
    }

    // MARK: Dates

    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    static let shortMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    public static func monthName(_ month: Int) -> String { monthNames[max(0, min(11, month - 1))] }
    public static func shortMonth(_ month: Int) -> String { shortMonths[max(0, min(11, month - 1))] }

    /// "September 2026".
    public static func monthTitle(year: Int, month: Int) -> String { "\(monthName(month)) \(year)" }

    /// "September 20 – 26, 2026"; "Sep 27 – Oct 3, 2026"; "Dec 27, 2026 – Jan 2, 2027".
    public static func rangeTitle(from first: CivilDate, to last: CivilDate) -> String {
        if first == last { return "\(monthName(first.month)) \(first.day), \(first.year)" }
        if first.year != last.year {
            return "\(shortMonth(first.month)) \(first.day), \(first.year) – \(shortMonth(last.month)) \(last.day), \(last.year)"
        }
        if first.month != last.month {
            return "\(shortMonth(first.month)) \(first.day) – \(shortMonth(last.month)) \(last.day), \(last.year)"
        }
        return "\(monthName(first.month)) \(first.day) – \(last.day), \(first.year)"
    }

    /// "Thursday, September 24, 2026".
    public static func dayTitle(_ day: CivilDate) -> String { "\(day.weekday.name), \(monthName(day.month)) \(day.day), \(day.year)" }

    /// "Thursday, September 24".
    public static func longDay(_ day: CivilDate) -> String { "\(day.weekday.name), \(monthName(day.month)) \(day.day)" }

    /// "Thu, Sep 24, 2026" (editor date boxes).
    public static func editorDate(_ day: CivilDate) -> String { "\(day.weekday.shortName), \(shortMonth(day.month)) \(day.day), \(day.year)" }

    /// "Sep 24".
    public static func shortDate(_ day: CivilDate) -> String { "\(shortMonth(day.month)) \(day.day)" }

    /// Popover: "Thursday, September 24 · 7:00 – 8:30 PM", "Friday, September 25 · All day",
    /// "Sep 25 – 27 · All day", "Fri, Sep 25, 10:00 PM – Sat, Sep 26, 2:00 AM".
    public static func when(_ event: CalendarEvent, zone: TimeZone) -> String {
        if event.isAllDay {
            let first = event.start.civilDate(in: zone)
            let last = event.end.civilDate(in: zone).adding(days: -1)
            if last <= first { return "\(longDay(first)) · All day" }
            let span = first.month == last.month ? "\(shortDate(first)) – \(last.day)" : "\(shortDate(first)) – \(shortDate(last))"
            return "\(span) · All day"
        }
        let start = event.startDate(in: zone), end = event.endDate(in: zone)
        let a = CivilDate(start, in: zone), b = CivilDate(end.addingTimeInterval(-1), in: zone)
        if a == b { return "\(longDay(a)) · \(timeRange(start, end, zone: zone))" }
        return "\(a.weekday.shortName), \(shortDate(a)), \(clock(start, zone: zone)) – \(b.weekday.shortName), \(shortDate(b)), \(clock(end, zone: zone))"
    }

    /// Invitation card: "Fri, Sep 25 · 3:00 – 3:45 PM".
    public static func shortWhen(_ event: CalendarEvent, zone: TimeZone) -> String {
        let day = event.start.civilDate(in: zone)
        let prefix = "\(day.weekday.shortName), \(shortDate(day))"
        if event.isAllDay { return "\(prefix) · All day" }
        return "\(prefix) · \(timeRange(event.startDate(in: zone), event.endDate(in: zone), zone: zone))"
    }

    // MARK: Guests

    /// "3 going · 1 no reply" (also "1 maybe", "1 declined").
    public static func replyCounts(_ attendees: [EventAttendee]) -> String {
        let people = attendees.filter { $0.resource != true }
        var parts: [String] = []
        let going = people.filter { $0.responseStatus == .accepted }.count
        let maybe = people.filter { $0.responseStatus == .tentative }.count
        let declined = people.filter { $0.responseStatus == .declined }.count
        let waiting = people.filter { ($0.responseStatus ?? .needsAction) == .needsAction }.count
        if going > 0 { parts.append("\(going) going") }
        if maybe > 0 { parts.append("\(maybe) maybe") }
        if declined > 0 { parts.append("\(declined) declined") }
        if waiting > 0 { parts.append("\(waiting) no reply") }
        return parts.joined(separator: " · ")
    }

    /// Popover: "4 guests · 3 going, 1 no reply"; for an unanswered invitation "Priya Shah invited you · awaiting
    /// your reply". Nil without guests.
    public static func guestSummary(_ event: CalendarEvent) -> String? {
        guard let attendees = event.attendees?.filter({ $0.resource != true }), !attendees.isEmpty else { return nil }
        if event.needsResponse {
            let organizer = event.organizer?.displayName ?? event.organizer?.email ?? attendees.first { $0.organizer == true }?.name ?? "Someone"
            return "\(organizer) invited you · awaiting your reply"
        }
        let counts = replyCounts(attendees).replacingOccurrences(of: " · ", with: ", ")
        return "\(attendees.count) guest\(attendees.count == 1 ? "" : "s") · \(counts)"
    }

    // MARK: Lists

    /// "a", "a and b", "a, b and c".
    public static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    // MARK: Repeating-event scope dialog

    /// What the user did before being asked which events it applies to.
    public enum ScopeAction: Hashable, Sendable {
        /// Dragged (or re-timed) the occurrence to new times.
        case move(start: EventDateTime, end: EventDateTime)
        /// Changed other fields in the editor.
        case edit
        case delete
    }

    /// Dialog title: "Change a repeating event" / "Delete a repeating event".
    public static func scopeTitle(_ action: ScopeAction) -> String {
        if case .delete = action { return "Delete a repeating event" }
        return "Change a repeating event"
    }

    /// "repeats Tue, Thu, Sat at 7:00 AM" (weekly), else the rule summary ("repeats daily until Dec 10").
    public static func seriesSubtitle(master: CalendarEvent, zone: TimeZone) -> String {
        let seriesZone = master.start.zone ?? zone
        guard let rule = master.rrule else { return "repeats" }
        let at = master.isAllDay ? "" : " at \(clock(master.startDate(in: seriesZone), zone: seriesZone))"
        if rule.frequency == .weekly, rule.interval == 1, !rule.byDay.isEmpty, rule.byDay.allSatisfy({ $0.ordinal == nil }) {
            return "repeats \(rule.weekdays.sorted().map(\.shortName).joined(separator: ", "))\(at)"
        }
        if let builder = RecurrenceBuilder(recurrence: master.recurrence, start: master.start.civilDate(in: seriesZone), zone: seriesZone) {
            let summary = builder.summary
            return "repeats " + summary.prefix(1).lowercased() + summary.dropFirst() + at
        }
        return "repeats" + at
    }

    /// The question under the title, in Markdown (`**…**` bold): "You moved Thursday’s session from **7:00** to
    /// **7:30 – 8:30 AM**. Which events should change?"
    public static func scopePrompt(_ action: ScopeAction, instance: CalendarEvent, zone: TimeZone) -> String {
        let original = (instance.originalStartTime ?? instance.start)
        let day = original.civilDate(in: zone)
        switch action {
        case .delete:
            return "You’re deleting \(day.weekday.name)’s “\(instance.title)”. Which events should be deleted?"
        case .edit:
            return "You changed \(day.weekday.name)’s “\(instance.title)”. Which events should change?"
        case .move(let start, let end):
            if start.isAllDay || instance.isAllDay {
                let target = start.civilDate(in: zone)
                return "You moved \(day.weekday.name)’s “\(instance.title)” to **\(longDay(target))**. Which events should change?"
            }
            let newStart = start.instant(in: zone), newEnd = end.instant(in: zone)
            let oldStart = instance.startDate(in: zone)
            let newDay = CivilDate(newStart, in: zone)
            let sameHalf = (parts(oldStart, zone).hour < 12) == (parts(newStart, zone).hour < 12)
            let range = timeRange(newStart, newEnd, zone: zone)
            let target = newDay == instance.start.civilDate(in: zone) ? "**\(range)**" : "**\(newDay.weekday.name), \(range)**"
            return "You moved \(day.weekday.name)’s session from **\(clock(oldStart, zone: zone, suffix: !sameHalf))** to \(target). Which events should change?"
        }
    }

    /// The line under each scope option, e.g. "Thursdays move to 7:30 AM. Tuesdays and Saturdays stay at 7:00."
    public static func scopeDetail(_ scope: RecurrenceScope, action: ScopeAction, master: CalendarEvent?, instance: CalendarEvent,
                                   zone: TimeZone) -> String {
        let original = instance.originalStartTime ?? instance.start
        let day = original.civilDate(in: zone)
        let rule = master?.rrule
        let weekly = rule.map { $0.frequency == .weekly && !$0.byDay.isEmpty && $0.byDay.allSatisfy { $0.ordinal == nil } } ?? false
        let ruleDays = weekly ? (rule?.weekdays.sorted() ?? []) : []
        let since = master.map { shortDate($0.start.civilDate(in: $0.start.zone ?? zone)) }
        let pastClause = since.map { ", including past events since \($0)" } ?? ""

        switch action {
        case .move(let start, _):
            let newStart = start.instant(in: zone)
            let movedDay = start.civilDate(in: zone)
            let clockText = start.isAllDay ? "" : clock(newStart, zone: zone)
            let target: String
            if start.isAllDay { target = longDay(movedDay) } else if movedDay == instance.start.civilDate(in: zone) { target = clockText } else { target = "\(movedDay.weekday.name) at \(clockText)" }
            switch scope {
            case .thisEvent:
                return "\(longDay(day)) moves to \(target)."
            case .everyWeekday(let weekday):
                let others = ruleDays.filter { $0 != weekday }.map(\.plural)
                let oldStart = instance.startDate(in: zone)
                let sameHalf = (parts(oldStart, zone).hour < 12) == (parts(newStart, zone).hour < 12)
                let stay = others.isEmpty ? "" : " \(list(others)) stay at \(clock(oldStart, zone: zone, suffix: !sameHalf))."
                return "\(weekday.plural) move to \(target).\(stay)"
            case .thisAndFollowing:
                let who = ruleDays.count > 1 ? "Every \(list(ruleDays.map(\.shortName)))" : "Every event"
                return "\(who) from \(shortDate(day)) on moves to \(target)."
            case .allEvents:
                return "The whole series moves\(pastClause)."
            }
        case .edit:
            switch scope {
            case .thisEvent:
                return "Only \(longDay(day)) changes."
            case .everyWeekday(let weekday):
                let others = ruleDays.filter { $0 != weekday }.map(\.plural)
                return "\(weekday.plural) from \(shortDate(day)) on change." + (others.isEmpty ? "" : " \(list(others)) stay as they are.")
            case .thisAndFollowing:
                return "Every event from \(shortDate(day)) on changes."
            case .allEvents:
                return "The whole series changes\(pastClause)."
            }
        case .delete:
            switch scope {
            case .thisEvent:
                return "Only \(longDay(day)) is deleted."
            case .everyWeekday(let weekday):
                let others = ruleDays.filter { $0 != weekday }.map(\.plural)
                return "\(weekday.plural) from \(shortDate(day)) on are deleted." + (others.isEmpty ? "" : " \(list(others)) stay.")
            case .thisAndFollowing:
                return "Every event from \(shortDate(day)) on is deleted. Earlier ones stay."
            case .allEvents:
                return "The whole series is deleted\(pastClause)."
            }
        }
    }

    /// The dialog's action button: "Move events", "Save", "Delete".
    public static func scopeButton(_ action: ScopeAction) -> String {
        switch action {
        case .move: return "Move events"
        case .edit: return "Save"
        case .delete: return "Delete"
        }
    }
}
