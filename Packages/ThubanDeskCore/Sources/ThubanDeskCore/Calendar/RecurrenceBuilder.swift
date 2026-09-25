import Foundation

/// The editor's "Repeat" model (design: Never / Daily / Weekly / Monthly, "Every N", weekday toggles, monthly by date
/// or by nth weekday, Ends never / on date / after N). Converts both ways with `RRule`; rules outside this vocabulary
/// (`init?(rrule:)` returns nil) are shown read-only as "Custom" and left untouched on save.
public struct RecurrenceBuilder: Hashable, Sendable {
    public enum Pattern: Hashable, Sendable {
        case daily
        case weekly(Set<Weekday>)
        /// Day of the month (1…31; months without it are skipped, as Google does).
        case monthlyByDate(Int)
        /// `ordinal` 1…4, or -1 for "last".
        case monthlyByWeekday(ordinal: Int, weekday: Weekday)
        case yearly
    }

    public enum End: Hashable, Sendable {
        case never
        /// Inclusive last date.
        case onDate(CivilDate)
        case after(Int)
    }

    public var pattern: Pattern
    public var interval: Int
    public var end: End

    public init(pattern: Pattern, interval: Int = 1, end: End = .never) {
        self.pattern = pattern
        self.interval = max(1, interval)
        self.end = end
    }

    /// Reads a rule; nil when the rule uses parts the builder cannot show (BYSETPOS, several BYMONTHDAY, …).
    public init?(rrule: RRule, zone: TimeZone = .current) {
        guard rrule.other.isEmpty, rrule.bySetPos.isEmpty else { return nil }
        let end: End
        if let count = rrule.count {
            end = .after(count)
        } else if let until = rrule.until {
            switch until {
            case .date(let date): end = .onDate(date)
            case .dateTime(let instant): end = .onDate(CivilDate(instant, in: zone))
            }
        } else {
            end = .never
        }
        switch rrule.frequency {
        case .daily:
            guard rrule.byDay.isEmpty, rrule.byMonthDay.isEmpty, rrule.byMonth.isEmpty else { return nil }
            self.init(pattern: .daily, interval: rrule.interval, end: end)
        case .weekly:
            guard rrule.byMonthDay.isEmpty, rrule.byMonth.isEmpty, rrule.byDay.allSatisfy({ $0.ordinal == nil }) else { return nil }
            self.init(pattern: .weekly(Set(rrule.weekdays)), interval: rrule.interval, end: end)
        case .monthly:
            guard rrule.byMonth.isEmpty else { return nil }
            if rrule.byDay.isEmpty, rrule.byMonthDay.count == 1, let day = rrule.byMonthDay.first, day > 0 {
                self.init(pattern: .monthlyByDate(day), interval: rrule.interval, end: end)
            } else if rrule.byMonthDay.isEmpty, rrule.byDay.count == 1, let day = rrule.byDay.first, let ordinal = day.ordinal,
                      (1...4).contains(ordinal) || ordinal == -1 {
                self.init(pattern: .monthlyByWeekday(ordinal: ordinal, weekday: day.weekday), interval: rrule.interval, end: end)
            } else if rrule.byDay.isEmpty, rrule.byMonthDay.isEmpty {
                // FREQ=MONTHLY alone repeats on DTSTART's day; the caller fills the day from the start date.
                self.init(pattern: .monthlyByDate(0), interval: rrule.interval, end: end)
            } else {
                return nil
            }
        case .yearly:
            guard rrule.byDay.isEmpty, rrule.byMonthDay.isEmpty, rrule.byMonth.count <= 1 else { return nil }
            self.init(pattern: .yearly, interval: rrule.interval, end: end)
        }
    }

    /// Reads a master's `recurrence` lines, filling "same day as the start" patterns from `start`.
    public init?(recurrence: [String]?, start: CivilDate, zone: TimeZone = .current) {
        guard let rule = RecurrenceSet(lines: recurrence ?? []).rule, var builder = RecurrenceBuilder(rrule: rule, zone: zone) else { return nil }
        if case .monthlyByDate(0) = builder.pattern { builder.pattern = .monthlyByDate(start.day) }
        if case .weekly(let days) = builder.pattern, days.isEmpty { builder.pattern = .weekly([start.weekday]) }
        self = builder
    }

    /// The rule for a series starting at `start`. For timed series UNTIL is the end of the chosen day in `zone`,
    /// written in UTC as Google requires; all-day series use a date.
    public func rrule(isAllDay: Bool, zone: TimeZone) -> RRule {
        var rule: RRule
        switch pattern {
        case .daily:
            rule = RRule(frequency: .daily, interval: interval)
        case .weekly(let days):
            rule = RRule(frequency: .weekly, interval: interval, byDay: days.sorted().map { RRule.Day($0) })
        case .monthlyByDate(let day):
            rule = RRule(frequency: .monthly, interval: interval, byMonthDay: day > 0 ? [day] : [])
        case .monthlyByWeekday(let ordinal, let weekday):
            rule = RRule(frequency: .monthly, interval: interval, byDay: [RRule.Day(weekday, ordinal: ordinal)])
        case .yearly:
            rule = RRule(frequency: .yearly, interval: interval)
        }
        switch end {
        case .never: break
        case .after(let count): rule.count = max(1, count)
        case .onDate(let date):
            if isAllDay {
                rule.until = .date(date)
            } else {
                let endOfDay = date.adding(days: 1).startDate(in: zone).addingTimeInterval(-1)
                rule.until = .dateTime(endOfDay)
            }
        }
        return rule
    }

    /// The `recurrence` array for an insert / patch (EXDATE lines from `keeping` are carried over).
    public func recurrenceLines(isAllDay: Bool, zone: TimeZone, keeping existing: [String]? = nil) -> [String] {
        [rrule(isAllDay: isAllDay, zone: zone).line] + RecurrenceSet(lines: existing ?? []).otherLines
    }

    // MARK: Text

    /// "Weekly on Mon, Wed, Fri until Dec 10", "Every 2 weeks on Thursday", "Monthly on the last Friday", "Daily, 12 times".
    public var summary: String {
        var text: String
        switch pattern {
        case .daily:
            text = interval == 1 ? "Daily" : "Every \(interval) days"
        case .weekly(let days):
            let sorted = days.sorted()
            let list: String
            if sorted.count == 1 {
                list = sorted[0].name
            } else if Set(sorted) == Set([Weekday.monday, .tuesday, .wednesday, .thursday, .friday]) {
                list = "weekdays"
            } else {
                list = sorted.map(\.shortName).joined(separator: ", ")
            }
            text = (interval == 1 ? "Weekly" : "Every \(interval) weeks") + (sorted.isEmpty ? "" : " on \(list)")
        case .monthlyByDate(let day):
            text = (interval == 1 ? "Monthly" : "Every \(interval) months") + (day > 0 ? " on day \(day)" : "")
        case .monthlyByWeekday(let ordinal, let weekday):
            text = (interval == 1 ? "Monthly" : "Every \(interval) months") + " on the \(Self.ordinalWord(ordinal)) \(weekday.name)"
        case .yearly:
            text = interval == 1 ? "Annually" : "Every \(interval) years"
        }
        switch end {
        case .never: break
        case .after(let count): text += count == 1 ? ", once" : ", \(count) times"
        case .onDate(let date): text += " until \(Self.shortDate(date))"
        }
        return text
    }

    static func ordinalWord(_ n: Int) -> String {
        switch n {
        case -1: return "last"
        case 1: return "first"
        case 2: return "second"
        case 3: return "third"
        case 4: return "fourth"
        default: return "\(n)th"
        }
    }

    /// "Dec 10".
    static func shortDate(_ date: CivilDate) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(months[max(0, min(11, date.month - 1))]) \(date.day)"
    }

    // MARK: Suggestions

    /// Nth weekday of `date` within its month: (ordinal 1…5, isLast).
    public static func weekdayPosition(of date: CivilDate) -> (ordinal: Int, isLast: Bool) {
        let ordinal = (date.day - 1) / 7 + 1
        let isLast = date.day + 7 > RRule.length(year: date.year, month: date.month)
        return (ordinal, isLast)
    }

    /// Sensible patterns for an event starting on `date` (the Repeat menu).
    public static func suggestions(for date: CivilDate) -> [Pattern] {
        var patterns: [Pattern] = [.daily, .weekly([date.weekday]), .weekly([.monday, .tuesday, .wednesday, .thursday, .friday]), .monthlyByDate(date.day)]
        let position = weekdayPosition(of: date)
        if position.ordinal <= 4 { patterns.append(.monthlyByWeekday(ordinal: position.ordinal, weekday: date.weekday)) }
        if position.isLast { patterns.append(.monthlyByWeekday(ordinal: -1, weekday: date.weekday)) }
        patterns.append(.yearly)
        return patterns
    }
}
