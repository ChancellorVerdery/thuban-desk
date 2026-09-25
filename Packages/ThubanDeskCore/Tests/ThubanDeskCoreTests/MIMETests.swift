import XCTest
@testable import ThubanDeskCore

final class MIMETests: XCTestCase {
    // MARK: Headers

    func testRFC2047Decoding() {
        XCTAssertEqual(RFC2047.decode("=?UTF-8?B?Q2Fmw6kgcGxhbnMg4piV?= for Friday"), "Café plans ☕ for Friday")
        XCTAssertEqual(RFC2047.decode("=?iso-8859-1?Q?Andr=E9_Pirard?="), "André Pirard")
        // Adjacent encoded words join without the whitespace between them.
        XCTAssertEqual(RFC2047.decode("=?UTF-8?Q?a?= =?UTF-8?Q?b?=  c"), "ab  c")
        XCTAssertEqual(RFC2047.decode("Plain subject"), "Plain subject")
        XCTAssertEqual(RFC2047.decode("=?UTF-8?X?bad?="), "=?UTF-8?X?bad?=")
    }

    func testRFC2047EncodingRoundTripsAndStaysShort() {
        let long = String(repeating: "Größenänderung ", count: 8) + "✓"
        let encoded = RFC2047.encode(long)
        XCTAssertTrue(encoded.components(separatedBy: "\r\n ").allSatisfy { $0.count <= 75 })
        XCTAssertEqual(RFC2047.decode(encoded.replacingOccurrences(of: "\r\n", with: "")), long)
        XCTAssertEqual(RFC2047.encode("ASCII only"), "ASCII only")
    }

    func testAddressListParsing() {
        let list = EmailAddress.parseList("\"Morgan, Alex\" <alex.morgan@example.com>, maya.chen@students.example.edu, =?UTF-8?Q?Ren=C3=A9e?= <renee@x.org>, bob@x.org (Bob Smith)")
        XCTAssertEqual(list.map(\.email), ["alex.morgan@example.com", "maya.chen@students.example.edu", "renee@x.org", "bob@x.org"])
        XCTAssertEqual(list.map(\.name), ["Morgan, Alex", nil, "Renée", "Bob Smith"])
        XCTAssertEqual(list[0].header, "\"Morgan, Alex\" <alex.morgan@example.com>")
        XCTAssertEqual(list[2].header, "=?UTF-8?B?UmVuw6ll?= <renee@x.org>")
        XCTAssertEqual(EmailAddress("priya.shah@crescentlabs-hq.example", name: "Priya Shah").initials, "PS")
        XCTAssertEqual(EmailAddress.parseList("Team: a@x.org, b@x.org;").map(\.email), ["a@x.org", "b@x.org"])
        XCTAssertTrue(EmailAddress.parseList("undisclosed-recipients:;").isEmpty)
    }

    func testHeaderParametersIncludingRFC2231() {
        let type = HeaderParameters("text/plain; charset=\"UTF-8\"; format=flowed")
        XCTAssertEqual(type.value, "text/plain")
        XCTAssertEqual(type["charset"], "UTF-8")
        XCTAssertEqual(HeaderParameters("attachment; filename*=UTF-8''%E2%82%AC%20rates.pdf")["filename"], "€ rates.pdf")
        XCTAssertEqual(HeaderParameters("attachment; filename*0*=UTF-8''Na%C3%AFve; filename*1=\" plan.txt\"")["filename"], "Naïve plan.txt")
    }

    func testQuotedPrintableRoundTrip() {
        let text = "Café = crème brûlée\nA line with trailing space \n" + String(repeating: "x", count: 120)
        let encoded = QuotedPrintable.encode(text)
        XCTAssertTrue(encoded.components(separatedBy: "\r\n").allSatisfy { $0.count <= 76 })
        XCTAssertTrue(encoded.contains("=3D"))
        XCTAssertEqual(String(decoding: QuotedPrintable.decode(encoded), as: UTF8.self), text)
    }

    // MARK: Gmail payloads

    func testGmailPayloadExtraction() throws {
        let message = try GoogleJSON.decoder.decode(GmailMessage.self, from: fixtureData("gmail_message_mixed.json"))
        let mail = MailMessage(message)
        XCTAssertEqual(mail.subject, "Café plans ☕ for Friday")
        XCTAssertEqual(mail.from?.name, "Renée O’Brien")
        XCTAssertEqual(mail.to.count, 2)
        XCTAssertEqual(mail.cc.first?.email, "sam@example.com")
        XCTAssertEqual(mail.text, "Plain café body\nLine two")
        XCTAssertEqual(mail.html, "<p>HTML <b>café</b> body</p><img src=\"cid:logo1\">")
        XCTAssertEqual(mail.messageIDHeader, "<abc123@mail.example.com>")
        XCTAssertEqual(mail.references, ["<r1@example.com>", "<r2@example.com>"])
        XCTAssertEqual(mail.snippet, "Hi & welcome 'friend'")
        XCTAssertTrue(mail.isUnread)
        XCTAssertEqual(mail.date, Date(timeIntervalSince1970: 1_790_273_640))
        XCTAssertEqual(mail.attachments.count, 2)
        let inline = try XCTUnwrap(mail.attachments.first { $0.contentID == "logo1" })
        XCTAssertTrue(inline.isInline)
        XCTAssertNotNil(inline.data)
        let pdf = try XCTUnwrap(mail.attachments.first { $0.filename == "Syllabus Fall.pdf" })
        XCTAssertEqual(pdf.attachmentID, "ANGjdJ8")
        XCTAssertEqual(pdf.size, 48213)
        XCTAssertFalse(pdf.isInline)
        XCTAssertTrue(mail.hasAttachments)
    }

    // MARK: Building and round trips

    func testBuildParsesBackIdentically() throws {
        let message = OutgoingMessage(
            from: EmailAddress("alex.morgan@example.com", name: "Alex Morgan"),
            to: [EmailAddress("priya.shah@crescentlabs-hq.example", name: "Priya Shah")],
            cc: [EmailAddress("renee@x.org", name: "Renée O’Brien")],
            bcc: [EmailAddress("me@x.org")],
            subject: "Re: Interview — café ☕",
            html: "<p>Hi Priya,</p><p>I’ve <b>accepted</b> the invite. Is <i>Python</i> fine?</p>",
            text: "Hi Priya,\n\nI’ve accepted the invite. Is Python fine?",
            inReplyTo: "<t1m3@fixture.thuban>", references: ["<t1m1@fixture.thuban>", "<t1m3@fixture.thuban>"], threadID: "t1",
            attachments: [OutgoingAttachment(filename: "résumé.pdf", mimeType: "application/pdf", data: Data((0..<300).map { UInt8($0 % 256) }))])
        let raw = MIMEBuilder.build(message, date: ny(2026, 9, 24, 14, 41), zone: newYork, boundarySeed: "seed")
        XCTAssertTrue(raw.contains("Date: Thu, 24 Sep 2026 14:41:00 -0400"))
        XCTAssertTrue(raw.contains("In-Reply-To: <t1m3@fixture.thuban>"))
        XCTAssertTrue(raw.contains("MIME-Version: 1.0"))
        XCTAssertTrue(raw.contains("multipart/mixed; boundary=\"mix-seed\""))
        XCTAssertTrue(raw.contains("multipart/alternative; boundary=\"alt-seed\""))
        XCTAssertFalse(raw.contains("\n\n") && !raw.contains("\r\n\r\n"), "CRLF line endings")

        let parsed = MIMEParser.parse(raw)
        XCTAssertEqual(parsed.decodedHeader("Subject"), "Re: Interview — café ☕")
        XCTAssertEqual(EmailAddress.parseList(parsed.header("Cc")).first?.name, "Renée O’Brien")
        XCTAssertEqual(EmailAddress.parseList(parsed.header("Bcc")).first?.email, "me@x.org")
        XCTAssertEqual(parsed.header("References"), "<t1m1@fixture.thuban> <t1m3@fixture.thuban>")
        let content = MIMEContent.extract(parsed)
        XCTAssertEqual(content.text, message.text)
        XCTAssertEqual(content.html, message.html)
        XCTAssertEqual(content.attachments.count, 1)
        XCTAssertEqual(content.attachments.first?.filename, "résumé.pdf")
        XCTAssertEqual(content.attachments.first?.data, message.attachments.first?.data)

        // Gmail's JSON shape carries the same content.
        let payload = GmailMessagePart(mime: parsed)
        let viaJSON = try GoogleJSON.decoder.decode(GmailMessagePart.self, from: GoogleJSON.encoder.encode(payload))
        XCTAssertEqual(MIMEContent.extract(viaJSON.mime).html, message.html)

        // base64url raw decodes to the same text.
        let encoded = MIMEBuilder.raw(message, date: ny(2026, 9, 24, 14, 41), zone: newYork)
        XCTAssertFalse(encoded.contains("+") || encoded.contains("/") || encoded.contains("="))
        XCTAssertNotNil(Base64URL.decode(encoded))
    }

    func testPlainTextOnlyMessage() {
        let message = OutgoingMessage(from: EmailAddress("a@x.org"), to: [EmailAddress("b@x.org")], subject: "Hi", text: "Just text.\nTwo lines.")
        let parsed = MIMEParser.parse(MIMEBuilder.build(message))
        XCTAssertEqual(parsed.mimeType, "text/plain")
        XCTAssertEqual(MIMEContent.extract(parsed).text, "Just text.\nTwo lines.")
        XCTAssertNil(MIMEContent.extract(parsed).html)
    }

    func testRawParserHandlesBase64AndLatin1() {
        let raw = "From: a@x.org\r\nSubject: =?iso-8859-1?Q?caf=E9?=\r\nContent-Type: text/plain; charset=iso-8859-1\r\nContent-Transfer-Encoding: base64\r\n\r\n"
            + Data([0x63, 0x61, 0x66, 0xE9]).base64EncodedString() + "\r\n"
        let part = MIMEParser.parse(raw)
        XCTAssertEqual(part.decodedHeader("Subject"), "café")
        XCTAssertEqual(part.text, "café")
    }

    // MARK: Reply / forward

    func original() throws -> MailMessage {
        MailMessage(try GoogleJSON.decoder.decode(GmailMessage.self, from: fixtureData("gmail_message_mixed.json")))
    }

    func testReplyHeadersAndRecipients() throws {
        let me = EmailAddress("alex.morgan@example.com", name: "Alex Morgan")
        let source = try original()
        let reply = MIMEBuilder.reply(to: source, from: me, replyAll: false, html: "<p>Sounds good.</p>", text: "Sounds good.", zone: newYork)
        XCTAssertEqual(reply.subject, "Re: Café plans ☕ for Friday")
        XCTAssertEqual(reply.to.map(\.email), ["renee@example.com"])
        XCTAssertTrue(reply.cc.isEmpty)
        XCTAssertEqual(reply.inReplyTo, "<abc123@mail.example.com>")
        XCTAssertEqual(reply.references, ["<r1@example.com>", "<r2@example.com>", "<abc123@mail.example.com>"])
        XCTAssertEqual(reply.threadID, "18a0")
        XCTAssertTrue(reply.text.contains("On Thu, Sep 24 at 2:14 PM, Renée O’Brien wrote:"))
        XCTAssertTrue(reply.text.contains("> Plain café body"))
        XCTAssertTrue(reply.html?.contains("<blockquote") ?? false)

        let all = MIMEBuilder.reply(to: source, from: me, replyAll: true, html: nil, text: "OK", zone: newYork)
        XCTAssertEqual(all.to.map(\.email), ["renee@example.com", "maya.chen@students.example.edu"], "own address removed")
        XCTAssertEqual(all.cc.map(\.email), ["sam@example.com"])
        XCTAssertEqual(MIMEBuilder.replySubject("RE: x"), "RE: x")

        // The reply's raw form threads correctly.
        let parsed = MIMEParser.parse(MIMEBuilder.build(reply, zone: newYork))
        XCTAssertEqual(parsed.header("In-Reply-To"), "<abc123@mail.example.com>")
    }

    /// Regression: encoded-words that decode to CR/LF must never become extra headers in a reply / forward.
    func testReplyToEncodedWordsWithLineBreaksCannotInjectHeaders() throws {
        func b64(_ text: String) -> String { "=?UTF-8?B?\(Data(text.utf8).base64EncodedString())?=" }
        let raw = "From: \(b64("Mallory\r\nBcc: evil@example.com")) <mallory@example.com>\r\n"
            + "To: alex.morgan@example.com\r\n"
            + "Subject: \(b64("Hi\r\nBcc: evil@example.com"))\r\n"
            + "Message-ID: <inj1@example.com>\r\nContent-Type: text/plain\r\n\r\nHello\r\n"
        let parsed = MIMEParser.parse(raw)
        let subject = try XCTUnwrap(parsed.decodedHeader("Subject"))
        XCTAssertFalse(subject.contains("\r") || subject.contains("\n"))
        let from = try XCTUnwrap(EmailAddress.parseList(parsed.header("From")).first)
        XCTAssertFalse(from.name?.contains("\n") ?? true)
        let original = MailMessage(id: "i", threadID: "t", date: designNow, from: from, to: [EmailAddress("alex.morgan@example.com")],
                                   subject: subject, messageIDHeader: "<inj1@example.com>\r\nBcc: evil@example.com", text: "Hello")
        let me = EmailAddress("alex.morgan@example.com", name: "Alex Morgan")
        for message in [MIMEBuilder.reply(to: original, from: me, replyAll: false, html: nil, text: "OK", zone: newYork),
                        MIMEBuilder.reply(to: original, from: me, replyAll: true, html: "<p>OK</p>", text: "OK", zone: newYork),
                        MIMEBuilder.forward(original, from: me, to: [from], html: nil, text: "FYI",
                                            attachments: [OutgoingAttachment(filename: "a\r\nBcc: evil@example.com.txt", mimeType: "text/plain", data: Data("x".utf8))],
                                            zone: newYork)] {
            let built = MIMEBuilder.build(message, date: designNow, zone: newYork, boundarySeed: "s")
            let lines = built.components(separatedBy: "\r\n")
            XCTAssertFalse(lines.contains { $0.lowercased().hasPrefix("bcc:") }, built)
            XCTAssertNil(MIMEParser.parse(built).header("Bcc"))
        }
        // Values set directly (not via decode) are guarded too.
        var direct = OutgoingMessage(from: EmailAddress("me@x.org", name: "Me\nBcc: a@b.c"), to: [EmailAddress("x@y.org")], subject: "S\r\nBcc: a@b.c", text: "t")
        direct.references = ["<r@x>\r\nBcc: a@b.c"]
        direct.inReplyTo = "<r@x>\nBcc: a@b.c"
        XCTAssertFalse(MIMEBuilder.build(direct).components(separatedBy: "\r\n").contains { $0.lowercased().hasPrefix("bcc:") })
    }

    func testForward() throws {
        let fwd = MIMEBuilder.forward(try original(), from: EmailAddress("alex.morgan@example.com"), to: [EmailAddress("dad@x.org")],
                                      html: "<p>FYI</p>", text: "FYI", zone: newYork)
        XCTAssertEqual(fwd.subject, "Fwd: Café plans ☕ for Friday")
        XCTAssertTrue(fwd.text.contains("---------- Forwarded message ---------"))
        XCTAssertTrue(fwd.text.contains("Subject: Café plans ☕ for Friday"))
        XCTAssertEqual(MIMEBuilder.forwardSubject("Fwd: x"), "Fwd: x")
    }

    // MARK: HTML

    func testEventDescriptionSanitizing() {
        let html = "Bring <b>Q3</b> <a href=\"https://x.org\" onclick=\"evil()\">notes</a><script>alert(1)</script><iframe src=\"https://x\"></iframe><img src=\"https://t.example/p.gif\">"
        let clean = HTMLSanitizer.eventDescription(html)
        XCTAssertTrue(clean.contains("<b>Q3</b>"))
        XCTAssertTrue(clean.contains("href=\"https://x.org\""))
        XCTAssertFalse(clean.contains("script"))
        XCTAssertFalse(clean.contains("onclick"))
        XCTAssertFalse(clean.contains("iframe"))
        XCTAssertFalse(clean.contains("<img"))
        XCTAssertEqual(HTMLSanitizer.eventDescription("Line 1\nhttps://zoom.us/j/1"), "Line 1<br><a href=\"https://zoom.us/j/1\">https://zoom.us/j/1</a>")
        let rich = HTMLSanitizer.richText("Bring <b>Q3</b><ul><li>Maya</li><li>You</li></ul>")
        XCTAssertEqual(String(rich.characters), "Bring Q3\n• Maya\n• You")
        XCTAssertEqual(HTMLSanitizer.plainText("<p>One</p><p>Two&nbsp;three</p>"), "One\nTwo three")
    }

    func testMailHTMLBlocksRemoteImagesAndScripts() {
        let html = "<p onmouseover=\"x()\">Hi</p><script>bad()</script><a href=\"javascript:bad()\">x</a><img src=\"https://tracker.example/o.gif\"><img src=\"cid:logo\"><form><input></form>"
        let blocked = MailHTML.prepare(html: html, text: nil, allowRemoteImages: false, inlineImages: ["logo": Data([1, 2, 3])], inlineTypes: ["logo": "image/png"])
        XCTAssertTrue(blocked.hasRemoteImages)
        XCTAssertTrue(blocked.document.contains("img-src data:;"))
        XCTAssertFalse(blocked.document.contains("<script"))
        XCTAssertFalse(blocked.document.contains("onmouseover"))
        XCTAssertFalse(blocked.document.contains("javascript:"))
        XCTAssertFalse(blocked.document.contains("<form"))
        XCTAssertTrue(blocked.document.contains("data:image/png;base64,AQID"))
        let allowed = MailHTML.prepare(html: html, text: nil, allowRemoteImages: true)
        XCTAssertTrue(allowed.document.contains("img-src data: https: http:"))
        XCTAssertFalse(MailHTML.prepare(html: nil, text: "plain", allowRemoteImages: false).hasRemoteImages)
    }
}
