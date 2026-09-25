import Foundation

/// `UNTIL` in an RRULE: a date for all-day series, a UTC instant for timed ones (Google requires the UTC form).
public enum RRuleUntil: Hashable, Sendable {
    case date(CivilDate)
    case dateTime(Date)

    /// `20261210` / `20261211T045959Z`.
    public var string: String {
        switch self {
        case .date(let date): return date.compact
        case .dateTime(let date): return RRule.utcStamp(date)
        }
    }

    /// Parses `yyyyMMdd`, `yyyyMMddTHHmmssZ` and floating `yyyyMMddTHHmmss` (read in `zone`).
    public init?(string: String, zone: TimeZone = TimeZone(identifier: "UTC")!) {
        let text = string.trimmingCharacters(in: .whitespaces)
        if text.count == 8, let date = CivilDate(string: text) {
            self = .date(date)
            return
        }
        guard let date = RRule.parseStamp(text, zone: zone) else { return nil }
        self = .dateTime(date)
    }
}

/// One RFC 5545 recurrence rule (the `RRULE:` line Google stores on a recurring master). Parses and formats every
/// part; `occurrences(…)` expands the subset Google Calendar's own UI produces (DAILY / WEEKLY / MONTHLY / YEARLY with
/// INTERVAL, BYDAY (with ordinals), BYMONTHDAY, BYMONTH, BYSETPOS, COUNT, UNTIL, WKST). Unknown parts are preserved.
public struct RRule: Hashable, Sendable {
    public enum Frequency: String, Sendable, CaseIterable {
        case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY"
    }

    /// `MO`, `2TU`, `-1FR`.
    public struct Day: Hashable, Sendable, CustomStringConvertible {
        public var ordinal: Int?
        public var weekday: Weekday

        public init(_ weekday: Weekday, ordinal: Int? = nil) {
            self.weekday = weekday
            self.ordinal = ordinal
        }

        public init?(string: String) {
            let text = string.trimmingCharacters(in: .whitespaces).uppercased()
            guard text.count >= 2, let weekday = Weekday(rawValue: String(text.suffix(2))) else { return nil }
            let prefix = text.dropLast(2)
            if prefix.isEmpty {
                self.init(weekday)
            } else {
                guard let n = Int(prefix.replacingOccurrences(of: "+", with: "")), n != 0, abs(n) <= 53 else { return nil }
                self.init(weekday, ordinal: n)
            }
        }

        public var description: String { (ordinal.map(String.init) ?? "") + weekday.rawValue }
    }

    public var frequency: Frequency
    public var interval: Int
    public var byDay: [Day]
    public var byMonthDay: [Int]
    public var byMonth: [Int]
    public var bySetPos: [Int]
    public var count: Int?
    public var until: RRuleUntil?
    public var weekStart: Weekday?
    /// Parts this type does not model (`BYHOUR=…`), kept verbatim.
    public var other: [String]

    public init(frequency: Frequency, interval: Int = 1, byDay: [Day] = [], byMonthDay: [Int] = [], byMonth: [Int] = [], bySetPos: [Int] = [],
                count: Int? = nil, until: RRuleUntil? = nil, weekStart: Weekday? = nil, other: [String] = []) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.byDay = byDay
        self.byMonthDay = byMonthDay
        self.byMonth = byMonth
        self.bySetPos = bySetPos
        self.count = count
        self.until = until
        self.weekStart = weekStart
        self.other = other
    }

    /// Parses `RRULE:FREQ=WEEKLY;BYDAY=MO,WE` or the bare `FREQ=…` value. Nil for EXDATE / RDATE lines or garbage.
    public init?(line: String) {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.uppercased().hasPrefix("RRULE:") { text = String(text.dropFirst(6)) } else if text.contains(":") { return nil }
        var frequency: Frequency?
        var rule = RRule(frequency: .daily)
        for part in text.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            let key = pair[0].uppercased(), value = pair[1]
            let list = value.split(separator: ",").map(String.init)
            switch key {
            case "FREQ": frequency = Frequency(rawValue: value.uppercased())
            case "INTERVAL": rule.interval = max(1, Int(value) ?? 1)
            case "BYDAY": rule.byDay = list.compactMap(Day.init(string:))
            case "BYMONTHDAY": rule.byMonthDay = list.compactMap { Int($0) }
            case "BYMONTH": rule.byMonth = list.compactMap { Int($0) }
            case "BYSETPOS": rule.bySetPos = list.compactMap { Int($0) }
            case "COUNT": rule.count = Int(value)
            case "UNTIL": rule.until = RRuleUntil(string: value)
            case "WKST": rule.weekStart = Weekday(rawValue: value.uppercased())
            default: rule.other.append(String(part))
            }
        }
        guard let frequency else { return nil }
        rule.frequency = frequency
        self = rule
    }

    /// `FREQ=…;…` without the `RRULE:` prefix.
    public var value: String {
        var parts = ["FREQ=\(frequency.rawValue)"]
        if interval > 1 { parts.append("INTERVAL=\(interval)") }
        if !byDay.isEmpty { parts.append("BYDAY=" + byDay.map(\.description).joined(separator: ",")) }
        if !byMonthDay.isEmpty { parts.append("BYMONTHDAY=" + byMonthDay.map(String.init).joined(separator: ",")) }
        if !byMonth.isEmpty { parts.append("BYMONTH=" + byMonth.map(String.init).joined(separator: ",")) }
        if !bySetPos.isEmpty { parts.append("BYSETPOS=" + bySetPos.map(String.init).joined(separator: ",")) }
        if let weekStart { parts.append("WKST=\(weekStart.rawValue)") }
        if let count { parts.append("COUNT=\(count)") }
        if let until { parts.append("UNTIL=\(until.string)") }
        parts.append(contentsOf: other)
        return parts.joined(separator: ";")
    }

    /// The full line Google stores: `RRULE:FREQ=…`.
    public var line: String { "RRULE:" + value }

    /// Weekdays named in BYDAY (ignoring ordinals).
    public var weekdays: [Weekday] { byDay.map(\.weekday) }

    // MARK: Stamps

    static func utcStamp(_ date: Date) -> String {
        let parts = Calendar.gregorian(TimeZone(identifier: "UTC")!).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02dZ", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// `yyyyMMddTHHmmss[Z]`; without `Z` the stamp is wall-clock time in `zone`.
    static func parseStamp(_ text: String, zone: TimeZone) -> Date? {
        var body = text
        var useZone = zone
        if body.hasSuffix("Z") { body.removeLast(); useZone = TimeZone(identifier: "UTC")! }
        let pieces = body.split(separator: "T")
        guard pieces.count == 2, let date = CivilDate(string: String(pieces[0])), pieces[1].count == 6,
              let hh = Int(pieces[1].prefix(2)), let mm = Int(pieces[1].dropFirst(2).prefix(2)), let ss = Int(pieces[1].suffix(2)) else { return nil }
        return Calendar.gregorian(useZone).date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: hh, minute: mm, second: ss))
    }
}

// MARK: - Recurrence set (RRULE + EXDATE + RDATE lines)

/// The `recurrence` array of a master event, split into its rule and exception dates.
public struct RecurrenceSet: Hashable, Sendable {
    public var rule: RRule?
    /// EXDATE / RDATE / EXRULE lines, verbatim.
    public var otherLines: [String]

    public init(rule: RRule?, otherLines: [String] = []) {
        self.rule = rule
        self.otherLines = otherLines
    }

    public init(lines: [String]) {
        var rule: RRule?
        var others: [String] = []
        for line in lines {
            if rule == nil, line.uppercased().hasPrefix("RRULE"), let parsed = RRule(line: line) { rule = parsed } else { others.append(line) }
        }
        self.init(rule: rule, otherLines: others)
    }

    public var lines: [String] { (rule.map { [$0.line] } ?? []) + otherLines }

    /// Excluded instants (timed series) and dates (all-day series) from every EXDATE line.
    public func exclusions(defaultZone: TimeZone) -> (instants: Set<Date>, dates: Set<CivilDate>) {
        var instants = Set<Date>(), dates = Set<CivilDate>()
        for line in otherLines where line.uppercased().hasPrefix("EXDATE") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let params = line[..<colon].uppercased()
            var zone = defaultZone
            if let range = line[..<colon].range(of: "TZID=", options: .caseInsensitive) {
                let id = line[range.upperBound..<colon].split(separator: ";").first.map(String.init) ?? ""
                zone = TimeZone(identifier: id) ?? defaultZone
            }
            for value in line[line.index(after: colon)...].split(separator: ",").map(String.init) {
                if params.contains("VALUE=DATE") && !params.contains("DATE-TIME") || value.count == 8 {
                    if let date = CivilDate(string: value) { dates.insert(date) }
                } else if let instant = RRule.parseStamp(value, zone: zone) {
                    instants.insert(instant)
                }
            }
        }
        return (instants, dates)
    }
}

// MARK: - Expansion

extension RRule {
    /// Occurrence starts of the series whose first start (DTSTART) is `start`, expanded in `zone` (wall-clock time is
    /// kept across DST). All-day series pass midnight of the start date and `isAllDay: true`. Stops at `end`
    /// (exclusive), UNTIL, COUNT or `limit`. DTSTART is always the first occurrence (RFC 5545).
    public func occurrences(start: Date, zone: TimeZone, isAllDay: Bool = false, until end: Date? = nil,
                            excluding exclusions: (instants: Set<Date>, dates: Set<CivilDate>) = ([], []), limit: Int = 2000) -> [Date] {
        let calendar = Calendar.gregorian(zone)
        let first = CivilDate(start, in: zone)
        let time = calendar.dateComponents([.hour, .minute, .second], from: start)
        func instant(_ day: CivilDate) -> Date? {
            calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day,
                                               hour: isAllDay ? 0 : time.hour, minute: isAllDay ? 0 : time.minute, second: isAllDay ? 0 : time.second))
        }
        func beyondUntil(_ day: CivilDate, _ at: Date) -> Bool {
            switch until {
            case .none: return false
            case .date(let last): return day > last
            case .dateTime(let last): return at > last
            }
        }

        var result: [Date] = []
        var produced = 0
        var emittedFirst = false
        var period = 0
        var emptyPeriods = 0
        periods: while produced < limit, period < 20_000 {
            var candidates = candidateDays(period: period, first: first).filter { $0 >= first }
            if period == 0, !candidates.contains(first) { candidates.insert(first, at: 0) }
            period += 1
            if candidates.isEmpty {
                emptyPeriods += 1
                if emptyPeriods > 400 { break }
                continue
            }
            emptyPeriods = 0
            for day in candidates.sorted() {
                if day == first { if emittedFirst { continue }; emittedFirst = true }
                guard let at = instant(day) else { continue }
                if beyondUntil(day, at) { break periods }
                if let end, at >= end { break periods }
                produced += 1
                if let count, produced > count { break periods }
                let excluded = isAllDay ? exclusions.dates.contains(day) : exclusions.instants.contains(at)
                if !excluded { result.append(at) }
                if produced >= limit { break periods }
            }
        }
        return result
    }

    /// Civil dates the rule produces in period `n` (before filtering by DTSTART).
    func candidateDays(period n: Int, first: CivilDate) -> [CivilDate] {
        switch frequency {
        case .daily:
            let day = first.adding(days: n * interval)
            return passesFilters(day) ? [day] : []
        case .weekly:
            let wkst = weekStart ?? .monday
            let offset = (first.weekday.calendarWeekday - wkst.calendarWeekday + 7) % 7
            let anchor = first.adding(days: -offset + 7 * interval * n)
            let days = byDay.isEmpty ? [first.weekday] : byDay.map(\.weekday)
            let dates = Set(days).map { day in anchor.adding(days: (day.calendarWeekday - wkst.calendarWeekday + 7) % 7) }
            return dates.filter { byMonth.isEmpty || byMonth.contains($0.month) }.sorted()
        case .monthly:
            let index = (first.year * 12 + first.month - 1) + n * interval
            let year = index / 12, month = index % 12 + 1
            if !byMonth.isEmpty, !byMonth.contains(month) { return [] }
            return applySetPos(daysInMonth(year: year, month: month, defaultDay: first.day))
        case .yearly:
            let year = first.year + n * interval
            let months = byMonth.isEmpty ? [first.month] : byMonth
            var days: [CivilDate] = []
            for month in months {
                if byDay.isEmpty && byMonthDay.isEmpty {
                    if let date = RRule.valid(year, month, first.day) { days.append(date) }
                } else {
                    days += daysInMonth(year: year, month: month, defaultDay: first.day)
                }
            }
            return applySetPos(days.sorted())
        }
    }

    private func passesFilters(_ day: CivilDate) -> Bool {
        if !byDay.isEmpty, !byDay.contains(where: { $0.weekday == day.weekday }) { return false }
        if !byMonth.isEmpty, !byMonth.contains(day.month) { return false }
        if !byMonthDay.isEmpty {
            let length = RRule.length(year: day.year, month: day.month)
            if !byMonthDay.contains(where: { ($0 > 0 ? $0 : length + $0 + 1) == day.day }) { return false }
        }
        return true
    }

    private func daysInMonth(year: Int, month: Int, defaultDay: Int) -> [CivilDate] {
        let length = RRule.length(year: year, month: month)
        var days: [CivilDate] = []
        if !byMonthDay.isEmpty {
            for value in byMonthDay {
                let day = value > 0 ? value : length + value + 1
                if let date = RRule.valid(year, month, day) { days.append(date) }
            }
            if !byDay.isEmpty { days = days.filter { d in byDay.contains { $0.weekday == d.weekday } } }
        } else if !byDay.isEmpty {
            for entry in byDay {
                let matches = (1...length).compactMap { RRule.valid(year, month, $0) }.filter { $0.weekday == entry.weekday }
                if let ordinal = entry.ordinal {
                    let index = ordinal > 0 ? ordinal - 1 : matches.count + ordinal
                    if matches.indices.contains(index) { days.append(matches[index]) }
                } else {
                    days += matches
                }
            }
        } else if let date = RRule.valid(year, month, defaultDay) {
            days.append(date)
        }
        return Array(Set(days)).sorted()
    }

    private func applySetPos(_ days: [CivilDate]) -> [CivilDate] {
        guard !bySetPos.isEmpty else { return days }
        return bySetPos.compactMap { pos in
            let index = pos > 0 ? pos - 1 : days.count + pos
            return days.indices.contains(index) ? days[index] : nil
        }.sorted()
    }

    static func length(year: Int, month: Int) -> Int {
        let utc = TimeZone(identifier: "UTC")!
        let start = CivilDate(year: year, month: month, day: 1).startDate(in: utc)
        return Calendar.gregorian(utc).range(of: .day, in: .month, for: start)?.count ?? 30
    }

    static func valid(_ year: Int, _ month: Int, _ day: Int) -> CivilDate? {
        guard day >= 1, day <= length(year: year, month: month) else { return nil }
        return CivilDate(year: year, month: month, day: day)
    }
}
