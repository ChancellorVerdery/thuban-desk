import Foundation
import XCTest
@testable import ThubanDeskCore

final class MailComposeTests: XCTestCase {
    let me = EmailAddress("alex.morgan@example.com", name: "Alex Morgan")
    let priya = EmailAddress("priya.shah@crescentlabs-hq.example", name: "Priya Shah")
    let marcus = EmailAddress("marcus.lee@crescentlabs.example.org", name: "Marcus Lee")

    func original() -> MailMessage {
        MailMessage(id: "m3", threadID: "t1", date: ny(2026, 9, 24, 14, 14), from: priya, to: [me], cc: [marcus],
                    subject: "Re: Interview confirmed: Friday 3:00 PM", messageIDHeader: "<m3@x>", references: ["<m1@x>", "<m2@x>"],
                    text: "Great — you’re confirmed for Friday, September 25 at 3:00 PM with Marcus Lee from our platform team.")
    }

    // MARK: Draft → outgoing

    func testReplyStartsFromThreadAccountWithHeaders() {
        let draft = ComposeDraft.reply(to: original(), account: me, replyAll: false, ownAddresses: [me.normalized])
        XCTAssertEqual(draft.account, me.normalized)
        XCTAssertEqual(draft.to, [priya])
        XCTAssertEqual(draft.cc, [])
        XCTAssertEqual(draft.subject, "Re: Interview confirmed: Friday 3:00 PM")
        XCTAssertFalse(draft.canChangeAccount)
        XCTAssertEqual(draft.windowTitle, "Reply · Interview confirmed: Friday 3:00 PM")
        XCTAssertEqual(ComposeDraft.baseSubject("RE: Fwd: re:Hello"), "Hello")

        var edited = draft
        edited.html = "<p>Hi Priya,</p>"
        edited.text = "Hi Priya,"
        let message = edited.outgoing(from: me, ownAddresses: [me.normalized], zone: newYork)
        XCTAssertEqual(message.inReplyTo, "<m3@x>")
        XCTAssertEqual(message.references, ["<m1@x>", "<m2@x>", "<m3@x>"])
        XCTAssertEqual(message.threadID, "t1")
        XCTAssertEqual(message.to, [priya])
        XCTAssertTrue(message.html?.hasPrefix("<p>Hi Priya,</p>") ?? false)
        XCTAssertTrue(message.html?.contains("gmail_quote") ?? false)
        XCTAssertTrue(message.text.contains("On Thu, Sep 24 at 2:14 PM, Priya Shah wrote:"))
        XCTAssertTrue(message.text.contains("> Great — you’re confirmed"))
        let raw = MIMEBuilder.build(message, date: designNow, zone: newYork, boundarySeed: "s")
        XCTAssertTrue(raw.contains("In-Reply-To: <m3@x>"))
        XCTAssertTrue(raw.contains("multipart/alternative"))
    }

    func testReplyAllKeepsOthersAndDropsSelf() {
        let draft = ComposeDraft.reply(to: original(), account: me, replyAll: true, ownAddresses: [me.normalized])
        XCTAssertEqual(draft.to, [priya])
        XCTAssertEqual(draft.cc, [marcus])
        XCTAssertEqual(draft.windowTitle.hasPrefix("Reply all"), true)
    }

    func testEditedRecipientsWinOverTheReplyDefaults() {
        var draft = ComposeDraft.reply(to: original(), account: me, replyAll: true, ownAddresses: [me.normalized])
        draft.cc = []
        draft.bcc = [EmailAddress("me2@example.org")]
        draft.text = "ok"
        let message = draft.outgoing(from: me, ownAddresses: [me.normalized], zone: newYork)
        XCTAssertEqual(message.cc, [])
        XCTAssertEqual(message.bcc.map(\.email), ["me2@example.org"])
        XCTAssertTrue(message.html?.hasPrefix("ok") ?? false, "plain text body becomes HTML when no rich body")
    }

    func testForwardAndNew() {
        var forward = ComposeDraft.forward(original(), account: me)
        XCTAssertEqual(forward.subject, "Fwd: Re: Interview confirmed: Friday 3:00 PM")
        forward.to = [EmailAddress("mom@example.org")]
        let message = forward.outgoing(from: me, zone: newYork)
        XCTAssertEqual(message.to.map(\.email), ["mom@example.org"])
        XCTAssertTrue(message.text.contains("---------- Forwarded message ---------"))
        XCTAssertNil(message.inReplyTo)

        var new = ComposeDraft(account: "Alex.Morgan@example.com", to: [priya], subject: "Hello", text: "Hi")
        new.draftID = "d1"
        XCTAssertTrue(new.canChangeAccount)
        XCTAssertEqual(new.account, "alex.morgan@example.com")
        let out = new.outgoing(from: me)
        XCTAssertEqual(out.draftID, "d1")
        XCTAssertNil(out.threadID)
        XCTAssertEqual(out.subject, "Hello")
    }

    func testEmptinessAndSendProblems() {
        var draft = ComposeDraft(account: me.email)
        XCTAssertTrue(draft.isEmpty)
        XCTAssertEqual(draft.sendProblem, "Add at least one recipient.")
        draft.to = [EmailAddress("not-an-address")]
        XCTAssertFalse(draft.isEmpty)
        XCTAssertEqual(draft.sendProblem, "“not-an-address” is not an email address.")
        draft.to = [priya]
        XCTAssertNil(draft.sendProblem)
        // A reply with nothing typed is empty even though it has recipients from the thread? No: recipients count.
        let reply = ComposeDraft.reply(to: original(), account: me, replyAll: false, ownAddresses: [])
        XCTAssertFalse(reply.isEmpty)
    }

    // MARK: Recipients

    func testParseRecipients() {
        let parsed = ComposeDraft.parseRecipients("maya.chen@students.example.edu, Priya Shah <priya.shah@crescentlabs-hq.example>; bob@x.org")
        XCTAssertEqual(parsed.addresses.map(\.email), ["maya.chen@students.example.edu", "priya.shah@crescentlabs-hq.example", "bob@x.org"])
        XCTAssertEqual(parsed.addresses[1].name, "Priya Shah")
        XCTAssertEqual(parsed.rest, "")
        let partial = ComposeDraft.parseRecipients("maya")
        XCTAssertEqual(partial.addresses, [])
        XCTAssertEqual(partial.rest, "maya")
        XCTAssertTrue(ComposeDraft.isValidAddress("a.b@c.io"))
        XCTAssertFalse(ComposeDraft.isValidAddress("a@b"))
        XCTAssertFalse(ComposeDraft.isValidAddress("a @b.com"))
        XCTAssertEqual(ComposeDraft.adding([priya, EmailAddress("PRIYA.SHAH@crescentlabs-hq.example")], to: [priya]), [priya])
    }

    func testSuggestionsRankPrefixFirstAndSkipOwnAndPresent() {
        let contacts = [EmailAddress("jordan.blake@example.edu", name: "Jordan Blake"), EmailAddress("maya.chen@students.example.edu", name: "Maya Chen"),
                        me, EmailAddress("lmaya@x.org", name: "Lee"), priya]
        let found = ComposeDraft.suggestions("maya", contacts: contacts, excluding: [], own: [me.normalized])
        XCTAssertEqual(found.map(\.email), ["maya.chen@students.example.edu", "lmaya@x.org"])
        XCTAssertEqual(ComposeDraft.suggestions("chan", contacts: contacts, excluding: [], own: [me.normalized]).map(\.email), [])
        XCTAssertEqual(ComposeDraft.suggestions("e", contacts: contacts, excluding: [priya], own: [], limit: 2).count, 2)
        XCTAssertEqual(ComposeDraft.suggestions("  ", contacts: contacts, excluding: [], own: []), [])
    }

    func testQuoteAttributionAndExcerpt() {
        XCTAssertEqual(ComposeDraft.quoteAttribution(original(), zone: newYork), "On Thu, Sep 24 at 2:14 PM, Priya Shah wrote:")
        XCTAssertEqual(ComposeDraft.quoteExcerpt(original()), "Great — you’re confirmed for Friday, September 25 at 3:00 PM with Marcus Lee…")
    }

    func testByteSize() {
        XCTAssertEqual(ByteSize.text(1), "1 byte")
        XCTAssertEqual(ByteSize.text(2_048), "2 KB")
        XCTAssertEqual(ByteSize.text(2_516_582), "2.4 MB")
        XCTAssertEqual(ByteSize.text(30 * 1_048_576), "30 MB")
    }

    // MARK: Invitation card

    func testInviteMatchesTheSampleInterviewForPriyasMessage() throws {
        let world = SampleData.world(now: designNow, zone: newYork)
        let account = SampleData.primaryEmail
        let thread = try XCTUnwrap(world.threads[account]?.first { $0.id == "t1" })
        let message = MailThread(account: account, thread).messages.last { !$0.isDraft }!
        let candidates = world.events.flatMap { account, calendars in
            calendars.flatMap { id, events in events.map { AgendaEvent(calendar: CalendarKey(account: account, calendarID: id), event: $0) } }
        }
        let invite = try XCTUnwrap(MailInvite.match(message, candidates: candidates, zone: newYork))
        XCTAssertEqual(invite.event.title, "Interview · Crescent Labs")
        XCTAssertEqual(MailInvite.detailLine(invite.event, zone: newYork), "3:00 – 3:45 PM · Zoom · Priya Shah, Marcus Lee")
        // Maya's thread has no invitation from her in the future beyond the study group she organizes.
        let other = MailMessage(id: "x", threadID: "x", date: designNow, from: EmailAddress("nobody@example.org"))
        XCTAssertNil(MailInvite.match(other, candidates: candidates, zone: newYork))
    }

    func testAvailabilityText() {
        func timed(_ id: String, _ title: String, _ h: Int, _ m: Int, _ h2: Int, _ m2: Int) -> AgendaEvent {
            AgendaEvent(calendar: CalendarKey(account: "a@b.c", calendarID: "c"),
                        event: CalendarEvent(id: id, summary: title, start: EventDateTime(dateTime: ny(2026, 9, 25, h, m)), end: EventDateTime(dateTime: ny(2026, 9, 25, h2, m2))))
        }
        let interview = timed("i", "Interview", 15, 0, 15, 45).event
        let phys = timed("p", "PHYS 2102 · Physics II", 13, 0, 14, 15)
        let morning = timed("m", "Gym", 7, 0, 8, 0)
        let free = MailInvite.availability(of: interview, among: [morning, phys], zone: newYork)
        XCTAssertEqual(MailInvite.availabilityText(free, zone: newYork), "Free then — after PHYS 2102 ends at 2:15")
        XCTAssertEqual(MailInvite.availabilityText(MailInvite.availability(of: interview, among: [], zone: newYork)), "Free then")
        let clash = timed("s", "Study group · MATH 2210", 15, 30, 16, 30)
        XCTAssertEqual(MailInvite.availabilityText(MailInvite.availability(of: interview, among: [phys, clash], zone: newYork)), "Conflicts with Study group")
        var declined = clash
        declined.event.attendees = [EventAttendee(email: "a@b.c", isSelf: true, responseStatus: .declined)]
        XCTAssertEqual(MailInvite.availability(of: interview, among: [declined], zone: newYork), .free(after: nil, endsAt: nil))
        XCTAssertEqual(MailInvite.timeRange(ny(2026, 9, 25, 11, 30), ny(2026, 9, 25, 12, 15), zone: newYork), "11:30 AM – 12:15 PM")
    }

    // MARK: Reader style

    func testDesignedMailDetection() {
        XCTAssertFalse(MailReaderStyle.isDesigned("<p>Hi <b>there</b></p><span style=\"color:#888\">sig</span>"))
        XCTAssertTrue(MailReaderStyle.isDesigned("<table bgcolor=\"#fff\"><tr><td>x</td></tr></table>"))
        XCTAssertTrue(MailReaderStyle.isDesigned("<div style=\"background-color: #f4f4f4\">x</div>"))
        XCTAssertFalse(MailReaderStyle.isDesigned(nil))
        let css = MailReaderStyle.css(theme: ThemeResolver.resolve(.default, systemIsDark: true), paper: true)
        XCTAssertTrue(css.contains("color-scheme: light"))
    }
}
