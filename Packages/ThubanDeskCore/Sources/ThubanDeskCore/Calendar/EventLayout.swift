import Foundation

/// Pure geometry for the calendar grids: side-by-side columns for overlapping timed events, lanes for all-day /
/// multi-day bars, and drag snapping. No UI types, so it is unit-tested.
public enum EventLayout {
    /// Where one timed event sits inside its day column: `column` of `columns` (equal widths), widened across
    /// `span` free columns to its right.
    public struct Slot: Equatable, Sendable {
        public var column: Int
        public var columns: Int
        public var span: Int

        public init(column: Int, columns: Int, span: Int = 1) {
            self.column = column
            self.columns = columns
            self.span = span
        }

        /// Leading edge and width as fractions of the day column.
        public var fraction: (x: Double, width: Double) {
            let unit = 1 / Double(max(1, columns))
            return (Double(column) * unit, Double(span) * unit)
        }
    }

    /// Column assignment for one day's timed events (`start` / `end` in any unit, e.g. minutes from midnight).
    /// Events that overlap — directly or through a chain — form a cluster sharing one column count; each event takes
    /// the first column free at its start (longer events first on equal starts) and spreads into free columns to
    /// its right. Very short events count as `minimumLength` long so their blocks never overlap visually.
    /// Returns one slot per input, in input order.
    public static func columns(_ intervals: [(start: Double, end: Double)], minimumLength: Double = 0) -> [Slot] {
        guard !intervals.isEmpty else { return [] }
        let spans = intervals.map { (start: $0.start, end: max($0.end, $0.start + minimumLength)) }
        let order = spans.indices.sorted {
            let a = spans[$0], b = spans[$1]
            if a.start != b.start { return a.start < b.start }
            if a.end != b.end { return a.end > b.end }
            return $0 < $1
        }
        var slots = [Slot](repeating: Slot(column: 0, columns: 1), count: spans.count)
        var cluster: [Int] = []
        var columnEnds: [Double] = []
        var clusterEnd = -Double.infinity

        func closeCluster() {
            guard !cluster.isEmpty else { return }
            let count = columnEnds.count
            for index in cluster {
                slots[index].columns = count
                // Spread right while the neighbouring columns stay free for this event's whole span.
                var span = 1
                var next = slots[index].column + 1
                while next < count {
                    let blocked = cluster.contains { other in
                        other != index && slots[other].column == next
                            && spans[other].start < spans[index].end && spans[other].end > spans[index].start
                    }
                    if blocked { break }
                    span += 1
                    next += 1
                }
                slots[index].span = span
            }
            cluster = []
            columnEnds = []
        }

        for index in order {
            let span = spans[index]
            if span.start >= clusterEnd { closeCluster() }
            if let free = columnEnds.firstIndex(where: { $0 <= span.start }) {
                columnEnds[free] = span.end
                slots[index].column = free
            } else {
                columnEnds.append(span.end)
                slots[index].column = columnEnds.count - 1
            }
            cluster.append(index)
            clusterEnd = max(clusterEnd, span.end)
        }
        closeCluster()
        return slots
    }

    /// Lanes for bars covering day ranges (all-day row of a week, a month week row): each bar takes the lowest lane
    /// free across its whole range, longer bars first on equal starts. Returns one lane per input, in input order.
    public static func lanes(_ ranges: [ClosedRange<Int>]) -> [Int] {
        let order = ranges.indices.sorted {
            let a = ranges[$0], b = ranges[$1]
            if a.lowerBound != b.lowerBound { return a.lowerBound < b.lowerBound }
            if a.count != b.count { return a.count > b.count }
            return $0 < $1
        }
        var result = [Int](repeating: 0, count: ranges.count)
        var laneEnds: [Int] = []
        for index in order {
            let range = ranges[index]
            if let free = laneEnds.firstIndex(where: { $0 < range.lowerBound }) {
                laneEnds[free] = range.upperBound
                result[index] = free
            } else {
                laneEnds.append(range.upperBound)
                result[index] = laneEnds.count - 1
            }
        }
        return result
    }

    /// Days in a month (leap years included).
    public static func daysInMonth(year: Int, month: Int) -> Int { RRule.length(year: year, month: month) }

    /// Rounds a minute offset to the nearest `step` (drag to move / resize snaps to 15 minutes).
    public static func snap(minutes: Double, step: Int = 15) -> Int {
        let step = Double(max(1, step))
        return Int((minutes / step).rounded()) * Int(step)
    }

    /// Minutes from `day`'s midnight to `date` in `zone` (can exceed 1440 or be negative for other days).
    public static func minutes(of date: Date, from day: CivilDate, zone: TimeZone) -> Double {
        date.timeIntervalSince(day.startDate(in: zone)) / 60
    }

    /// The instant `minutes` after midnight of `day` in `zone`, keeping wall-clock time across DST changes.
    public static func date(on day: CivilDate, minutes: Int, zone: TimeZone) -> Date {
        let calendar = Calendar.gregorian(zone)
        let base = DateComponents(year: day.year, month: day.month, day: day.day, hour: 0, minute: 0)
        guard let midnight = calendar.date(from: base) else { return day.startDate(in: zone) }
        let hours = Int(floor(Double(minutes) / 60))
        let rest = minutes - hours * 60
        var parts = DateComponents(year: day.year, month: day.month, day: day.day, hour: hours, minute: rest)
        if hours >= 24 || hours < 0 {
            // Past midnight: move whole days first, then set the time.
            let extraDays = Int(floor(Double(hours) / 24))
            let moved = day.adding(days: extraDays)
            parts = DateComponents(year: moved.year, month: moved.month, day: moved.day, hour: hours - extraDays * 24, minute: rest)
        }
        return calendar.date(from: parts) ?? midnight.addingTimeInterval(Double(minutes) * 60)
    }
}
