import Foundation
import XCTest
@testable import ThubanDeskCore

final class TodayLinksTests: XCTestCase {
    let own: Set<String> = [SampleData.primaryEmail, SampleData.schoolEmail]

    /// Today + tomorrow from the fake Google (instances expanded, as the app loads them).
    func designEvents() async throws -> [AgendaEvent] {
        let backend = FixtureGoogle(world: SampleData.world(now: designNow, zone: newYork))
        var items: [AgendaEvent] = []
        for account in [SampleData.primaryEmail, SampleData.schoolEmail] {
            let client = fixtureClient(backend, account: account)
            for calendar in try await client.calendarList() {
                let events = try await client.events(calendarID: calendar.id, from: ny(2026, 9, 24), to: ny(2026, 9, 26))
                items += events.map { AgendaEvent(calendar: CalendarKey(account: account, calendarID: calendar.id), event: $0) }
            }
        }
        return items
    }

    func testDesignLinks() async throws {
        let events = try await designEvents()
        let invitations = TodayAgenda.pendingInvitations(events, after: designNow, zone: newYork)
        XCTAssertEqual(invitations.map(\.event.title), ["Interview · Crescent Labs"])

        let priya = try XCTUnwrap(TodayLinks.link(sender: "Priya.Shah@crescentlabs-hq.example", events: events, invitations: invitations, own: own, now: designNow, zone: newYork))
        XCTAssertEqual(priya.kind, .invitation)
        XCTAssertEqual(TodayLinks.phrase(for: priya, now: designNow, zone: newYork), "About the invitation for Fri 3:00 PM — answer it below")

        let maya = try XCTUnwrap(TodayLinks.link(sender: "maya.chen@students.example.edu", events: events, invitations: invitations, own: own, now: designNow, zone: newYork))
        XCTAssertEqual(maya.kind, .event)
        XCTAssertEqual(maya.event.event.title, "Study group · MATH 2210")
        XCTAssertEqual(TodayLinks.phrase(for: maya, now: designNow, zone: newYork), "For Study group tonight at 7:00 PM")

        XCTAssertNil(TodayLinks.link(sender: "morgan.mom@example.com", events: events, invitations: invitations, own: own, now: designNow, zone: newYork))
        XCTAssertEqual(TodayLinks.guestLine(of: maya.event.event), "with Maya, Sam, Leah")
        XCTAssertEqual(TodayLinks.inviter(of: priya.event.event), "Priya Shah")
        XCTAssertTrue(TodayLinks.conflicts(of: priya.event, among: events, zone: newYork).isEmpty, "the design says: no conflicts")
    }

    func testExcerptsAndAges() async throws {
        let backend = FixtureGoogle(world: SampleData.world(now: designNow, zone: newYork))
        var quotes: [String: String] = [:]
        for account in [SampleData.primaryEmail, SampleData.schoolEmail] {
            let client = fixtureClient(backend, account: account)
            for ref in try await client.threadRefs(labelIDs: ["INBOX"]) {
                let thread = try await client.thread(ref.id)
                let verdict = NeedsReply.classify(thread, ownAddresses: own, now: designNow)
                guard verdict.needsReply, let name = thread.messages.last(where: { !$0.isDraft })?.from?.displayName else { continue }
                quotes[name] = TodayLinks.excerpt(of: thread, verdict: verdict)
            }
        }
        XCTAssertEqual(quotes["Priya Shah"], "Could you accept the invite or reply to confirm by tomorrow morning?")
        XCTAssertEqual(quotes["Maya Chen"], "Still on for 7 in Atkins 244? Can you grab whiteboard markers on your way — the ones there are dead.")
        XCTAssertEqual(quotes["Mom"], "What time are you coming Saturday? Aunt Carol wants to do lunch at 1.")

        XCTAssertEqual(TodayLinks.age(designNow.addingTimeInterval(-26 * 60), now: designNow, zone: newYork), "26 min ago")
        XCTAssertEqual(TodayLinks.age(ny(2026, 9, 24, 9), now: designNow, zone: newYork), "5 h ago")
        XCTAssertEqual(TodayLinks.age(ny(2026, 9, 23, 22), now: designNow, zone: newYork), "Yesterday")
        XCTAssertEqual(TodayLinks.age(ny(2026, 9, 22, 18, 40), now: designNow, zone: newYork), "2 days ago")
    }

    func testFinishedEventsDoNotLink() {
        let key = CalendarKey(account: "me@x.org", calendarID: "c")
        var past = CalendarEvent(id: "p", summary: "Coffee", start: .timed(ny(2026, 9, 24, 9), timeZone: nil), end: .timed(ny(2026, 9, 24, 10), timeZone: nil),
                                 attendees: [EventAttendee(email: "a@x.org"), EventAttendee(email: "me@x.org", isSelf: true, responseStatus: .accepted)])
        XCTAssertNil(TodayLinks.link(sender: "a@x.org", events: [AgendaEvent(calendar: key, event: past)], invitations: [], own: ["me@x.org"], now: designNow, zone: newYork))
        past.start = .timed(ny(2026, 9, 25, 9), timeZone: nil)
        past.end = .timed(ny(2026, 9, 25, 10), timeZone: nil)
        let link = TodayLinks.link(sender: "a@x.org", events: [AgendaEvent(calendar: key, event: past)], invitations: [], own: ["me@x.org"], now: designNow, zone: newYork)
        XCTAssertEqual(link.map { TodayLinks.phrase(for: $0, now: designNow, zone: newYork) }, "For Coffee tomorrow at 9:00 AM")
    }

    func testPhrasesAndConflicts() {
        XCTAssertEqual(TodayLinks.shortTitle("Gym · UREC"), "Gym")
        XCTAssertEqual(TodayLinks.shortTitle("Laundry"), "Laundry")
        XCTAssertEqual(TodayLinks.range(ny(2026, 9, 25, 15), ny(2026, 9, 25, 15, 45), zone: newYork), "3:00 – 3:45 PM")
        XCTAssertEqual(TodayLinks.range(ny(2026, 9, 25, 11, 30), ny(2026, 9, 25, 12, 45), zone: newYork), "11:30 AM – 12:45 PM")
        XCTAssertEqual(TodayLinks.relativeTime(ny(2026, 9, 24, 11), now: designNow, zone: newYork), "today at 11:00 AM")
        XCTAssertEqual(TodayLinks.relativeTime(ny(2026, 9, 28, 11), now: designNow, zone: newYork), "on Mon at 11:00 AM")
        let key = CalendarKey(account: "a", calendarID: "c")
        func item(_ id: String, _ h: Int, _ h2: Int) -> AgendaEvent {
            var event = CalendarEvent(id: id, summary: id, start: .timed(ny(2026, 9, 25, h), timeZone: nil), end: .timed(ny(2026, 9, 25, h2), timeZone: nil))
            event.iCalUID = id
            return AgendaEvent(calendar: key, event: event)
        }
        let invite = item("invite", 15, 16)
        XCTAssertEqual(TodayLinks.conflicts(of: invite, among: [invite, item("a", 14, 15), item("b", 15, 17)], zone: newYork).map(\.event.id), ["b"])
        let stat = item("stat", 14, 16)
        XCTAssertEqual(TodayLinks.progress(of: stat, now: ny(2026, 9, 25, 15), zone: newYork), 0.5, accuracy: 0.001)
    }
}
