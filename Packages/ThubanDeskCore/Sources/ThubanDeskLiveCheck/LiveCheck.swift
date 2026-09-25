// Live check against a REAL Google Calendar: creates one clearly-labelled test event, reads it back, deletes it,
// and confirms it is gone. Nothing else is touched (no mail, no other events, no sends).
//
// NEVER run by build / test / smoke scripts. To run it deliberately (after signing in with the app):
//
//   THUBAN_DESK_LIVE_CHECK=create-and-delete-test-event \
//   THUBAN_DESK_LIVE_CALENDAR="<calendar id or exact name>" \
//   [THUBAN_DESK_LIVE_ACCOUNT=<email>] [THUBAN_DESK_HOME=<dir>] \
//   swift run --package-path Packages/ThubanDeskCore thuban-desk-live-check
//
// or scripts/live_check.sh. Exit status 0 = the event was created, read back correctly and deleted.
import Foundation
import ThubanDeskCore

@main
struct LiveCheck {
    static let confirmation = "create-and-delete-test-event"

    static func main() async {
        let env = ProcessInfo.processInfo.environment
        guard env["THUBAN_DESK_LIVE_CHECK"] == confirmation else {
            fputs("Refusing to run: set THUBAN_DESK_LIVE_CHECK=\(confirmation) to create and delete one test event on a real calendar.\n", stderr)
            exit(2)
        }
        guard let calendarName = env["THUBAN_DESK_LIVE_CALENDAR"], !calendarName.isEmpty else {
            fputs("Set THUBAN_DESK_LIVE_CALENDAR to the calendar id or name to use (a calendar you own).\n", stderr)
            exit(2)
        }
        do {
            try await run(calendarName: calendarName, accountEmail: env["THUBAN_DESK_LIVE_ACCOUNT"])
            print("live-check: PASS")
            exit(0)
        } catch {
            fputs("live-check: FAIL — \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func run(calendarName: String, accountEmail: String?) async throws {
        let file = try CredentialStore.load()
        guard file.client != nil else { throw ThubanError.missingClientID }
        guard let account = accountEmail.flatMap(file.account) ?? file.primary else { throw ThubanError.notSignedIn(accountEmail) }
        let tokens = AccountTokenStore(file: file)
        // Calendar writes only; sending mail is impossible from this client.
        let client = GoogleClient(accountID: account.id, tokens: tokens, gate: WriteGate(allowWrites: { true }, allowSend: { false }))

        let calendars = try await client.calendarList()
        guard let calendar = calendars.first(where: { $0.id == calendarName }) ?? calendars.first(where: { $0.displayName == calendarName }) else {
            throw ThubanError.store("No calendar named \(calendarName) in \(account.email).")
        }
        guard calendar.canWrite else { throw ThubanError.store("\(calendar.displayName) is read-only.") }
        print("live-check: account \(account.email), calendar \(calendar.displayName) (\(calendar.id))")

        let zone = calendar.zone
        let tomorrow = CivilDate(Date(), in: zone).adding(days: 1)
        let start = Calendar.gregorian(zone).date(from: DateComponents(year: tomorrow.year, month: tomorrow.month, day: tomorrow.day, hour: 9)) ?? Date()
        let marker = UUID().uuidString.prefix(8)
        let summary = "Thuban Desk live check \(marker) — safe to delete"
        let draft = CalendarEvent(summary: summary, start: .timed(start, timeZone: zone.identifier),
                                  end: .timed(start.addingTimeInterval(15 * 60), timeZone: zone.identifier),
                                  description: "Created by the Thuban Desk live check; deleted automatically.")

        let created = try await client.insertEvent(draft, calendarID: calendar.id, sendUpdates: .none)
        print("live-check: created \(created.id)")
        var failure: Error?
        do {
            let fetched = try await client.event(calendarID: calendar.id, eventID: created.id)
            guard fetched.summary == summary else { throw ThubanError.store("Read back a different title: \(fetched.summary ?? "nil")") }
            guard let fetchedStart = fetched.start.dateTime, abs(fetchedStart.timeIntervalSince(start)) < 1 else {
                throw ThubanError.store("Read back a different start time.")
            }
            let listed = try await client.events(calendarID: calendar.id, from: start.addingTimeInterval(-60), to: start.addingTimeInterval(16 * 60))
            guard listed.contains(where: { $0.id == created.id }) else { throw ThubanError.store("The event is missing from events.list.") }
            print("live-check: read back OK (get + list)")
        } catch {
            failure = error
        }
        // Always delete, even when the checks failed.
        try await client.deleteEvent(eventID: created.id, calendarID: calendar.id, sendUpdates: .none)
        print("live-check: deleted \(created.id)")
        do {
            let after = try await client.event(calendarID: calendar.id, eventID: created.id)
            guard after.isCancelled else { throw ThubanError.store("The test event still exists after delete.") }
        } catch let error as ThubanError where error.isNotFound {
            // Gone.
        }
        print("live-check: confirmed deleted")
        if let failure { throw failure }
    }
}
