import XCTest
@testable import ThubanDeskCore

/// Layout and wording used by the calendar views (overlap columns, lanes, snapping, the design's strings).
final class CalendarViewLogicTests: XCTestCase {
    // MARK: Overlap columns

    func testSeparateEventsTakeTheFullWidth() {
        let slots = EventLayout.columns([(start: 420, end: 480), (start: 600, end: 660)])
        XCTAssertEqual(slots, [EventLayout.Slot(column: 0, columns: 1), EventLayout.Slot(column: 0, columns: 1)])
    }

    func testTouchingEventsDoNotOverlap() {
        let slots = EventLayout.columns([(start: 420, end: 480), (start: 480, end: 540)])
        XCTAssertEqual(slots.map(\.columns), [1, 1])
    }

    func testOverlapChainSharesColumnsAndLastSpreads() {
        // A 9–11, B 9:30–10, C 10:30–12: A|B then A|C → two columns; B and C share column 1.
        let slots = EventLayout.columns([(start: 540, end: 660), (start: 570, end: 600), (start: 630, end: 720)])
        XCTAssertEqual(slots.map(\.column), [0, 1, 1])
        XCTAssertEqual(slots.map(\.columns), [2, 2, 2])
        XCTAssertEqual(slots.map(\.span), [1, 1, 1])
    }

    func testEventSpreadsIntoFreeColumnsOnItsRight() {
        // A 9–12 and B 9–10 and C 9–10:30 → 3 columns; D 11–12 sits in column 1 and spreads over column 2.
        let slots = EventLayout.columns([(start: 540, end: 720), (start: 540, end: 600), (start: 540, end: 630), (start: 660, end: 720)])
        XCTAssertEqual(slots[0], EventLayout.Slot(column: 0, columns: 3, span: 1))
        XCTAssertEqual(slots[3].column, 1)
        XCTAssertEqual(slots[3].span, 2)
        XCTAssertEqual(slots[3].fraction.width, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testShortEventsGetAMinimumLength() {
        let slots = EventLayout.columns([(start: 600, end: 600), (start: 610, end: 640)], minimumLength: 20)
        XCTAssertEqual(slots.map(\.columns), [2, 2])
    }

    func testLanesForAllDayBars() {
        // Week bars: Mon–Wed, Tue, Thu, Wed–Fri.
        let lanes = EventLayout.lanes([1...3, 2...2, 4...4, 3...5])
        XCTAssertEqual(lanes, [0, 1, 0, 1])
    }

    func testSnapToQuarterHours() {
        XCTAssertEqual(EventLayout.snap(minutes: 22), 15)
        XCTAssertEqual(EventLayout.snap(minutes: 23), 30)
        XCTAssertEqual(EventLayout.snap(minutes: -8), -15)
        XCTAssertEqual(EventLayout.snap(minutes: 7), 0)
    }

    func testDateOnDayKeepsWallClock() {
        let day = CivilDate(year: 2026, month: 11, day: 1) // DST ends in New York
        XCTAssertEqual(EventLayout.date(on: day, minutes: 9 * 60 + 30, zone: newYork), ny(2026, 11, 1, 9, 30))
        XCTAssertEqual(EventLayout.date(on: CivilDate(year: 2026, month: 9, day: 24), minutes: 24 * 60 + 30, zone: newYork), ny(2026, 9, 25, 0, 30))
        XCTAssertEqual(EventLayout.minutes(of: ny(2026, 9, 24, 14, 40), from: CivilDate(year: 2026, month: 9, day: 24), zone: newYork), 880)
    }

    // MARK: Words

    func testClockStrings() {
        XCTAssertEqual(CalendarText.timeRange(ny(2026, 9, 24, 19), ny(2026, 9, 24, 20, 30), zone: newYork), "7:00 – 8:30 PM")
        XCTAssertEqual(CalendarText.timeRange(ny(2026, 9, 24, 11, 30), ny(2026, 9, 24, 12, 45), zone: newYork), "11:30 AM – 12:45 PM")
        XCTAssertEqual(CalendarText.compactTime(ny(2026, 9, 24, 7), zone: newYork), "7am")
        XCTAssertEqual(CalendarText.compactTime(ny(2026, 9, 24, 13, 25), zone: newYork), "1:25pm")
        XCTAssertEqual(CalendarText.hourLabel(0), "12 AM")
        XCTAssertEqual(CalendarText.hourLabel(12), "12 PM")
        XCTAssertEqual(CalendarText.hourLabel(20), "8 PM")
        XCTAssertEqual(CalendarText.duration(minutes: 90), "1 h 30 m")
        XCTAssertEqual(CalendarText.duration(minutes: 45), "45 m")
        XCTAssertEqual(CalendarText.duration(minutes: 120), "2 h")
    }

    func testTitles() {
        XCTAssertEqual(CalendarText.rangeTitle(from: CivilDate(year: 2026, month: 9, day: 20), to: CivilDate(year: 2026, month: 9, day: 26)), "September 20 – 26, 2026")
        XCTAssertEqual(CalendarText.rangeTitle(from: CivilDate(year: 2026, month: 9, day: 27), to: CivilDate(year: 2026, month: 10, day: 3)), "Sep 27 – Oct 3, 2026")
        XCTAssertEqual(CalendarText.rangeTitle(from: CivilDate(year: 2026, month: 12, day: 27), to: CivilDate(year: 2027, month: 1, day: 2)), "Dec 27, 2026 – Jan 2, 2027")
        XCTAssertEqual(CalendarText.monthTitle(year: 2026, month: 9), "September 2026")
        XCTAssertEqual(CalendarText.dayTitle(CivilDate(year: 2026, month: 9, day: 24)), "Thursday, September 24, 2026")
        XCTAssertEqual(CalendarText.editorDate(CivilDate(year: 2026, month: 12, day: 10)), "Thu, Dec 10, 2026")
    }

    func testWhenLines() {
        let group = CalendarEvent(summary: "Study group", start: .timed(ny(2026, 9, 24, 19), timeZone: newYork.identifier),
                                  end: .timed(ny(2026, 9, 24, 20, 30), timeZone: newYork.identifier))
        XCTAssertEqual(CalendarText.when(group, zone: newYork), "Thursday, September 24 · 7:00 – 8:30 PM")
        let birthday = CalendarEvent(summary: "Mom’s birthday", start: .allDay(CivilDate(year: 2026, month: 9, day: 26)), end: .allDay(CivilDate(year: 2026, month: 9, day: 27)))
        XCTAssertEqual(CalendarText.when(birthday, zone: newYork), "Saturday, September 26 · All day")
        let trip = CalendarEvent(summary: "Trip", start: .allDay(CivilDate(year: 2026, month: 9, day: 25)), end: .allDay(CivilDate(year: 2026, month: 9, day: 28)))
        XCTAssertEqual(CalendarText.when(trip, zone: newYork), "Sep 25 – 27 · All day")
        let interview = CalendarEvent(summary: "Interview", start: .timed(ny(2026, 9, 25, 15), timeZone: nil), end: .timed(ny(2026, 9, 25, 15, 45), timeZone: nil))
        XCTAssertEqual(CalendarText.shortWhen(interview, zone: newYork), "Fri, Sep 25 · 3:00 – 3:45 PM")
    }

    func testGuestSummaries() {
        var group = CalendarEvent(summary: "Study group", start: .timed(ny(2026, 9, 24, 19), timeZone: nil), end: .timed(ny(2026, 9, 24, 20, 30), timeZone: nil))
        group.attendees = [
            EventAttendee(email: "maya@x.edu", displayName: "Maya Chen", organizer: true, responseStatus: .accepted),
            EventAttendee(email: "me@x.edu", isSelf: true, responseStatus: .accepted),
            EventAttendee(email: "sam@x.edu", responseStatus: .accepted),
            EventAttendee(email: "leah@x.edu", responseStatus: .needsAction),
        ]
        XCTAssertEqual(CalendarText.guestSummary(group), "4 guests · 3 going, 1 no reply")
        XCTAssertEqual(CalendarText.replyCounts(group.attendees ?? []), "3 going · 1 no reply")

        var invite = group
        invite.attendees = [
            EventAttendee(email: "priya@crescent.com", displayName: "Priya Shah", organizer: true, responseStatus: .accepted),
            EventAttendee(email: "me@x.edu", isSelf: true, responseStatus: .needsAction),
        ]
        invite.organizer = EventPerson(email: "priya@crescent.com", displayName: "Priya Shah")
        XCTAssertEqual(CalendarText.guestSummary(invite), "Priya Shah invited you · awaiting your reply")
        XCTAssertNil(CalendarText.guestSummary(CalendarEvent(summary: "Solo", start: group.start, end: group.end)))
        XCTAssertEqual(CalendarText.list(["Tuesdays", "Saturdays"]), "Tuesdays and Saturdays")
        XCTAssertEqual(CalendarText.list(["Tue", "Thu", "Sat"]), "Tue, Thu and Sat")
    }

    // MARK: Scope dialog (design: RecurringScope)

    func gymMaster() -> CalendarEvent {
        CalendarEvent(id: "gym", summary: "Gym · UREC", start: .timed(ny(2026, 8, 25, 7), timeZone: newYork.identifier),
                      end: .timed(ny(2026, 8, 25, 8), timeZone: newYork.identifier),
                      recurrence: [RRule(frequency: .weekly, byDay: [.init(.tuesday), .init(.thursday), .init(.saturday)]).line])
    }

    func gymThursday() -> CalendarEvent {
        var event = CalendarEvent(id: "gym_20260924T110000Z", summary: "Gym · UREC", start: .timed(ny(2026, 9, 24, 7), timeZone: newYork.identifier),
                                  end: .timed(ny(2026, 9, 24, 8), timeZone: newYork.identifier))
        event.recurringEventId = "gym"
        event.originalStartTime = event.start
        return event
    }

    func testScopeTextsMatchTheDesign() {
        let master = gymMaster(), instance = gymThursday()
        let move = CalendarText.ScopeAction.move(start: .timed(ny(2026, 9, 24, 7, 30), timeZone: newYork.identifier),
                                                 end: .timed(ny(2026, 9, 24, 8, 30), timeZone: newYork.identifier))
        XCTAssertEqual(CalendarText.seriesSubtitle(master: master, zone: newYork), "repeats Tue, Thu, Sat at 7:00 AM")
        XCTAssertEqual(CalendarText.scopePrompt(move, instance: instance, zone: newYork),
                       "You moved Thursday’s session from **7:00** to **7:30 – 8:30 AM**. Which events should change?")
        func detail(_ scope: RecurrenceScope) -> String {
            CalendarText.scopeDetail(scope, action: move, master: master, instance: instance, zone: newYork)
        }
        XCTAssertEqual(detail(.thisEvent), "Thursday, September 24 moves to 7:30 AM.")
        XCTAssertEqual(detail(.everyWeekday(.thursday)), "Thursdays move to 7:30 AM. Tuesdays and Saturdays stay at 7:00.")
        XCTAssertEqual(detail(.thisAndFollowing), "Every Tue, Thu and Sat from Sep 24 on moves to 7:30 AM.")
        XCTAssertEqual(detail(.allEvents), "The whole series moves, including past events since Aug 25.")
        XCTAssertEqual(CalendarText.scopeButton(move), "Move events")
        XCTAssertEqual(CalendarText.scopeTitle(.delete), "Delete a repeating event")
        XCTAssertEqual(CalendarText.scopeDetail(.everyWeekday(.thursday), action: .delete, master: master, instance: instance, zone: newYork),
                       "Thursdays from Sep 24 on are deleted. Tuesdays and Saturdays stay.")
    }

    // MARK: Description HTML + time parsing

    func testDescriptionHTMLRoundTrips() {
        typealias Run = DescriptionHTML.Run
        let lines: [[Run]] = [
            [Run("Bring your attempts at "), Run("Homework 4, Q3 and Q5", bold: true), Run(". We’ll split the whiteboard:")],
            [Run("• Maya — partial derivatives")],
            [Run("• You — limits along paths")],
            [Run("Notes: "), Run("MATH 2210 study notes", link: "https://docs.google.com/document/d/x"), Run(" <soon>", italic: true, underline: true)],
            [Run("")],
        ]
        let html = DescriptionHTML.html(lines: lines)
        XCTAssertEqual(html, "Bring your attempts at <b>Homework 4, Q3 and Q5</b>. We’ll split the whiteboard:<ul><li>Maya — partial derivatives</li><li>You — limits along paths</li></ul>Notes: <a href=\"https://docs.google.com/document/d/x\">MATH 2210 study notes</a><i><u> &lt;soon&gt;</u></i>")
        let text = String(HTMLSanitizer.richText(html).characters)
        XCTAssertEqual(text, "Bring your attempts at Homework 4, Q3 and Q5. We’ll split the whiteboard:\n• Maya — partial derivatives\n• You — limits along paths\nNotes: MATH 2210 study notes <soon>")
        XCTAssertEqual(DescriptionHTML.html(lines: [[Run("1. First")], [Run("2. Second")], [Run("a")], [Run("")], [Run("b")]]),
                       "<ol><li>First</li><li>Second</li></ol>a<br><br>b")
        XCTAssertEqual(DescriptionHTML.html(lines: [[Run("x", link: "javascript:alert(1)")]]), "x")
    }

    func testParseClock() {
        XCTAssertEqual(CalendarText.parseClock("7:30 PM"), 19 * 60 + 30)
        XCTAssertEqual(CalendarText.parseClock("7pm"), 19 * 60)
        XCTAssertEqual(CalendarText.parseClock("730p"), 19 * 60 + 30)
        XCTAssertEqual(CalendarText.parseClock("19:30"), 19 * 60 + 30)
        XCTAssertEqual(CalendarText.parseClock("12:15 am"), 15)
        XCTAssertEqual(CalendarText.parseClock("noon"), 720)
        XCTAssertEqual(CalendarText.parseClock("9"), 540)
        XCTAssertNil(CalendarText.parseClock("25:00"))
        XCTAssertNil(CalendarText.parseClock("7:75"))
        XCTAssertNil(CalendarText.parseClock("soon"))
        XCTAssertEqual(CalendarText.clock(minutes: 19 * 60 + 30), "7:30 PM")
    }
}
