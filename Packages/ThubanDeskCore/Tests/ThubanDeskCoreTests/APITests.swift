import XCTest
@testable import ThubanDeskCore

final class CalendarAPITests: XCTestCase {
    func testRequestsAreBuiltWithoutPerformingThem() throws {
        let list = CalendarEndpoints.events(calendarID: "en.usa#holiday@group.v.calendar.google.com", from: ny(2026, 9, 20), to: ny(2026, 9, 27), query: "gym")
        XCTAssertEqual(list.method, "GET")
        XCTAssertEqual(list.kind, .read)
        XCTAssertEqual(list.path, "/calendar/v3/calendars/en.usa%23holiday%40group.v.calendar.google.com/events")
        XCTAssertEqual(list.queryValue("timeMin"), "2026-09-20T04:00:00Z")
        XCTAssertEqual(list.queryValue("singleEvents"), "true")
        XCTAssertEqual(list.queryValue("orderBy"), "startTime")
        XCTAssertEqual(list.queryValue("q"), "gym")
        XCTAssertNil(CalendarEndpoints.events(calendarID: "c", from: Date(), to: Date(), singleEvents: false).queryValue("orderBy"))

        let patch = CalendarEndpoints.patch(EventPatch(summary: "New"), eventID: "e1", calendarID: "c", sendUpdates: .all)
        XCTAssertEqual(patch.method, "PATCH")
        XCTAssertEqual(patch.kind, .write)
        XCTAssertEqual(patch.queryValue("sendUpdates"), "all")
        XCTAssertEqual(String(decoding: patch.body!, as: UTF8.self), #"{"summary":"New"}"#)
        XCTAssertEqual(CalendarEndpoints.delete(eventID: "e1", calendarID: "c").method, "DELETE")
    }

    func testDecodingEventsPage() throws {
        let page = try GoogleJSON.decoder.decode(EventsPage.self, from: fixtureData("events_page.json"))
        let events = page.pageItems
        XCTAssertEqual(events.count, 3)
        let allDay = events[0]
        XCTAssertTrue(allDay.isAllDay)
        XCTAssertEqual(allDay.start.date, CivilDate(year: 2026, month: 9, day: 25))
        XCTAssertEqual(allDay.end.date, CivilDate(year: 2026, month: 9, day: 26))
        let timed = events[1]
        XCTAssertEqual(timed.start.dateTime, ny(2026, 9, 24, 19))
        XCTAssertEqual(timed.start.timeZone, "America/New_York")
        XCTAssertEqual(timed.seriesID, "series1")
        XCTAssertTrue(timed.needsResponse)
        XCTAssertEqual(timed.attendees?[2].responseStatus, .needsAction, "unknown statuses decode as needsAction")
        XCTAssertEqual(timed.videoLink, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(timed.reminders?.overrides?.first?.minutes, 10)
        XCTAssertTrue(events[2].isCancelled)
    }

    func testEventDateTimeEncodingSwitchesKinds() throws {
        let timed = try GoogleJSON.encoder.encode(EventDateTime.timed(ny(2026, 9, 24, 19), timeZone: "America/New_York"))
        XCTAssertEqual(String(decoding: timed, as: UTF8.self), #"{"date":null,"dateTime":"2026-09-24T19:00:00-04:00","timeZone":"America\/New_York"}"#)
        let allDay = try GoogleJSON.encoder.encode(EventDateTime.allDay(CivilDate(year: 2026, month: 9, day: 25)))
        XCTAssertEqual(String(decoding: allDay, as: UTF8.self), #"{"date":"2026-09-25","dateTime":null}"#)
        // A new event omits the empty id.
        let event = CalendarEvent(summary: "X", start: .allDay(CivilDate(year: 2026, month: 1, day: 1)), end: .allDay(CivilDate(year: 2026, month: 1, day: 2)))
        XCTAssertFalse(String(decoding: try GoogleJSON.encoder.encode(event), as: UTF8.self).contains("\"id\""))
    }

    func testRSVPPatchChangesOnlyOwnResponse() throws {
        let page = try GoogleJSON.decoder.decode(EventsPage.self, from: fixtureData("events_page.json"))
        let patch = try XCTUnwrap(CalendarEndpoints.rsvpPatch(for: page.pageItems[1], status: .tentative, selfEmail: "amorgan@example.edu"))
        XCTAssertEqual(patch.attendees?.map(\.responseStatus), [.accepted, .tentative, .needsAction])
        XCTAssertNil(CalendarEndpoints.rsvpPatch(for: page.pageItems[0], status: .accepted, selfEmail: "x@y.z"))
    }

    func testEventPatchDiff() {
        var old = CalendarEvent(id: "e", summary: "A", start: .allDay(CivilDate(year: 2026, month: 1, day: 1)), end: .allDay(CivilDate(year: 2026, month: 1, day: 2)))
        old.location = "Here"
        var new = old
        new.summary = "B"
        new.location = nil
        XCTAssertEqual(EventPatch.diff(from: old, to: new), EventPatch(summary: "B", location: ""))
        XCTAssertTrue(EventPatch.diff(from: old, to: old).isEmpty)
    }

    func testFixtureCalendarsRSVPAndFindOrCreate() async throws {
        let backend = FixtureGoogle(world: SampleData.world(now: designNow, zone: newYork))
        let client = fixtureClient(backend, account: SampleData.primaryEmail)
        let calendars = try await client.calendarList()
        XCTAssertEqual(calendars.map(\.displayName), ["Personal", "Gym", "Recruiting", "US Holidays"])
        XCTAssertEqual(calendars.map(\.defaultTint), [.neg, .pos, .grey, .pos])

        let week = try await client.events(calendarID: "recruiting@fixture", from: ny(2026, 9, 20), to: ny(2026, 9, 27))
        let interview = try XCTUnwrap(week.first { $0.title == "Interview · Crescent Labs" })
        XCTAssertTrue(interview.needsResponse)
        let answered = try await client.rsvp(.accepted, to: interview, calendarID: "recruiting@fixture", selfEmail: SampleData.primaryEmail)
        XCTAssertEqual(answered.selfResponse, .accepted)

        let first = try await client.findOrCreateCalendar(named: "Thuban")
        let second = try await client.findOrCreateCalendar(named: "thuban")
        XCTAssertEqual(first, second)
        let names = try await client.calendarList().map(\.displayName)
        XCTAssertEqual(names.filter { $0 == "Thuban" }.count, 1)
    }

    func testFixtureWeekMatchesTheDesign() async throws {
        let backend = FixtureGoogle(world: SampleData.world(now: designNow, zone: newYork))
        let school = fixtureClient(backend, account: SampleData.schoolEmail)
        let classes = try await school.events(calendarID: SampleData.schoolEmail, from: ny(2026, 9, 24), to: ny(2026, 9, 25))
        XCTAssertEqual(classes.map(\.title), ["ITSC 2214 · Data Structures", "STAT 2122 · Statistics"])
        let study = try await school.events(calendarID: "study@fixture", from: ny(2026, 9, 24), to: ny(2026, 9, 25))
        XCTAssertEqual(study.first?.title, "Study group · MATH 2210")
        XCTAssertEqual(study.first?.attendees?.count, 4)
        // The modified STAT instance on Sep 15 is the exam.
        let exam = try await school.events(calendarID: SampleData.schoolEmail, from: ny(2026, 9, 15), to: ny(2026, 9, 16))
        XCTAssertEqual(exam.map(\.title), ["ITSC 2214 · Data Structures", "Exam 1 · STAT 2122"])
        // Masters are available for edits.
        let masters = try await school.events(calendarID: SampleData.schoolEmail, from: ny(2026, 9, 1), to: ny(2026, 10, 1), singleEvents: false)
        XCTAssertTrue(masters.contains { $0.id == "math2210" && $0.isRecurringMaster })
        // Deleting one instance hides only it.
        let tuesday = try await school.events(calendarID: SampleData.schoolEmail, from: ny(2026, 9, 22), to: ny(2026, 9, 23))
        try await school.deleteEvent(eventID: tuesday[0].id, calendarID: SampleData.schoolEmail)
        let afterDelete = try await school.events(calendarID: SampleData.schoolEmail, from: ny(2026, 9, 22), to: ny(2026, 9, 23))
        XCTAssertEqual(afterDelete.count, tuesday.count - 1)
    }
}

final class GmailAPITests: XCTestCase {
    func testThreadRequests() {
        let list = GmailEndpoints.threads(labelIDs: ["INBOX", "Label_1"], query: "from:maya", maxResults: 25)
        XCTAssertEqual(list.url.query?.components(separatedBy: "&").filter { $0.hasPrefix("labelIds=") }, ["labelIds=INBOX", "labelIds=Label_1"])
        XCTAssertEqual(list.queryValue("q"), "from:maya")
        let metadata = GmailEndpoints.thread("t1", format: .metadata)
        XCTAssertTrue(metadata.url.absoluteString.contains("metadataHeaders=List-Unsubscribe"))
        XCTAssertEqual(MailAction.archive.request(threadID: "t1").path, "/gmail/v1/users/me/threads/t1/modify")
        XCTAssertEqual(String(decoding: MailAction.archive.request(threadID: "t1").body!, as: UTF8.self), #"{"addLabelIds":[],"removeLabelIds":["INBOX"]}"#)
        XCTAssertEqual(MailAction.trash.request(threadID: "t1").path, "/gmail/v1/users/me/threads/t1/trash")
        XCTAssertEqual(MailAction.spam.apply(to: ["INBOX", "UNREAD"]), ["SPAM", "UNREAD"])
        let send = GmailEndpoints.send(OutgoingMessage(from: EmailAddress("a@x.org"), to: [EmailAddress("b@x.org")], text: "hi", threadID: "t9"))
        XCTAssertEqual(send.kind, .send)
        XCTAssertTrue(String(decoding: send.body!, as: UTF8.self).contains("\"threadId\":\"t9\""))
        XCTAssertEqual(GmailEndpoints.sendDraft("d1").kind, .send)
        XCTAssertEqual(GmailEndpoints.createDraft(OutgoingMessage(from: EmailAddress("a@x.org"))).kind, .write)
    }

    func testFolderListings() {
        let labels = [GmailLabel(id: "Label_math", name: "MATH 2210")]
        XCTAssertEqual(MailFolder.inbox.listing(labels: [])?.labelIDs, ["INBOX"])
        XCTAssertEqual(MailFolder.trash.listing(labels: [])?.includeSpamTrash, true)
        XCTAssertEqual(MailFolder.archive.listing(labels: [], search: "maya")?.query, "-in:inbox -in:spam -in:trash -in:drafts -in:sent -in:chats maya")
        XCTAssertEqual(MailFolder.label("math 2210").listing(labels: labels)?.labelIDs, ["Label_math"])
        XCTAssertNil(MailFolder.label("Housing").listing(labels: labels))
        XCTAssertNil(MailFolder.pinned.listing(labels: labels))
        XCTAssertEqual(MailFolder(storageKey: MailFolder.label("A b").storageKey), .label("A b"))
        XCTAssertEqual(MailFolder(storageKey: "starred"), .starred)
        XCTAssertEqual(MailScope().title, "All inboxes")
    }

    func testAllInboxesMergesAccountsByDateAndLabelsByName() async throws {
        let backend = FixtureGoogle(world: SampleData.world(now: designNow, zone: newYork))
        let gmail = fixtureClient(backend, account: SampleData.primaryEmail)
        let school = fixtureClient(backend, account: SampleData.schoolEmail)
        let a = try await gmail.threadSummaries(labelIDs: ["INBOX"])
        let b = try await school.threadSummaries(labelIDs: ["INBOX"])
        let merged = MailMerge.merge([a, b])
        XCTAssertEqual(merged.prefix(4).map(\.subject), ["Interview confirmed: Friday 3:00 PM", "Tonight: bring your Q3 attempts",
                                                        "MATH 2210 — Homework 4 now due Friday", "Re: Tangent plane question from office hours"])
        XCTAssertEqual(merged.count, 10)
        XCTAssertEqual(merged.filter(\.isUnread).count, 4)
        XCTAssertEqual(merged.first?.accountDomain, "example.com")
        XCTAssertEqual(merged.first?.messageCount, 3, "drafts do not count")
        XCTAssertEqual(merged.first?.from?.name, "Priya Shah")

        let labelSets = [SampleData.primaryEmail: try await gmail.labels(), SampleData.schoolEmail: try await school.labels()]
        let labels = MailMerge.mergeLabels(labelSets, accountOrder: [SampleData.primaryEmail, SampleData.schoolEmail])
        XCTAssertEqual(labels.map(\.name), ["Housing", "MATH 2210", "Receipts", "Recruiting"])
        let recruiting = try XCTUnwrap(labels.last)
        XCTAssertEqual(recruiting.ids.count, 2)
        XCTAssertEqual(recruiting.unread, 1)
    }

    func testMailboxActionsDraftsAndRefusedSends() async throws {
        let backend = FixtureGoogle(world: SampleData.world(now: designNow, zone: newYork))
        let gmail = fixtureClient(backend, account: SampleData.primaryEmail, gate: .open)
        try await gmail.perform(.archive, threadID: "t8")
        try await gmail.perform(.markRead, threadID: "t8")
        let mom = try await gmail.thread("t8")
        XCTAssertFalse(mom.labelIDs.contains("INBOX"))
        XCTAssertFalse(mom.isUnread)
        try await gmail.perform(.trash, threadID: "t6")
        let trash = try await gmail.threadSummaries(labelIDs: ["TRASH"], includeSpamTrash: true)
        XCTAssertTrue(trash.contains { $0.id == "t6" })
        let inbox = try await gmail.threadSummaries(labelIDs: ["INBOX"])
        XCTAssertFalse(inbox.contains { $0.id == "t6" })

        let full = try await gmail.thread("t1")
        let reply = MIMEBuilder.reply(to: try XCTUnwrap(full.messages.last { !$0.isDraft }), from: EmailAddress(SampleData.primaryEmail),
                                      replyAll: false, html: "<p>Yes</p>", text: "Yes")
        let draft = try await gmail.saveDraft(reply)
        var updated = reply
        updated.draftID = draft.id
        updated.text = "Yes, confirmed."
        _ = try await gmail.saveDraft(updated)
        let drafts = try await gmail.drafts()
        XCTAssertTrue(drafts.contains { $0.id == draft.id })

        // Even with an open gate, the fixture backend refuses to send.
        do {
            try await gmail.send(updated)
            XCTFail("fixture must refuse sends")
        } catch let error as ThubanError {
            if case .http(let status, _, _) = error { XCTAssertEqual(status, 403) } else { XCTFail("\(error)") }
        }
        try await gmail.deleteDraft(draft.id)

        let filter = try await gmail.createFilter(.fromSender("maya.chen@students.example.edu", addLabelID: "Label_recruiting", skipInbox: true))
        XCTAssertEqual(filter.action?.removeLabelIds, ["INBOX"])
        let filters = try await gmail.filters()
        XCTAssertEqual(filters.count, 2)
        XCTAssertFalse(backend.log.contains { !$0.contains("googleapis.com") }, "only Google API paths were served")
    }

    func testFixtureRefusesUnknownHostsAndTokens() async throws {
        let backend = FixtureGoogle(world: SampleData.world(now: designNow, zone: newYork))
        let session = backend.makeSession()
        var request = URLRequest(url: URL(string: "https://example.com/")!)
        request.setValue("Bearer fixture-token-\(SampleData.primaryEmail)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 403)
        let (_, unauthorized) = try await session.data(from: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/labels")!)
        XCTAssertEqual((unauthorized as? HTTPURLResponse)?.statusCode, 401)
    }
}

final class NeedsReplyTests: XCTestCase {
    func testOnlyPeopleAskingYouDirectlyQualify() async throws {
        let backend = FixtureGoogle(world: SampleData.world(now: designNow, zone: newYork))
        let own: Set<String> = [SampleData.primaryEmail, SampleData.schoolEmail]
        var needing: [String] = []
        for account in [SampleData.primaryEmail, SampleData.schoolEmail] {
            let client = fixtureClient(backend, account: account)
            for ref in try await client.threadRefs(labelIDs: ["INBOX"]) {
                let thread = try await client.thread(ref.id)
                let verdict = NeedsReply.classify(thread, ownAddresses: own, now: designNow)
                if verdict.needsReply { needing.append(thread.messages.last { !$0.isDraft }?.from?.displayName ?? "") }
            }
        }
        XCTAssertEqual(Set(needing), ["Priya Shah", "Maya Chen", "Mom"])
    }

    func testReasons() {
        let me = EmailAddress("me@x.org")
        let friend = EmailAddress("friend@x.org", name: "Friend")
        func thread(_ messages: [MailMessage], labels: [String] = []) -> MailThread { MailThread(account: "me@x.org", id: "t", messages: messages) }
        func message(from: EmailAddress, to: [EmailAddress] = [EmailAddress("me@x.org")], text: String, daysAgo: Double = 1, labels: [String] = ["INBOX"],
                     headers: [String: String] = [:]) -> MailMessage {
            MailMessage(id: UUID().uuidString, threadID: "t", labelIDs: labels, date: designNow.addingTimeInterval(-daysAgo * 86_400), from: from, to: to,
                        text: text, extraHeaders: headers)
        }
        XCTAssertTrue(NeedsReply.classify(thread([message(from: friend, text: "Are you free Friday?")]), ownAddresses: [], now: designNow).needsReply)
        XCTAssertEqual(NeedsReply.classify(thread([message(from: friend, text: "Are you free?", daysAgo: 8)]), ownAddresses: [], now: designNow).reason, "older than 7 days")
        XCTAssertEqual(NeedsReply.classify(thread([message(from: friend, text: "Are you free?"), message(from: me, to: [friend], text: "Yes", daysAgo: 0.5, labels: ["SENT"])]),
                                           ownAddresses: [], now: designNow).reason, "you wrote last")
        XCTAssertEqual(NeedsReply.classify(thread([message(from: friend, text: "FYI, the report is attached.")]), ownAddresses: [], now: designNow).reason, "does not ask anything")
        XCTAssertTrue(NeedsReply.classify(thread([message(from: friend, text: "Please let me know by Monday.")]), ownAddresses: [], now: designNow).needsReply)
        XCTAssertEqual(NeedsReply.classify(thread([message(from: EmailAddress("no-reply@shop.com"), text: "Can you rate us?")]), ownAddresses: [], now: designNow).reason,
                       "automated or bulk sender")
        XCTAssertEqual(NeedsReply.classify(thread([message(from: friend, text: "Can you come?", headers: ["list-id": "<x>"])]), ownAddresses: [], now: designNow).reason,
                       "automated or bulk sender")
        XCTAssertEqual(NeedsReply.classify(thread([message(from: friend, to: [EmailAddress("team@x.org")], text: "Can you come?")]), ownAddresses: [], now: designNow).reason,
                       "not addressed to you")
        XCTAssertEqual(NeedsReply.classify(thread([message(from: friend, text: "Can you?", labels: ["INBOX", "CATEGORY_PROMOTIONS"])]), ownAddresses: [], now: designNow).reason,
                       "category, spam or trash")
        let quoted = message(from: friend, text: "Thanks, that works.\n\nOn Mon, Sep 21 at 1:18 PM, Me wrote:\n> Can you meet?")
        XCTAssertFalse(NeedsReply.classify(thread([quoted]), ownAddresses: [], now: designNow).needsReply, "questions in quoted text do not count")
        XCTAssertEqual(NeedsReply.question(in: "Hi. Still on for 7? Bring markers."), "Still on for 7?")
    }
}

final class TodayAgendaTests: XCTestCase {
    func item(_ id: String, _ h: Int, _ m: Int, _ h2: Int, _ m2: Int, day: Int = 24) -> AgendaEvent {
        AgendaEvent(calendar: CalendarKey(account: "a", calendarID: "c"),
                    event: CalendarEvent(id: id, summary: id, start: .timed(ny(2026, 9, day, h, m), timeZone: nil), end: .timed(ny(2026, 9, day, h2, m2), timeZone: nil)))
    }

    func testDesignDay() {
        let events = [item("gym", 7, 0, 8, 0), item("itsc", 11, 30, 12, 45), item("stat", 14, 30, 15, 45), item("study", 19, 0, 20, 30), item("tomorrow", 10, 10, 11, 0, day: 25),
                      AgendaEvent(calendar: CalendarKey(account: "a", calendarID: "c"),
                                  event: CalendarEvent(id: "hw", summary: "HW", start: .allDay(CivilDate(year: 2026, month: 9, day: 24)), end: .allDay(CivilDate(year: 2026, month: 9, day: 25))))]
        let entries = TodayAgenda.build(events: events, day: CivilDate(year: 2026, month: 9, day: 24), now: designNow, zone: newYork)
        XCTAssertEqual(entries.count, 6)
        guard case .allDay(let hw) = entries[0] else { return XCTFail() }
        XCTAssertEqual(hw.event.id, "hw")
        guard case .event(_, .done) = entries[1], case .event(_, .done) = entries[2] else { return XCTFail("\(entries)") }
        guard case .event(let now, .now(let remaining)) = entries[3] else { return XCTFail("\(entries)") }
        XCTAssertEqual(now.event.id, "stat")
        XCTAssertEqual(TodayAgenda.durationText(remaining), "65 min")
        guard case .free(let gap) = entries[4] else { return XCTFail("\(entries)") }
        XCTAssertEqual(gap.start, ny(2026, 9, 24, 15, 45))
        XCTAssertEqual(TodayAgenda.durationText(gap.duration), "3 h 15 m")
        guard case .event(_, .upcoming(let startsIn)) = entries[5] else { return XCTFail() }
        XCTAssertEqual(TodayAgenda.durationText(startsIn), "4 h 20 m")
    }

    func testNowMarkerBetweenEvents() {
        let entries = TodayAgenda.build(events: [item("a", 9, 0, 10, 0), item("b", 13, 0, 14, 0)], day: CivilDate(year: 2026, month: 9, day: 24),
                                        now: ny(2026, 9, 24, 11), zone: newYork)
        XCTAssertEqual(entries.map(\.id), ["event|a|c|a", "now", "free|\(ny(2026, 9, 24, 11).timeIntervalSince1970)", "event|a|c|b"])
    }

    func testPendingInvitations() throws {
        let page = try GoogleJSON.decoder.decode(EventsPage.self, from: fixtureData("events_page.json"))
        let items = page.pageItems.map { AgendaEvent(calendar: CalendarKey(account: "a", calendarID: "c"), event: $0) }
        XCTAssertEqual(TodayAgenda.pendingInvitations(items, after: ny(2026, 9, 24, 12), zone: newYork).map(\.event.id), ["timed1"])
        XCTAssertTrue(TodayAgenda.pendingInvitations(items, after: ny(2026, 9, 25), zone: newYork).isEmpty)
    }
}

final class StorageTests: XCTestCase {
    var home: URL!

    override func setUp() {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("thuban-desk-tests-\(UUID().uuidString)")
        AppPaths.overrideHome = home
    }

    override func tearDown() {
        AppPaths.overrideHome = nil
        try? FileManager.default.removeItem(at: home)
    }

    func testCredentialsFileIsPrivate() throws {
        try CredentialStore.save(signedInFile())
        let attributes = try FileManager.default.attributesOfItem(atPath: AppPaths.credentialsFile.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try CredentialStore.load().accounts.first?.email, "me@example.com")
        XCTAssertTrue(AppPaths.credentialsFile.path.hasPrefix(home.path))
    }

    func testSettingsTolerateMissingAndUnknownValues() throws {
        let data = Data(#"{"lastArea":"nonsense","mailListWidth":500,"hiddenCalendars":["a@x.org|cal1"],"pins":{"a@x.org":["t1"]}}"#.utf8)
        let settings = try JSONFile.decoder.decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.lastArea, .calendar)
        XCTAssertEqual(settings.mailListWidth, 500)
        XCTAssertTrue(settings.isHidden(CalendarKey(account: "A@x.org", calendarID: "cal1")))
        XCTAssertTrue(settings.isPinned(ThreadKey(account: "a@x.org", threadID: "t1")))
        var copy = settings
        copy.setPinned(false, ThreadKey(account: "a@x.org", threadID: "t1"))
        XCTAssertNil(copy.pins["a@x.org"])
        let roundTrip = try JSONFile.decoder.decode(AppSettings.self, from: JSONFile.encoder.encode(settings))
        XCTAssertEqual(roundTrip, settings)
    }

    func testDiskCache() async throws {
        let cache = DiskCache(directory: home.appendingPathComponent("cache"))
        await cache.store(Data("x".utf8), for: "events|a|2026-09")
        let entry = await cache.entry(for: "events|a|2026-09")
        XCTAssertEqual(entry?.data, Data("x".utf8))
        let fresh = DiskCache(directory: home.appendingPathComponent("cache"))
        let reread = await fresh.entry(for: "events|a|2026-09")
        XCTAssertEqual(reread?.data, Data("x".utf8), "survives a new instance (disk)")
        await fresh.clear()
        let cleared = await fresh.entry(for: "events|a|2026-09")
        XCTAssertNil(cleared)
    }

    func testFixtureSeederWritesASignedInHome() throws {
        let world = SampleData.world(now: designNow, zone: newYork)
        try FixtureSeeder.seed(world: world)
        let credentials = try CredentialStore.load()
        XCTAssertEqual(credentials.primary?.email, SampleData.primaryEmail)
        XCTAssertEqual(credentials.accounts.count, 2)
        let settings = SettingsStore.load()
        XCTAssertTrue(settings.isHidden(CalendarKey(account: SampleData.primaryEmail, calendarID: SampleData.holidaysCalendarID)))
    }
}
