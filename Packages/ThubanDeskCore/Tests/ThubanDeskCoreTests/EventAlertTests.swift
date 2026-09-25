import XCTest
@testable import ThubanDeskCore

final class EventAlertTests: XCTestCase {
    func testReadsGoogleReminders() {
        XCTAssertEqual(EventAlert(nil), .calendarDefault)
        XCTAssertEqual(EventAlert(EventReminders(useDefault: true)), .calendarDefault)
        XCTAssertEqual(EventAlert(EventReminders(useDefault: false, overrides: [])), .none)
        XCTAssertEqual(EventAlert(EventReminders(useDefault: false, overrides: nil)), .none)
        XCTAssertEqual(EventAlert(EventReminders(useDefault: false, overrides: [ReminderOverride(minutes: 10), ReminderOverride(minutes: 30)])), .minutes(30))
        XCTAssertEqual(EventAlert(EventReminders(useDefault: false, overrides: [ReminderOverride(method: "email", minutes: 1440), ReminderOverride(minutes: 15)])), .minutes(15))
        XCTAssertEqual(EventAlert(EventReminders(useDefault: false, overrides: [ReminderOverride(method: "email", minutes: 60)])), .minutes(60))
    }

    func testWritesGoogleReminders() {
        XCTAssertEqual(EventAlert.calendarDefault.reminders, EventReminders(useDefault: true))
        XCTAssertEqual(EventAlert.none.reminders, EventReminders(useDefault: false, overrides: []))
        XCTAssertEqual(EventAlert.minutes(30).reminders, EventReminders(useDefault: false, overrides: [ReminderOverride(method: "popup", minutes: 30)]))
        for alert in EventAlert.presets { XCTAssertEqual(EventAlert(alert.reminders), alert, "\(alert)") }
    }

    func testLabels() {
        XCTAssertEqual(EventAlert.minutes(30).label, "30 min before")
        XCTAssertEqual(EventAlert.minutes(60).label, "1 hour before")
        XCTAssertEqual(EventAlert.minutes(120).label, "2 hours before")
        XCTAssertEqual(EventAlert.minutes(1440).label, "1 day before")
        XCTAssertEqual(EventAlert.minutes(0).label, "At start")
        XCTAssertEqual(EventAlert.none.label, "None")
    }
}
