import XCTest
@testable import ThubanDeskCore

/// The title-bar search over events (Mail is searched by Gmail).
final class SearchMatchTests: XCTestCase {
    private let key = CalendarKey(account: "me@gmail.com", calendarID: "primary")

    private func item(_ id: String, _ title: String, day: Int, hour: Int, series: String? = nil, location: String? = nil,
                      description: String? = nil, guests: [EventAttendee]? = nil, status: String = "confirmed") -> AgendaEvent {
        var event = CalendarEvent(id: id, summary: title, start: EventDateTime(dateTime: ny(2026, 9, day, hour)),
                                  end: EventDateTime(dateTime: ny(2026, 9, day, hour + 1)), description: description,
                                  location: location, attendees: guests, status: status)
        event.recurringEventId = series
        return AgendaEvent(calendar: key, event: event)
    }

    func testMatchesEveryWordAcrossFields() {
        let event = item("a", "Interview — Research assistant", day: 25, hour: 15, location: "Zoom",
                         description: "<p>Bring your <b>résumé</b></p>",
                         guests: [EventAttendee(email: "priya.shah@example.edu", displayName: "Priya Shah")]).event
        XCTAssertTrue(SearchMatch.matches(event, query: "interview"))
        XCTAssertTrue(SearchMatch.matches(event, query: "priya zoom"))
        XCTAssertTrue(SearchMatch.matches(event, query: "RESUME"))
        XCTAssertFalse(SearchMatch.matches(event, query: "priya gym"))
        XCTAssertFalse(SearchMatch.matches(event, query: "   "))
    }

    func testOnePerSeriesUpcomingFirstThenRecentPast() {
        let now = ny(2026, 9, 24, 14, 40)
        let items = [
            item("gym-22", "Gym", day: 22, hour: 7, series: "gym"),
            item("gym-26", "Gym", day: 26, hour: 7, series: "gym"),
            item("gym-24", "Gym", day: 24, hour: 7, series: "gym"),
            item("gym-28", "Gym", day: 28, hour: 7, series: "gym"),
            item("gymclass", "Gym orientation", day: 20, hour: 9),
            item("gone", "Gym (cancelled)", day: 27, hour: 9, status: "cancelled"),
        ]
        let result = SearchMatch.events(items, query: "gym", now: now, zone: newYork)
        XCTAssertEqual(result.map(\.event.id), ["gym-26", "gymclass"])
    }
}
