import XCTest
@testable import ThubanDeskCore

/// The design's scenario: "Gym · UREC · repeats Tue, Thu, Sat at 7:00 AM" since Aug 25; Thursday Sep 24 moved to 7:30–8:30.
final class RecurrenceEditTests: XCTestCase {
    let calendarID = "gym@fixture"

    func master(count: Int? = nil, days: [Weekday] = [.tuesday, .thursday, .saturday]) -> CalendarEvent {
        var rule = RRule(frequency: .weekly, byDay: days.map { RRule.Day($0) })
        rule.count = count
        var event = CalendarEvent(id: "gym", summary: "Gym · UREC", start: .timed(ny(2026, 8, 25, 7), timeZone: newYork.identifier),
                                  end: .timed(ny(2026, 8, 25, 8), timeZone: newYork.identifier), location: "UREC weight room",
                                  recurrence: [rule.line, "EXDATE;TZID=America/New_York:20261126T070000"])
        event.iCalUID = "gym@google.com"
        event.htmlLink = "https://calendar.google.com/x"
        event.sequence = 3
        return event
    }

    func instance(_ day: Int, month: Int = 9, hour: Int = 7) -> CalendarEvent {
        let start = ny(2026, month, day, hour)
        var event = CalendarEvent(id: "gym_" + RRule.utcStamp(start), summary: "Gym · UREC", start: .timed(start, timeZone: newYork.identifier),
                                  end: .timed(start.addingTimeInterval(3600), timeZone: newYork.identifier), location: "UREC weight room")
        event.recurringEventId = "gym"
        event.originalStartTime = .timed(start, timeZone: newYork.identifier)
        return event
    }

    var moveToSevenThirty: EventPatch {
        EventPatch(start: .timed(ny(2026, 9, 24, 7, 30), timeZone: newYork.identifier), end: .timed(ny(2026, 9, 24, 8, 30), timeZone: newYork.identifier))
    }

    func insertedEvents(_ plan: [CalendarMutation]) -> [CalendarEvent] {
        plan.compactMap { if case .insert(_, let event) = $0 { return event } else { return nil } }
    }

    func patches(_ plan: [CalendarMutation]) -> [(String, EventPatch)] {
        plan.compactMap { if case .patch(_, let id, let patch) = $0 { return (id, patch) } else { return nil } }
    }

    // MARK: Scopes offered

    func testScopesOffered() {
        XCTAssertEqual(RecurrenceEditPlanner.scopes(master: master(), instance: instance(24), zone: newYork),
                       [.thisEvent, .everyWeekday(.thursday), .thisAndFollowing, .allEvents])
        XCTAssertEqual(RecurrenceEditPlanner.scopes(master: master(days: [.wednesday]), instance: instance(23), zone: newYork),
                       [.thisEvent, .thisAndFollowing, .allEvents])
        XCTAssertEqual(RecurrenceEditPlanner.scopes(master: master(), instance: instance(24), zone: newYork, changingRecurrence: true),
                       [.thisAndFollowing, .allEvents])
        var single = instance(24)
        single.recurringEventId = nil
        XCTAssertEqual(RecurrenceEditPlanner.scopes(master: nil, instance: single), [])
        XCTAssertEqual(RecurrenceScope.everyWeekday(.thursday).title, "Every Thursday like this")
    }

    // MARK: Edit

    func testOnlyThisEventPatchesTheInstance() throws {
        var patch = moveToSevenThirty
        patch.recurrence = ["RRULE:FREQ=DAILY"] // ignored for a single occurrence
        let plan = try RecurrenceEditPlanner.planEdit(master: master(), instance: instance(24), patch: patch, scope: .thisEvent, calendarID: calendarID, zone: newYork)
        XCTAssertEqual(plan, [.patch(calendarID: calendarID, eventID: instance(24).id, patch: moveToSevenThirty)])
    }

    func testEveryThursdayLikeThisSplitsTheWeekdays() throws {
        let plan = try RecurrenceEditPlanner.planEdit(master: master(), instance: instance(24), patch: moveToSevenThirty,
                                                      scope: .everyWeekday(.thursday), calendarID: calendarID, zone: newYork)
        XCTAssertEqual(plan.count, 3)
        // 1. Master keeps everything before Sep 24 7:00 EDT (11:00Z).
        let truncation = try XCTUnwrap(patches(plan).first)
        XCTAssertEqual(truncation.0, "gym")
        XCTAssertEqual(truncation.1.recurrence, ["RRULE:FREQ=WEEKLY;BYDAY=TU,TH,SA;UNTIL=20260924T105959Z", "EXDATE;TZID=America/New_York:20261126T070000"])
        XCTAssertNil(truncation.1.start)
        let inserts = insertedEvents(plan)
        XCTAssertEqual(inserts.count, 2)
        // 2. Tuesdays and Saturdays carry on at 7:00 from Saturday Sep 26.
        let rest = inserts[0]
        XCTAssertEqual(rest.recurrence?.first, "RRULE:FREQ=WEEKLY;BYDAY=TU,SA")
        XCTAssertEqual(rest.start.dateTime, ny(2026, 9, 26, 7))
        XCTAssertEqual(rest.end.dateTime, ny(2026, 9, 26, 8))
        XCTAssertEqual(rest.id, "")
        XCTAssertNil(rest.iCalUID)
        XCTAssertNil(rest.sequence)
        XCTAssertEqual(rest.location, "UREC weight room")
        // 3. Thursdays move to 7:30 from Sep 24.
        let thursdays = inserts[1]
        XCTAssertEqual(thursdays.recurrence?.first, "RRULE:FREQ=WEEKLY;BYDAY=TH")
        XCTAssertEqual(thursdays.start.dateTime, ny(2026, 9, 24, 7, 30))
        XCTAssertEqual(thursdays.end.dateTime, ny(2026, 9, 24, 8, 30))
        XCTAssertEqual(thursdays.recurrence?.last, "EXDATE;TZID=America/New_York:20261126T070000")
    }

    func testEveryWeekdayOnTheFirstOccurrencePatchesTheMasterInPlace() throws {
        let first = instance(25, month: 8)
        let patch = EventPatch(start: .timed(ny(2026, 8, 25, 6), timeZone: newYork.identifier), end: .timed(ny(2026, 8, 25, 7), timeZone: newYork.identifier))
        let plan = try RecurrenceEditPlanner.planEdit(master: master(), instance: first, patch: patch, scope: .everyWeekday(.tuesday), calendarID: calendarID, zone: newYork)
        XCTAssertEqual(plan.count, 2)
        let masterPatch = try XCTUnwrap(patches(plan).first)
        XCTAssertEqual(masterPatch.1.recurrence?.first, "RRULE:FREQ=WEEKLY;BYDAY=TH,SA")
        XCTAssertEqual(masterPatch.1.start?.dateTime, ny(2026, 8, 27, 7))
        XCTAssertEqual(insertedEvents(plan).first?.recurrence?.first, "RRULE:FREQ=WEEKLY;BYDAY=TU")
        XCTAssertEqual(insertedEvents(plan).first?.start.dateTime, ny(2026, 8, 25, 6))
    }

    func testThisAndFollowingTruncatesAndStartsANewSeries() throws {
        var patch = moveToSevenThirty
        patch.summary = "Gym · UREC (new time)"
        let plan = try RecurrenceEditPlanner.planEdit(master: master(), instance: instance(24), patch: patch, scope: .thisAndFollowing, calendarID: calendarID, zone: newYork)
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(patches(plan).first?.1.recurrence?.first, "RRULE:FREQ=WEEKLY;BYDAY=TU,TH,SA;UNTIL=20260924T105959Z")
        let series = try XCTUnwrap(insertedEvents(plan).first)
        XCTAssertEqual(series.summary, "Gym · UREC (new time)")
        XCTAssertEqual(series.recurrence?.first, "RRULE:FREQ=WEEKLY;BYDAY=TU,TH,SA")
        XCTAssertEqual(series.start.dateTime, ny(2026, 9, 24, 7, 30))
        XCTAssertEqual(series.status, "confirmed")
    }

    func testThisAndFollowingOnTheFirstOccurrenceIsAllEvents() throws {
        let plan = try RecurrenceEditPlanner.planEdit(master: master(), instance: instance(25, month: 8), patch: EventPatch(summary: "Lift"),
                                                      scope: .thisAndFollowing, calendarID: calendarID, zone: newYork)
        XCTAssertEqual(plan, [.patch(calendarID: calendarID, eventID: "gym", patch: EventPatch(summary: "Lift"))])
    }

    func testCountIsSplitBetweenTheSeries() throws {
        // COUNT=10 from Tue Aug 25: Aug 25, 27, 29, Sep 1 | Sep 3 (Th), 5, 8, 10 (Th), 12, 15.
        let plan = try RecurrenceEditPlanner.planEdit(master: master(count: 10), instance: instance(3), patch: EventPatch(location: "Rec center"),
                                                      scope: .thisAndFollowing, calendarID: calendarID, zone: newYork)
        XCTAssertEqual(patches(plan).first?.1.recurrence?.first, "RRULE:FREQ=WEEKLY;BYDAY=TU,TH,SA;UNTIL=20260903T105959Z")
        XCTAssertEqual(insertedEvents(plan).first?.recurrence?.first, "RRULE:FREQ=WEEKLY;BYDAY=TU,TH,SA;COUNT=6")

        let split = try RecurrenceEditPlanner.planEdit(master: master(count: 10), instance: instance(3), patch: EventPatch(location: "Rec center"),
                                                       scope: .everyWeekday(.thursday), calendarID: calendarID, zone: newYork)
        let inserts = insertedEvents(split)
        XCTAssertEqual(inserts[0].recurrence?.first, "RRULE:FREQ=WEEKLY;BYDAY=TU,SA;COUNT=4")
        XCTAssertEqual(inserts[0].start.dateTime, ny(2026, 9, 5, 7))
        XCTAssertEqual(inserts[1].recurrence?.first, "RRULE:FREQ=WEEKLY;BYDAY=TH;COUNT=2")
        XCTAssertEqual(inserts[1].location, "Rec center")
    }

    func testAllEventsShiftsTheMasterByTheSameWallClockChange() throws {
        let plan = try RecurrenceEditPlanner.planEdit(master: master(), instance: instance(24), patch: moveToSevenThirty, scope: .allEvents, calendarID: calendarID, zone: newYork)
        let patch = try XCTUnwrap(patches(plan).first)
        XCTAssertEqual(patch.0, "gym")
        XCTAssertEqual(patch.1.start?.dateTime, ny(2026, 8, 25, 7, 30))
        XCTAssertEqual(patch.1.end?.dateTime, ny(2026, 8, 25, 8, 30))
        XCTAssertNil(patch.1.recurrence, "same weekdays: the rule is untouched")

        // Moving Thursday to Friday moves every weekday by one day.
        let friday = EventPatch(start: .timed(ny(2026, 9, 25, 7), timeZone: newYork.identifier), end: .timed(ny(2026, 9, 25, 8), timeZone: newYork.identifier))
        let moved = try RecurrenceEditPlanner.planEdit(master: master(), instance: instance(24), patch: friday, scope: .allEvents, calendarID: calendarID, zone: newYork)
        let shifted = try XCTUnwrap(patches(moved).first?.1)
        XCTAssertEqual(shifted.start?.dateTime, ny(2026, 8, 26, 7))
        XCTAssertEqual(shifted.recurrence?.first, "RRULE:FREQ=WEEKLY;BYDAY=WE,FR,SU")
    }

    func testAllEventsAcrossDSTKeepsLocalTime() throws {
        // Instance in EST (Nov 5) moved 7:00 → 6:00; master start in EDT (Aug 25) becomes 6:00 EDT.
        let late = instance(5, month: 11)
        let patch = EventPatch(start: .timed(ny(2026, 11, 5, 6), timeZone: newYork.identifier), end: .timed(ny(2026, 11, 5, 7), timeZone: newYork.identifier))
        let plan = try RecurrenceEditPlanner.planEdit(master: master(), instance: late, patch: patch, scope: .allEvents, calendarID: calendarID, zone: newYork)
        XCTAssertEqual(patches(plan).first?.1.start?.dateTime, ny(2026, 8, 25, 6))
    }

    func testChangingTheRuleForFollowingEvents() throws {
        let patch = EventPatch(recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO,WE"])
        let plan = try RecurrenceEditPlanner.planEdit(master: master(), instance: instance(24), patch: patch, scope: .thisAndFollowing, calendarID: calendarID, zone: newYork)
        XCTAssertEqual(insertedEvents(plan).first?.recurrence, ["RRULE:FREQ=WEEKLY;BYDAY=MO,WE"])
        let never = try RecurrenceEditPlanner.planEdit(master: master(), instance: instance(24), patch: EventPatch(recurrence: []), scope: .thisAndFollowing,
                                                       calendarID: calendarID, zone: newYork)
        XCTAssertNil(insertedEvents(never).first?.recurrence)
    }

    func testSingleEventEditAndDelete() throws {
        var single = instance(24)
        single.recurringEventId = nil
        single.id = "one-off"
        XCTAssertEqual(try RecurrenceEditPlanner.planEdit(master: nil, instance: single, patch: EventPatch(summary: "X"), scope: .allEvents, calendarID: "c"),
                       [.patch(calendarID: "c", eventID: "one-off", patch: EventPatch(summary: "X"))])
        XCTAssertEqual(try RecurrenceEditPlanner.planDelete(master: nil, instance: single, scope: .thisEvent, calendarID: "c"), [.delete(calendarID: "c", eventID: "one-off")])
    }

    func testEveryWeekdayRejectsAMismatchedDay() {
        XCTAssertThrowsError(try RecurrenceEditPlanner.planEdit(master: master(), instance: instance(24), patch: moveToSevenThirty,
                                                                scope: .everyWeekday(.tuesday), calendarID: calendarID, zone: newYork))
    }

    // MARK: Delete

    func testDeleteScopes() throws {
        XCTAssertEqual(try RecurrenceEditPlanner.planDelete(master: master(), instance: instance(24), scope: .thisEvent, calendarID: calendarID, zone: newYork),
                       [.delete(calendarID: calendarID, eventID: instance(24).id)])
        XCTAssertEqual(try RecurrenceEditPlanner.planDelete(master: master(), instance: instance(24), scope: .allEvents, calendarID: calendarID, zone: newYork),
                       [.delete(calendarID: calendarID, eventID: "gym")])
        let following = try RecurrenceEditPlanner.planDelete(master: master(), instance: instance(24), scope: .thisAndFollowing, calendarID: calendarID, zone: newYork)
        XCTAssertEqual(following.count, 1)
        XCTAssertEqual(patches(following).first?.1.recurrence?.first, "RRULE:FREQ=WEEKLY;BYDAY=TU,TH,SA;UNTIL=20260924T105959Z")
        XCTAssertEqual(try RecurrenceEditPlanner.planDelete(master: master(), instance: instance(25, month: 8), scope: .thisAndFollowing, calendarID: calendarID, zone: newYork),
                       [.delete(calendarID: calendarID, eventID: "gym")])
        let thursdays = try RecurrenceEditPlanner.planDelete(master: master(), instance: instance(24), scope: .everyWeekday(.thursday), calendarID: calendarID, zone: newYork)
        XCTAssertEqual(thursdays.count, 2)
        XCTAssertEqual(insertedEvents(thursdays).first?.recurrence?.first, "RRULE:FREQ=WEEKLY;BYDAY=TU,SA")
    }

    func testAllDaySeriesTruncatesWithADate() throws {
        var birthday = CalendarEvent(id: "bday", summary: "Mom’s birthday", start: .allDay(CivilDate(year: 2020, month: 9, day: 26)),
                                     end: .allDay(CivilDate(year: 2020, month: 9, day: 27)), recurrence: ["RRULE:FREQ=YEARLY"])
        birthday.iCalUID = "b"
        var occurrence = CalendarEvent(id: "bday_20260926", summary: "Mom’s birthday", start: .allDay(CivilDate(year: 2026, month: 9, day: 26)),
                                       end: .allDay(CivilDate(year: 2026, month: 9, day: 27)))
        occurrence.recurringEventId = "bday"
        occurrence.originalStartTime = .allDay(CivilDate(year: 2026, month: 9, day: 26))
        let plan = try RecurrenceEditPlanner.planDelete(master: birthday, instance: occurrence, scope: .thisAndFollowing, calendarID: "p", zone: newYork)
        XCTAssertEqual(patches(plan).first?.1.recurrence, ["RRULE:FREQ=YEARLY;UNTIL=20260925"])
    }

    // MARK: Against the fixture backend

    func testPlansRunAgainstTheFixtureBackend() async throws {
        let backend = FixtureGoogle(world: SampleData.world(now: designNow, zone: newYork))
        let client = fixtureClient(backend, account: SampleData.primaryEmail)
        let week = (ny(2026, 9, 20), ny(2026, 9, 27))
        let before = try await client.events(calendarID: "gym@fixture", from: week.0, to: week.1)
        XCTAssertEqual(before.map { CivilDate($0.startDate(in: newYork), in: newYork).day }, [22, 24, 26])
        let thursday = try XCTUnwrap(before.first { CivilDate($0.startDate(in: newYork), in: newYork).day == 24 })
        let master = try await client.master(of: thursday, calendarID: "gym@fixture")
        XCTAssertTrue(master.isRecurringMaster)
        let plan = try RecurrenceEditPlanner.planEdit(master: master, instance: thursday, patch: moveToSevenThirty, scope: .everyWeekday(.thursday),
                                                      calendarID: "gym@fixture", zone: newYork)
        try await client.perform(plan)

        let after = try await client.events(calendarID: "gym@fixture", from: week.0, to: week.1)
        let times = after.map { ($0.startDate(in: newYork), $0.title) }
        XCTAssertEqual(times.map { Calendar.gregorian(newYork).dateComponents([.day, .hour, .minute], from: $0.0) }.map { "\($0.day!) \($0.hour!):\($0.minute!)" },
                       ["22 7:0", "24 7:30", "26 7:0"])
        // Last week's Thursday is untouched.
        let lastWeek = try await client.events(calendarID: "gym@fixture", from: ny(2026, 9, 17), to: ny(2026, 9, 18))
        XCTAssertEqual(lastWeek.first?.startDate(in: newYork), ny(2026, 9, 17, 7))
        // Next week follows the split.
        let next = try await client.events(calendarID: "gym@fixture", from: ny(2026, 9, 27), to: ny(2026, 10, 4))
        XCTAssertEqual(next.map { Calendar.gregorian(newYork).component(.minute, from: $0.startDate(in: newYork)) }, [0, 30, 0])
        XCTAssertFalse(backend.log.contains { $0.contains("send") })
    }
}
