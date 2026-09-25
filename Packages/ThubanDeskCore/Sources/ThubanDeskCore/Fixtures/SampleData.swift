import Foundation

/// Everything the fake Google serves: two accounts (as in the design), their calendars with recurring classes and
/// invitations, and their mail. Dates are laid out around `now`'s week so every screen has content on any day;
/// with `THUBAN_DESK_NOW=2026-09-24T14:40:00-04:00` it matches the artboards exactly.
public struct FixtureWorld: Sendable {
    public var now: Date
    public var zone: TimeZone
    public var client: GoogleClientConfig
    public var accounts: [GoogleAccount]
    /// account → calendars.
    public var calendars: [String: [CalendarListEntry]]
    /// account → calendar id → stored events (masters, single events and modified / cancelled instances).
    public var events: [String: [String: [CalendarEvent]]]
    public var labels: [String: [GmailLabel]]
    /// account → threads with full payloads.
    public var threads: [String: [GmailThread]]
    public var filters: [String: [GmailFilter]]
    public var sendAs: [String: [GmailSendAs]]

    public var accountIDs: [String] { accounts.sorted { $0.linkedAt < $1.linkedAt }.map(\.id) }
}

public enum SampleData {
    public static let primaryEmail = "alex.morgan@example.com"
    public static let schoolEmail = "amorgan@example.edu"
    public static let fixtureClientID = "000000000000-fixture.apps.googleusercontent.com"
    public static let holidaysCalendarID = "en.usa#holiday@group.v.calendar.google.com"

    public static func accessToken(for email: String) -> String { "fixture-token-" + email.lowercased() }
    public static func refreshToken(for email: String) -> String { "fixture-refresh-" + email.lowercased() }

    public static func world(now: Date = DeskClock.now(), zone: TimeZone = TimeZone(identifier: "America/New_York")!) -> FixtureWorld {
        let builder = Builder(now: now, zone: zone)
        return builder.build()
    }

    struct Builder {
        let now: Date
        let zone: TimeZone
        let calendar: Calendar
        /// Sunday of now's week.
        let week: CivilDate
        let today: CivilDate

        init(now: Date, zone: TimeZone) {
            self.now = now
            self.zone = zone
            calendar = Calendar.gregorian(zone)
            today = CivilDate(now, in: zone)
            week = today.adding(days: -(today.weekday.calendarWeekday - 1))
        }

        func at(_ day: CivilDate, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)) ?? now
        }

        func timed(_ day: CivilDate, _ h: Int, _ m: Int, _ h2: Int, _ m2: Int) -> (EventDateTime, EventDateTime) {
            (.timed(at(day, h, m), timeZone: zone.identifier), .timed(at(day, h2, m2), timeZone: zone.identifier))
        }

        func untilEndOf(_ day: CivilDate) -> RRuleUntil { .dateTime(day.adding(days: 1).startDate(in: zone).addingTimeInterval(-1)) }

        func weekly(_ days: [Weekday], until: CivilDate? = nil) -> [String] {
            [RRule(frequency: .weekly, byDay: days.map { RRule.Day($0) }, until: until.map(untilEndOf)).line]
        }

        func event(_ id: String, _ summary: String, _ times: (EventDateTime, EventDateTime), location: String? = nil, description: String? = nil,
                   recurrence: [String]? = nil, attendees: [EventAttendee]? = nil, organizer: EventPerson? = nil) -> CalendarEvent {
            var event = CalendarEvent(id: id, summary: summary, start: times.0, end: times.1, description: description, location: location,
                                      recurrence: recurrence, attendees: attendees)
            event.iCalUID = "\(id)@fixture.thuban"
            event.organizer = organizer ?? EventPerson(email: nil, displayName: nil, isSelf: true)
            event.created = now.addingTimeInterval(-60 * 86_400)
            event.updated = now.addingTimeInterval(-86_400)
            event.eventType = "default"
            event.reminders = EventReminders(useDefault: true)
            return event
        }

        func allDay(_ id: String, _ summary: String, _ day: CivilDate, recurrence: [String]? = nil) -> CalendarEvent {
            event(id, summary, (.allDay(day), .allDay(day.adding(days: 1))), recurrence: recurrence)
        }

        // MARK: Build

        func build() -> FixtureWorld {
            let primary = GoogleAccount(email: SampleData.primaryEmail, displayName: "Alex Morgan",
                                        linkedAt: RFC3339.date(from: "2024-08-18T15:00:00Z")!, refreshToken: SampleData.refreshToken(for: SampleData.primaryEmail),
                                        accessToken: SampleData.accessToken(for: SampleData.primaryEmail), accessTokenExpiry: Date.distantFuture,
                                        lastSynced: now.addingTimeInterval(-120))
            let school = GoogleAccount(email: SampleData.schoolEmail, displayName: "Alex Morgan",
                                       linkedAt: RFC3339.date(from: "2026-08-24T15:00:00Z")!, refreshToken: SampleData.refreshToken(for: SampleData.schoolEmail),
                                       accessToken: SampleData.accessToken(for: SampleData.schoolEmail), accessTokenExpiry: Date.distantFuture,
                                       lastSynced: now.addingTimeInterval(-120))
            let tz = zone.identifier
            let calendars: [String: [CalendarListEntry]] = [
                primary.id: [
                    CalendarListEntry(id: SampleData.primaryEmail, summary: "Personal", timeZone: tz, backgroundColor: "#e67c73", primary: true),
                    CalendarListEntry(id: "gym@fixture", summary: "Gym", timeZone: tz, backgroundColor: "#33b679"),
                    CalendarListEntry(id: "recruiting@fixture", summary: "Recruiting", timeZone: tz, backgroundColor: "#a79b8e"),
                    CalendarListEntry(id: SampleData.holidaysCalendarID, summary: "US Holidays", timeZone: tz, backgroundColor: "#0b8043", accessRole: "reader"),
                ],
                school.id: [
                    CalendarListEntry(id: SampleData.schoolEmail, summary: "Classes", timeZone: tz, backgroundColor: "#f6bf26", primary: true),
                    CalendarListEntry(id: "study@fixture", summary: "Study", timeZone: tz, backgroundColor: "#039be5"),
                ],
            ]
            return FixtureWorld(
                now: now, zone: zone,
                client: GoogleClientConfig(clientID: SampleData.fixtureClientID, clientSecret: "fixture-secret"),
                accounts: [primary, school],
                calendars: calendars,
                events: [primary.id: primaryEvents(), school.id: schoolEvents()],
                labels: labels(),
                threads: threads(),
                filters: [
                    primary.id: [GmailFilter(id: "f1", criteria: .init(from: "statements@carolinacredit.example.org"), action: .init(addLabelIds: ["Label_receipts"]))],
                    school.id: [GmailFilter(id: "f2", criteria: .init(from: "notifications@instructure.com"), action: .init(addLabelIds: nil, removeLabelIds: nil))],
                ],
                sendAs: [
                    primary.id: [GmailSendAs(sendAsEmail: SampleData.primaryEmail, displayName: "Alex Morgan",
                                             signature: "Alex Morgan<br>UNC Charlotte · B.S. Computer Science, 2028", isDefault: true, isPrimary: true)],
                    school.id: [GmailSendAs(sendAsEmail: SampleData.schoolEmail, displayName: "Alex Morgan",
                                            signature: "Alex Morgan<br>UNC Charlotte · B.S. Computer Science, 2028", isDefault: true, isPrimary: true)],
                ])
        }

        // MARK: Calendar

        func primaryEvents() -> [String: [CalendarEvent]] {
            let w = week
            let me = SampleData.primaryEmail
            var personal: [CalendarEvent] = [
                event("dinner1", "Dinner with Mom", timed(w, 17, 0, 19, 0), location: "Matthews"),
                event("dinner0", "Dinner with Mom", timed(w.adding(days: -14), 17, 0, 19, 0), location: "Matthews"),
                event("shift", "Shift · Atkins front desk", timed(w.adding(days: -20), 17, 0, 20, 0), location: "Atkins Library", recurrence: weekly([.monday])),
                event("brunch", "Brunch with Maya", timed(w.adding(days: -7), 11, 0, 12, 30), location: "Amélie’s French Bakery"),
                event("laundry", "Laundry + meal prep", timed(w.adding(days: 7), 16, 0, 17, 30)),
                allDay("bday", "Mom’s birthday", w.adding(days: 6), recurrence: [RRule(frequency: .yearly).line]),
            ]
            personal[0].description = nil
            let gym = [
                event("gym", "Gym · UREC", timed(w.adding(days: -26), 7, 0, 8, 0), location: "UREC weight room",
                      recurrence: weekly([.tuesday, .thursday, .saturday])),
            ]
            var interview = event("interview", "Interview · Crescent Labs", timed(w.adding(days: 5), 15, 0, 15, 45), location: "Zoom",
                                  description: "Software engineering intern, summer 2027. 45 minutes: one coding question, then Q&amp;A.",
                                  attendees: [
                                    EventAttendee(email: "priya.shah@crescentlabs-hq.example", displayName: "Priya Shah", organizer: true, responseStatus: .accepted),
                                    EventAttendee(email: "marcus.lee@crescentlabs.example.org", displayName: "Marcus Lee", responseStatus: .accepted),
                                    EventAttendee(email: me, displayName: "Alex Morgan", isSelf: true, responseStatus: .needsAction),
                                  ],
                                  organizer: EventPerson(email: "priya.shah@crescentlabs-hq.example", displayName: "Priya Shah"))
            interview.conferenceData = ConferenceData(entryPoints: [ConferenceEntryPoint(entryPointType: "video", uri: "https://zoom.us/j/5550142000", label: "zoom.us/j/5550142000")],
                                                      conferenceSolution: .init(name: "Zoom Meeting"))
            let recruiting = [
                event("phonescreen", "Phone screen · Piedmont Energy", timed(w.adding(days: 2), 16, 30, 17, 0), location: "Phone · (704) 555-0142",
                      description: "Data analyst intern, spring 2027. Recruiter: Dana Whitfield."),
                interview,
            ]
            let holidays = [allDay("columbus", "Columbus Day", CivilDate(year: w.year, month: 10, day: 12))]
            return [me: personal, "gym@fixture": gym, "recruiting@fixture": recruiting, SampleData.holidaysCalendarID: holidays]
        }

        func schoolEvents() -> [String: [CalendarEvent]] {
            let w = week
            let me = SampleData.schoolEmail
            let semesterEnd = w.adding(days: 81)
            let mwf: [Weekday] = [.monday, .wednesday, .friday]
            let tr: [Weekday] = [.tuesday, .thursday]
            var classes: [CalendarEvent] = [
                event("math2210", "MATH 2210 · Multivariable Calc", timed(w.adding(days: -27), 10, 10, 11, 0), location: "Fretwell 121", recurrence: weekly(mwf, until: semesterEnd)),
                event("phys2102", "PHYS 2102 · Physics II", timed(w.adding(days: -27), 13, 25, 14, 15), location: "Grigg 132", recurrence: weekly(mwf, until: semesterEnd)),
                event("itsc2214", "ITSC 2214 · Data Structures", timed(w.adding(days: -26), 11, 30, 12, 45), location: "Woodward 106", recurrence: weekly(tr, until: semesterEnd)),
                event("stat2122", "STAT 2122 · Statistics", timed(w.adding(days: -26), 14, 30, 15, 45), location: "Friday Bldg 142", recurrence: weekly(tr, until: semesterEnd)),
                allDay("adddrop", "Last day to add/drop", w.adding(days: -18)),
                allDay("hw2", "Homework 2 due · MATH 2210", w.adding(days: -9)),
                allDay("hw3", "Homework 3 due · MATH 2210", w.adding(days: -2)),
                allDay("careerclose", "Career Fair sign-up closes", w.adding(days: 3)),
                allDay("hw4", "Homework 4 due · MATH 2210", w.adding(days: 5)),
                allDay("fair", "Fall Career Fair", w.adding(days: 10)),
                event("exam1math", "Exam 1 · MATH 2210", timed(w.adding(days: 11), 10, 10, 11, 0), location: "Fretwell 121"),
            ]
            // Exam 1 replaces one STAT lecture (a modified instance of the series).
            let examDay = w.adding(days: -5)
            let examStart = at(examDay, 14, 30)
            var exam = event("stat2122_" + RRule.utcStamp(examStart), "Exam 1 · STAT 2122", timed(examDay, 14, 30, 15, 45), location: "Friday Bldg 142")
            exam.recurringEventId = "stat2122"
            exam.originalStartTime = .timed(examStart, timeZone: zone.identifier)
            classes.append(exam)
            let study: [CalendarEvent] = [
                event("officehours", "TA office hours · MATH 2210", timed(w.adding(days: -18), 15, 30, 16, 30), location: "Fretwell 330",
                      description: "Jordan Blake. Ask about the tangent-plane sign error from Homework 3.", recurrence: weekly([.wednesday], until: semesterEnd.adding(days: -1))),
                event("studygroup", "Study group · MATH 2210", timed(w.adding(days: -24), 19, 0, 20, 30), location: "Atkins Library 244",
                      description: "Bring your attempts at <b>Homework 4, Q3 and Q5</b>. We’ll split the whiteboard:<ul><li>Maya — partial derivatives</li><li>You — limits along paths</li></ul>Notes: <a href=\"https://docs.google.com/document/d/fixture\">MATH 2210 study notes</a><script>alert(1)</script>",
                      recurrence: weekly([.thursday], until: semesterEnd),
                      attendees: [
                        EventAttendee(email: "maya.chen@students.example.edu", displayName: "Maya Chen", organizer: true, responseStatus: .accepted),
                        EventAttendee(email: me, displayName: "Alex Morgan", isSelf: true, responseStatus: .accepted),
                        EventAttendee(email: "sokafor2@uni.example.edu", displayName: "Sam Okafor", responseStatus: .accepted),
                        EventAttendee(email: "lbrooks14@school.example.edu", displayName: "Leah Brooks", responseStatus: .needsAction),
                      ],
                      organizer: EventPerson(email: "maya.chen@students.example.edu", displayName: "Maya Chen")),
            ]
            var group = study[1]
            group.guestsCanModify = true
            return [me: classes, "study@fixture": [study[0], group]]
        }

        // MARK: Mail

        func labels() -> [String: [GmailLabel]] {
            let system = [GmailSystemLabel.inbox, GmailSystemLabel.sent, GmailSystemLabel.draft, GmailSystemLabel.spam, GmailSystemLabel.trash,
                          GmailSystemLabel.starred, GmailSystemLabel.unread, GmailSystemLabel.important].map { GmailLabel(id: $0, name: $0, type: "system") }
            return [
                SampleData.primaryEmail: system + [
                    GmailLabel(id: "Label_recruiting", name: "Recruiting", color: .init(textColor: "#ffffff", backgroundColor: "#999999")),
                    GmailLabel(id: "Label_receipts", name: "Receipts", color: .init(textColor: "#000000", backgroundColor: "#16a766")),
                ],
                SampleData.schoolEmail: system + [
                    GmailLabel(id: "Label_math", name: "MATH 2210", color: .init(textColor: "#000000", backgroundColor: "#fad165")),
                    GmailLabel(id: "Label_housing", name: "Housing", color: .init(textColor: "#ffffff", backgroundColor: "#4a86e8")),
                    GmailLabel(id: "Label_recruiting2", name: "Recruiting", color: .init(textColor: "#ffffff", backgroundColor: "#999999")),
                ],
            ]
        }

        struct Draft {
            var id: String
            var from: EmailAddress
            var to: [EmailAddress]
            var cc: [EmailAddress] = []
            var date: Date
            var subject: String
            var text: String
            var html: String? = nil
            var labels: [String]
            var headers: [MIMEHeader] = []
            var inReplyTo: String? = nil
        }

        func message(_ d: Draft, thread: String) -> GmailMessage {
            let outgoing = OutgoingMessage(from: d.from, to: d.to, cc: d.cc, subject: d.subject, html: d.html, text: d.text,
                                           inReplyTo: d.inReplyTo, references: d.inReplyTo.map { [$0] } ?? [], threadID: thread)
            var mime = MIMEParser.parse(MIMEBuilder.build(outgoing, date: d.date, zone: zone, boundarySeed: d.id))
            mime.headers.append(MIMEHeader(name: "Message-ID", value: "<\(d.id)@fixture.thuban>"))
            mime.headers += d.headers
            let snippet = String(HTMLSanitizer.plainText(d.html ?? d.text).replacingOccurrences(of: "\n", with: " ").prefix(140))
            return GmailMessage(id: d.id, threadId: thread, labelIds: d.labels, snippet: snippet,
                                internalDate: String(Int64(d.date.timeIntervalSince1970 * 1000)), payload: GmailMessagePart(mime: mime))
        }

        func threads() -> [String: [GmailThread]] {
            let me = EmailAddress(SampleData.primaryEmail, name: "Alex Morgan")
            let school = EmailAddress(SampleData.schoolEmail, name: "Alex Morgan")
            let priya = EmailAddress("priya.shah@crescentlabs-hq.example", name: "Priya Shah")
            let maya = EmailAddress("maya.chen@students.example.edu", name: "Maya Chen")
            let w = week
            let friday = Self.long(w.adding(days: 5))
            let todayAt = { (h: Int, m: Int) in self.at(self.today, h, m) }
            let yesterday = today.adding(days: -1)
            let inbox = GmailSystemLabel.inbox, unread = GmailSystemLabel.unread, starred = GmailSystemLabel.starred
            let bulk = [MIMEHeader(name: "List-Unsubscribe", value: "<mailto:unsubscribe@example.org>"), MIMEHeader(name: "Precedence", value: "bulk")]

            let t1 = GmailThread(id: "t1", historyId: "900", messages: [
                message(Draft(id: "t1m1", from: priya, to: [me], date: at(w.adding(days: 1), 10, 2), subject: "Interview confirmed: Friday 3:00 PM",
                              text: "Hi Alex, thanks for applying to our Summer 2027 Software Engineering Internship. We’d love to set up a 45-minute technical interview. Are you free Thursday or Friday afternoon this week?",
                              labels: ["Label_recruiting", GmailSystemLabel.categoryPersonal]), thread: "t1"),
                message(Draft(id: "t1m2", from: me, to: [priya], date: at(w.adding(days: 1), 13, 18), subject: "Re: Interview confirmed: Friday 3:00 PM",
                              text: "Hi Priya, thank you! Friday after 2:30 works best — I have class until 2:15. Looking forward to it.",
                              labels: [GmailSystemLabel.sent, "Label_recruiting"], inReplyTo: "<t1m1@fixture.thuban>"), thread: "t1"),
                message(Draft(id: "t1m3", from: priya, to: [me], date: min(todayAt(14, 14), now.addingTimeInterval(-26 * 60)), subject: "Re: Interview confirmed: Friday 3:00 PM",
                              text: "",
                              html: "<p>Great — you’re confirmed for <b>\(friday) at 3:00 PM</b> with Marcus Lee from our platform team. The calendar invite below has the Zoom link.</p><p>Expect one coding question (about 25 minutes, in the language of your choice) and time for your questions at the end.</p><p>Could you accept the invite or reply to confirm by tomorrow morning?</p><p>Best,<br>Priya Shah<br><span style=\"color:#888\">University Recruiting, Crescent Labs</span></p><img src=\"https://tracker.example.com/open.gif\" width=\"1\" height=\"1\">",
                              labels: [inbox, unread, GmailSystemLabel.important, "Label_recruiting", GmailSystemLabel.categoryPersonal], inReplyTo: "<t1m2@fixture.thuban>"), thread: "t1"),
                message(Draft(id: "t1d1", from: me, to: [priya], date: now.addingTimeInterval(-60), subject: "Re: Interview confirmed: Friday 3:00 PM",
                              text: "Hi Priya,\n\nThanks for setting this up — I’ve accepted the invite and will join from the Zoom link on Friday at 3:00 PM.",
                              labels: [GmailSystemLabel.draft], inReplyTo: "<t1m3@fixture.thuban>"), thread: "t1"),
            ])
            let t6 = GmailThread(id: "t6", historyId: "600", messages: [
                message(Draft(id: "t6m1", from: EmailAddress("talent@piedmont.example", name: "Piedmont Energy Talent"), to: [me], date: at(yesterday, 9, 12),
                              subject: "Thanks for speaking with us Tuesday",
                              text: "Hi Alex, thanks for your time on the phone Tuesday. The analytics team will review and follow up within two weeks. — Dana",
                              labels: [inbox, "Label_recruiting", GmailSystemLabel.categoryPersonal]), thread: "t6"),
            ])
            let t8 = GmailThread(id: "t8", historyId: "800", messages: [
                message(Draft(id: "t8m1", from: EmailAddress("morgan.mom@example.com", name: "Mom"), to: [me], date: at(w.adding(days: 2), 18, 40),
                              subject: "Saturday!", text: "What time are you coming Saturday? Aunt Carol wants to do lunch at 1. Love you.",
                              labels: [inbox, unread, GmailSystemLabel.categoryPersonal]), thread: "t8"),
            ])
            let t10 = GmailThread(id: "t10", historyId: "1000", messages: [
                message(Draft(id: "t10m1", from: EmailAddress("statements@carolinacredit.example.org", name: "Carolina Credit Union"), to: [me], date: at(w.adding(days: 1), 6, 0),
                              subject: "Your September statement is ready", text: "Your statement for checking ending in 4471 is ready to view.",
                              labels: [inbox, "Label_receipts", GmailSystemLabel.categoryUpdates], headers: bulk), thread: "t10"),
            ])
            let spam = GmailThread(id: "t11", historyId: "1100", messages: [
                message(Draft(id: "t11m1", from: EmailAddress("prize@win-now.example", name: "Prize Desk"), to: [me], date: at(w.adding(days: -1), 3, 0),
                              subject: "You have been selected!", text: "Claim your reward today.", labels: [GmailSystemLabel.spam]), thread: "t11"),
            ])
            let trashed = GmailThread(id: "t12", historyId: "1200", messages: [
                message(Draft(id: "t12m1", from: EmailAddress("deals@shop.example", name: "Shop"), to: [me], date: at(w.adding(days: -3), 9, 0),
                              subject: "Weekend sale", text: "Everything is 20% off.", labels: [GmailSystemLabel.trash], headers: bulk), thread: "t12"),
            ])

            let t2 = GmailThread(id: "t2", historyId: "200", messages: [
                message(Draft(id: "t2m1", from: school, to: [maya], date: min(todayAt(12, 30), now.addingTimeInterval(-3 * 3600)), subject: "Tonight: bring your Q3 attempts",
                              text: "Yes — see you tonight. I’ll bring my notes.", labels: [GmailSystemLabel.sent, "Label_math"]), thread: "t2"),
                message(Draft(id: "t2m2", from: maya, to: [school], date: min(todayAt(13, 52), now.addingTimeInterval(-48 * 60)), subject: "Re: Tonight: bring your Q3 attempts",
                              text: "Still on for 7 in Atkins 244? Can you grab whiteboard markers on your way — the ones there are dead. Also bring whatever you have for Q3, I’m stuck on part (c).",
                              labels: [inbox, unread, "Label_math"], inReplyTo: "<t2m1@fixture.thuban>"), thread: "t2"),
            ])
            let t3 = GmailThread(id: "t3", historyId: "300", messages: [
                message(Draft(id: "t3m1", from: EmailAddress("epark@campus.example.edu", name: "Dr. Elena Park"), to: [EmailAddress("math2210-students@uni.example.edu", name: "MATH 2210 students")],
                              date: min(todayAt(11, 5), now.addingTimeInterval(-4 * 3600)), subject: "MATH 2210 — Homework 4 now due Friday",
                              text: "Class, because of the Canvas outage Tuesday night, Homework 4 is now due \(friday) at 11:59 PM. Office hours are unchanged. — Dr. Park",
                              labels: [inbox, unread, starred, "Label_math"], headers: [MIMEHeader(name: "List-Id", value: "<math2210-students.charlotte.edu>")]), thread: "t3"),
            ])
            let jordan = EmailAddress("jordan.blake@example.edu", name: "Jordan Blake")
            let t4 = GmailThread(id: "t4", historyId: "400", messages: [
                message(Draft(id: "t4m1", from: school, to: [jordan], date: at(w.adding(days: 3), 16, 40), subject: "Re: Tangent plane question from office hours",
                              text: "Hi Jordan, I redid problem 3 and my tangent plane still doesn’t match the key. Is my setup wrong?", labels: [GmailSystemLabel.sent]), thread: "t4"),
                message(Draft(id: "t4m2", from: jordan, to: [school], date: at(w.adding(days: 3), 18, 2), subject: "Re: Tangent plane question from office hours",
                              text: "Can you send a photo of your work?", labels: [], inReplyTo: "<t4m1@fixture.thuban>"), thread: "t4"),
                message(Draft(id: "t4m3", from: school, to: [jordan], date: at(w.adding(days: 3), 19, 15), subject: "Re: Tangent plane question from office hours",
                              text: "Here it is — thanks for looking.", labels: [GmailSystemLabel.sent], inReplyTo: "<t4m2@fixture.thuban>"), thread: "t4"),
                message(Draft(id: "t4m4", from: jordan, to: [school], date: min(todayAt(9, 40), now.addingTimeInterval(-5 * 3600)), subject: "Re: Tangent plane question from office hours",
                              text: "Your setup was right — the sign error is in f_y. Check the chain rule on the 3xy³ term. If it still doesn’t match, come by next Wednesday at 3:30.",
                              labels: [inbox, starred], inReplyTo: "<t4m3@fixture.thuban>"), thread: "t4"),
            ])
            let t5 = GmailThread(id: "t5", historyId: "500", messages: [
                message(Draft(id: "t5m1", from: EmailAddress("careers@school.example.edu", name: "University Career Center"), to: [school], date: at(yesterday, 8, 0),
                              subject: "Last call: Career Fair sign-up closes tonight",
                              text: "Fall Career Fair · Wednesday, Sept 30 · 10 AM–3 PM · Popp Martin Student Union. 142 employers are registered. Sign-up closes tonight at 11:59 PM.",
                              labels: [inbox, GmailSystemLabel.categoryUpdates], headers: bulk), thread: "t5"),
            ])
            let t7 = GmailThread(id: "t7", historyId: "700", messages: [
                message(Draft(id: "t7m1", from: EmailAddress("urec@campus.example.edu", name: "UREC"), to: [school], date: at(w.adding(days: 2), 7, 30),
                              subject: "Your locker rental renews September 30", text: "Locker B-114 renews for the spring term unless you cancel before September 30.",
                              labels: [inbox], headers: [MIMEHeader(name: "Auto-Submitted", value: "auto-generated")]), thread: "t7"),
            ])
            let t9 = GmailThread(id: "t9", historyId: "900", messages: [
                message(Draft(id: "t9m1", from: EmailAddress("notifications@instructure.com", name: "Canvas Notifications"), to: [school], date: at(w.adding(days: 1), 8, 15),
                              subject: "Graded: Quiz 3 · STAT 2122", text: "Your score: 9 out of 10. Feedback from the instructor is available.",
                              labels: [inbox, GmailSystemLabel.categoryUpdates], headers: bulk), thread: "t9"),
            ])
            let housing = GmailThread(id: "t13", historyId: "1300", messages: [
                message(Draft(id: "t13m1", from: EmailAddress("housing@reslife.example.edu", name: "Housing & Residence Life"), to: [school], date: at(w.adding(days: -6), 10, 0),
                              subject: "Spring housing applications open October 5", text: "Applications for spring housing open October 5 at 9 AM.",
                              labels: ["Label_housing"], headers: bulk), thread: "t13"),
            ])
            return [SampleData.primaryEmail: [t1, t6, t8, t10, spam, trashed], SampleData.schoolEmail: [t2, t3, t4, t5, t7, t9, housing]]
        }

        /// "Friday, September 25".
        static func long(_ day: CivilDate) -> String {
            let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
            return "\(day.weekday.name), \(months[day.month - 1]) \(day.day)"
        }
    }
}
