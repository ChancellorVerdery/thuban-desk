import Foundation

/// A calendar date without a time or zone (`2026-09-24`) — all-day event dates, RRULE UNTIL dates.
public struct CivilDate: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The date `date` falls on in `timeZone`.
    public init(_ date: Date, in timeZone: TimeZone = .current) {
        let parts = Calendar.gregorian(timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Parses `yyyy-MM-dd` or `yyyyMMdd`.
    public init?(string: String) {
        let digits = string.replacingOccurrences(of: "-", with: "")
        guard digits.count == 8, let y = Int(digits.prefix(4)), let m = Int(digits.dropFirst(4).prefix(2)), let d = Int(digits.suffix(2)),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = CivilDate(string: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a date: \(text)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    /// `yyyy-MM-dd`.
    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
    /// `yyyyMMdd` (RRULE / EXDATE form).
    public var compact: String { String(format: "%04d%02d%02d", year, month, day) }

    public static func < (a: CivilDate, b: CivilDate) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    /// Midnight at the start of this date in `timeZone`.
    public func startDate(in timeZone: TimeZone = .current) -> Date {
        Calendar.gregorian(timeZone).date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int) -> CivilDate {
        let utc = TimeZone(identifier: "UTC")!
        let date = Calendar.gregorian(utc).date(byAdding: .day, value: days, to: startDate(in: utc)) ?? startDate(in: utc)
        return CivilDate(date, in: utc)
    }

    /// Whole days from `self` to `other`.
    public func days(to other: CivilDate) -> Int {
        let utc = TimeZone(identifier: "UTC")!
        return Calendar.gregorian(utc).dateComponents([.day], from: startDate(in: utc), to: other.startDate(in: utc)).day ?? 0
    }

    public var weekday: Weekday {
        let utc = TimeZone(identifier: "UTC")!
        return Weekday(calendarWeekday: Calendar.gregorian(utc).component(.weekday, from: startDate(in: utc)))
    }
}

/// Days of the week in RRULE spelling.
public enum Weekday: String, Codable, CaseIterable, Sendable, Comparable {
    case sunday = "SU", monday = "MO", tuesday = "TU", wednesday = "WE", thursday = "TH", friday = "FR", saturday = "SA"

    /// `Calendar.component(.weekday)`: 1 = Sunday … 7 = Saturday.
    public init(calendarWeekday: Int) {
        self = Weekday.allCases[max(0, min(6, calendarWeekday - 1))]
    }

    public var calendarWeekday: Int { (Weekday.allCases.firstIndex(of: self) ?? 0) + 1 }
    public var shortName: String { ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][calendarWeekday - 1] }
    public var name: String { ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][calendarWeekday - 1] }
    public var plural: String { name + "s" }

    public static func < (a: Weekday, b: Weekday) -> Bool { a.calendarWeekday < b.calendarWeekday }

    /// Sorted for display starting on `firstDay`.
    public static func ordered(from firstDay: Weekday) -> [Weekday] {
        let start = firstDay.calendarWeekday - 1
        return (0..<7).map { allCases[(start + $0) % 7] }
    }
}

extension Calendar {
    /// Gregorian calendar in a zone (never the user's locale calendar, so math is stable).
    public static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}
