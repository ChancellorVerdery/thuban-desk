import XCTest
@testable import ThubanDeskCore

final class RRuleTests: XCTestCase {
    func testParseAndFormatRoundTrip() throws {
        let rule = try XCTUnwrap(RRule(line: "RRULE:FREQ=WEEKLY;WKST=SU;UNTIL=20261211T045959Z;BYDAY=MO,WE,FR"))
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.weekdays, [.monday, .wednesday, .friday])
        XCTAssertEqual(rule.weekStart, .sunday)
        guard case .dateTime(let until) = rule.until else { return XCTFail("until") }
        XCTAssertEqual(RRule.utcStamp(until), "20261211T045959Z")
        XCTAssertEqual(RRule(line: rule.line), rule)
        XCTAssertEqual(rule.line, "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;WKST=SU;UNTIL=20261211T045959Z")
    }

    func testParsesOrdinalsDatesAndUnknownParts() throws {
        let rule = try XCTUnwrap(RRule(line: "FREQ=MONTHLY;INTERVAL=2;BYDAY=-1FR,+2TU;COUNT=6;BYHOUR=9"))
        XCTAssertEqual(rule.byDay, [RRule.Day(.friday, ordinal: -1), RRule.Day(.tuesday, ordinal: 2)])
        XCTAssertEqual(rule.interval, 2)
        XCTAssertEqual(rule.count, 6)
        XCTAssertEqual(rule.other, ["BYHOUR=9"])
        XCTAssertEqual(rule.value, "FREQ=MONTHLY;INTERVAL=2;BYDAY=-1FR,2TU;COUNT=6;BYHOUR=9")
        XCTAssertEqual(RRule(line: "RRULE:FREQ=YEARLY;UNTIL=20270101")?.until, .date(CivilDate(year: 2027, month: 1, day: 1)))
        XCTAssertNil(RRule(line: "EXDATE;TZID=America/New_York:20260924T070000"))
        XCTAssertNil(RRule(line: "RRULE:INTERVAL=2"))
    }

    func testWeeklyExpansionKeepsWallClockAcrossDST() {
        // MWF 10:10 from Mon Oct 26, 2026 across the Nov 1 DST change.
        let rule = RRule(frequency: .weekly, byDay: [.init(.monday), .init(.wednesday), .init(.friday)], count: 6)
        let starts = rule.occurrences(start: ny(2026, 10, 26, 10, 10), zone: newYork)
        XCTAssertEqual(starts.count, 6)
        XCTAssertEqual(starts.map { CivilDate($0, in: newYork).day }, [26, 28, 30, 2, 4, 6])
        let hours = starts.map { Calendar.gregorian(newYork).component(.hour, from: $0) }
        XCTAssertEqual(Set(hours), [10])
    }

    func testUntilIsInclusiveAndIntervalWorks() {
        let rule = RRule(frequency: .weekly, interval: 2, byDay: [.init(.tuesday)], until: .dateTime(ny(2026, 10, 20, 23, 59)))
        let starts = rule.occurrences(start: ny(2026, 9, 22, 7), zone: newYork)
        XCTAssertEqual(starts.map { CivilDate($0, in: newYork).description }, ["2026-09-22", "2026-10-06", "2026-10-20"])
    }

    func testMonthlyByNthAndLastWeekdayAndNegativeMonthDay() {
        let second = RRule(frequency: .monthly, byDay: [.init(.tuesday, ordinal: 2)], count: 3)
        XCTAssertEqual(second.occurrences(start: ny(2026, 9, 8, 9), zone: newYork).map { CivilDate($0, in: newYork).description },
                       ["2026-09-08", "2026-10-13", "2026-11-10"])
        let last = RRule(frequency: .monthly, byDay: [.init(.friday, ordinal: -1)], count: 3)
        XCTAssertEqual(last.occurrences(start: ny(2026, 9, 25, 9), zone: newYork).map { CivilDate($0, in: newYork).description },
                       ["2026-09-25", "2026-10-30", "2026-11-27"])
        let endOfMonth = RRule(frequency: .monthly, byMonthDay: [-1], count: 3)
        XCTAssertEqual(endOfMonth.occurrences(start: ny(2027, 1, 31, 9), zone: newYork).map { CivilDate($0, in: newYork).description },
                       ["2027-01-31", "2027-02-28", "2027-03-31"])
        // Plain monthly on the 31st skips short months.
        let on31 = RRule(frequency: .monthly, count: 3)
        XCTAssertEqual(on31.occurrences(start: ny(2026, 10, 31, 9), zone: newYork).map { CivilDate($0, in: newYork).description },
                       ["2026-10-31", "2026-12-31", "2027-01-31"])
    }

    func testAllDayYearlyAndDailyWithExdate() {
        let yearly = RRule(frequency: .yearly, count: 3)
        let starts = yearly.occurrences(start: CivilDate(year: 2026, month: 9, day: 26).startDate(in: newYork), zone: newYork, isAllDay: true)
        XCTAssertEqual(starts.map { CivilDate($0, in: newYork).year }, [2026, 2027, 2028])

        let set = RecurrenceSet(lines: ["RRULE:FREQ=DAILY;COUNT=5", "EXDATE;TZID=America/New_York:20260926T070000,20260927T070000"])
        let exclusions = set.exclusions(defaultZone: newYork)
        let daily = set.rule!.occurrences(start: ny(2026, 9, 24, 7), zone: newYork, excluding: exclusions)
        // COUNT includes the excluded dates (RFC 5545): 24, 25, 28 remain.
        XCTAssertEqual(daily.map { CivilDate($0, in: newYork).day }, [24, 25, 28])
        let allDaySet = RecurrenceSet(lines: ["RRULE:FREQ=DAILY;COUNT=3", "EXDATE;VALUE=DATE:20260925"])
        XCTAssertEqual(allDaySet.exclusions(defaultZone: newYork).dates, [CivilDate(year: 2026, month: 9, day: 25)])
    }

    func testDTStartCountsEvenWhenNotMatchingByDay() {
        let rule = RRule(frequency: .weekly, byDay: [.init(.monday)], count: 2)
        // Starts on a Thursday.
        XCTAssertEqual(rule.occurrences(start: ny(2026, 9, 24, 9), zone: newYork).map { CivilDate($0, in: newYork).day }, [24, 28])
    }

    func testWindowEndStopsInfiniteRules() {
        let rule = RRule(frequency: .daily)
        XCTAssertEqual(rule.occurrences(start: ny(2026, 9, 1, 8), zone: newYork, until: ny(2026, 9, 11)).count, 10)
    }

    // MARK: Builder

    func testBuilderRoundTripsAndSummaries() throws {
        let weekly = RecurrenceBuilder(pattern: .weekly([.monday, .wednesday, .friday]), end: .onDate(CivilDate(year: 2026, month: 12, day: 10)))
        let rule = weekly.rrule(isAllDay: false, zone: newYork)
        XCTAssertEqual(rule.value, "FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261211T045959Z")
        XCTAssertEqual(weekly.summary, "Weekly on Mon, Wed, Fri until Dec 10")
        XCTAssertEqual(RecurrenceBuilder(rrule: rule, zone: newYork), weekly)

        XCTAssertEqual(RecurrenceBuilder(pattern: .weekly([.thursday]), end: .onDate(CivilDate(year: 2026, month: 12, day: 10))).summary,
                       "Weekly on Thursday until Dec 10")
        XCTAssertEqual(RecurrenceBuilder(pattern: .daily, interval: 3, end: .after(12)).summary, "Every 3 days, 12 times")
        XCTAssertEqual(RecurrenceBuilder(pattern: .monthlyByWeekday(ordinal: -1, weekday: .friday)).summary, "Monthly on the last Friday")
        XCTAssertEqual(RecurrenceBuilder(pattern: .monthlyByWeekday(ordinal: 2, weekday: .tuesday), interval: 2).rrule(isAllDay: false, zone: newYork).value,
                       "FREQ=MONTHLY;INTERVAL=2;BYDAY=2TU")
        let allDay = RecurrenceBuilder(pattern: .yearly, end: .onDate(CivilDate(year: 2030, month: 1, day: 1))).rrule(isAllDay: true, zone: newYork)
        XCTAssertEqual(allDay.value, "FREQ=YEARLY;UNTIL=20300101")
        XCTAssertEqual(RecurrenceBuilder(pattern: .weekly([.monday, .tuesday, .wednesday, .thursday, .friday])).summary, "Weekly on weekdays")
    }

    func testBuilderRejectsRulesItCannotShow() {
        XCTAssertNil(RecurrenceBuilder(rrule: RRule(line: "FREQ=MONTHLY;BYDAY=MO,TU;BYSETPOS=1")!))
        XCTAssertNil(RecurrenceBuilder(rrule: RRule(line: "FREQ=DAILY;BYHOUR=9")!))
        let filled = RecurrenceBuilder(recurrence: ["RRULE:FREQ=MONTHLY"], start: CivilDate(year: 2026, month: 9, day: 15))
        XCTAssertEqual(filled?.pattern, .monthlyByDate(15))
    }

    func testSuggestionsIncludeLastWeekday() {
        let patterns = RecurrenceBuilder.suggestions(for: CivilDate(year: 2026, month: 9, day: 24))
        XCTAssertTrue(patterns.contains(.monthlyByWeekday(ordinal: 4, weekday: .thursday)))
        XCTAssertTrue(patterns.contains(.monthlyByWeekday(ordinal: -1, weekday: .thursday)))
        XCTAssertTrue(patterns.contains(.weekly([.thursday])))
    }

    func testCalendarTintMapping() {
        XCTAssertEqual(CalendarTint.from(googleHex: "#e67c73"), .neg)
        XCTAssertEqual(CalendarTint.from(googleHex: "#33b679"), .pos)
        XCTAssertEqual(CalendarTint.from(googleHex: "#a79b8e"), .grey)
        XCTAssertEqual(CalendarTint.from(googleHex: "#f6bf26"), .accent)
        XCTAssertEqual(CalendarTint.from(googleHex: "#039be5"), .signal)
        XCTAssertEqual(CalendarTint.from(googleHex: nil), .accent)
    }

    func testYearMonthCovering() {
        let months = YearMonth.covering(from: ny(2026, 11, 29), to: ny(2027, 1, 3), in: newYork)
        XCTAssertEqual(months.map(\.description), ["2026-11", "2026-12", "2027-01"])
        XCTAssertEqual(YearMonth(year: 2026, month: 0).description, "2025-12")
        XCTAssertEqual(YearMonth(year: 2026, month: 12).adding(months: 1).description, "2027-01")
    }
}
