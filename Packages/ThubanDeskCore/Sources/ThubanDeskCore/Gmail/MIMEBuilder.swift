import Foundation

public struct OutgoingAttachment: Hashable, Sendable {
    public var filename: String
    public var mimeType: String
    public var data: Data

    public init(filename: String, mimeType: String, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

/// A message being composed (new, reply, forward). `MIMEBuilder.build` turns it into RFC 2822 text.
public struct OutgoingMessage: Hashable, Sendable {
    /// The account's address (and display name) — replies are always sent from the account the thread arrived in.
    public var from: EmailAddress
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var bcc: [EmailAddress]
    public var subject: String
    /// Rich body; nil sends plain text only.
    public var html: String?
    /// Plain alternative (derived from `html` when empty).
    public var text: String
    /// `Message-ID` of the message being answered (with angle brackets).
    public var inReplyTo: String?
    public var references: [String]
    /// Gmail thread to file the sent message in (replies / forwards keep the thread).
    public var threadID: String?
    public var attachments: [OutgoingAttachment]
    /// Gmail draft id once saved (drafts.update / drafts.send).
    public var draftID: String?

    public init(from: EmailAddress, to: [EmailAddress] = [], cc: [EmailAddress] = [], bcc: [EmailAddress] = [], subject: String = "",
                html: String? = nil, text: String = "", inReplyTo: String? = nil, references: [String] = [], threadID: String? = nil,
                attachments: [OutgoingAttachment] = [], draftID: String? = nil) {
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.html = html
        self.text = text
        self.inReplyTo = inReplyTo
        self.references = references
        self.threadID = threadID
        self.attachments = attachments
        self.draftID = draftID
    }

    public var allRecipients: [EmailAddress] { to + cc + bcc }
    public var hasRecipients: Bool { !allRecipients.isEmpty }
}

/// RFC 2822 / MIME construction for Gmail `messages.send` and `drafts` (`raw`, base64url). HTML messages are sent
/// as multipart/alternative (plain + HTML); with attachments the alternative part is wrapped in multipart/mixed.
/// Bodies are UTF-8, quoted-printable; attachments base64; non-ASCII headers RFC 2047-encoded.
public enum MIMEBuilder {
    /// The full message text with CRLF line endings. `boundarySeed` makes output deterministic in tests.
    public static func build(_ message: OutgoingMessage, date: Date = Date(), zone: TimeZone = .current, boundarySeed: String? = nil) -> String {
        var headers: [(String, String)] = [
            ("From", message.from.header),
        ]
        if !message.to.isEmpty { headers.append(("To", EmailAddress.headerList(message.to))) }
        if !message.cc.isEmpty { headers.append(("Cc", EmailAddress.headerList(message.cc))) }
        if !message.bcc.isEmpty { headers.append(("Bcc", EmailAddress.headerList(message.bcc))) }
        headers.append(("Subject", RFC2047.encode(message.subject)))
        headers.append(("Date", RFC2822Date.string(date, zone: zone)))
        if let inReplyTo = message.inReplyTo { headers.append(("In-Reply-To", inReplyTo)) }
        if !message.references.isEmpty { headers.append(("References", message.references.joined(separator: "\r\n "))) }
        headers.append(("MIME-Version", "1.0"))

        let seed = boundarySeed ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let text = message.text.isEmpty && message.html != nil ? HTMLSanitizer.plainText(message.html) : message.text
        var body: (headers: [(String, String)], content: String)
        if let html = message.html {
            let boundary = "alt-" + seed
            body = ([("Content-Type", "multipart/alternative; boundary=\"\(boundary)\"")],
                    multipart(boundary: boundary, parts: [textPart(text, subtype: "plain"), textPart(html, subtype: "html")]))
        } else {
            let part = textPart(text, subtype: "plain")
            body = (part.headers, part.content)
        }
        if !message.attachments.isEmpty {
            let boundary = "mix-" + seed
            let inner = body
            let files = message.attachments.map(attachmentPart)
            body = ([("Content-Type", "multipart/mixed; boundary=\"\(boundary)\"")], multipart(boundary: boundary, parts: [inner] + files))
        }
        headers += body.headers
        return headers.map { "\($0.0): \($0.1)" }.joined(separator: "\r\n") + "\r\n\r\n" + body.content
    }

    /// base64url of `build(message)` — the `raw` field.
    public static func raw(_ message: OutgoingMessage, date: Date = Date(), zone: TimeZone = .current) -> String {
        Base64URL.encode(Data(build(message, date: date, zone: zone).utf8))
    }

    private static func textPart(_ content: String, subtype: String) -> (headers: [(String, String)], content: String) {
        ([("Content-Type", "text/\(subtype); charset=\"UTF-8\""), ("Content-Transfer-Encoding", "quoted-printable")], QuotedPrintable.encode(content))
    }

    private static func attachmentPart(_ file: OutgoingAttachment) -> (headers: [(String, String)], content: String) {
        let name = file.filename.replacingOccurrences(of: "\"", with: "'")
        let encodedName = name.unicodeScalars.allSatisfy(\.isASCII) ? "\"\(name)\"" : "\"\(RFC2047.encode(name))\""
        let base64 = file.data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        return ([("Content-Type", "\(file.mimeType); name=\(encodedName)"),
                 ("Content-Disposition", "attachment; filename=\(encodedName)"),
                 ("Content-Transfer-Encoding", "base64")], base64)
    }

    private static func multipart(boundary: String, parts: [(headers: [(String, String)], content: String)]) -> String {
        var out = ""
        for part in parts {
            out += "--\(boundary)\r\n"
            out += part.headers.map { "\($0.0): \($0.1)" }.joined(separator: "\r\n")
            out += "\r\n\r\n" + part.content + "\r\n"
        }
        return out + "--\(boundary)--"
    }

    // MARK: Reply / forward

    /// "Re: …" unless the subject already starts with Re:.
    public static func replySubject(_ subject: String) -> String {
        subject.range(of: #"^\s*re\s*:"#, options: [.regularExpression, .caseInsensitive]) != nil ? subject : "Re: \(subject)"
    }

    public static func forwardSubject(_ subject: String) -> String {
        subject.range(of: #"^\s*(fwd?|fw)\s*:"#, options: [.regularExpression, .caseInsensitive]) != nil ? subject : "Fwd: \(subject)"
    }

    /// A reply (or reply-all) from `account` to `original`: recipients from Reply-To / From (reply-all adds the
    /// other To and Cc addresses, minus the user's own), `Re:` subject, In-Reply-To + References, same thread, the
    /// original quoted below the body. `ownAddresses` are all the user's addresses (every linked account and alias).
    public static func reply(to original: MailMessage, from account: EmailAddress, replyAll: Bool, html: String?, text: String,
                             ownAddresses: Set<String> = [], zone: TimeZone = .current) -> OutgoingMessage {
        let own = ownAddresses.union([account.normalized])
        var to: [EmailAddress]
        var cc: [EmailAddress] = []
        if original.from.map({ own.contains($0.normalized) }) ?? false {
            // Replying to our own sent message: answer its recipients.
            to = original.to
        } else {
            to = original.replyTo.isEmpty ? (original.from.map { [$0] } ?? []) : original.replyTo
        }
        if replyAll {
            to += original.to
            cc = original.cc
        }
        var seen = Set<String>()
        to = to.filter { !own.contains($0.normalized) && seen.insert($0.normalized).inserted }
        cc = cc.filter { !own.contains($0.normalized) && seen.insert($0.normalized).inserted }
        var references = original.references
        if let id = original.messageIDHeader, !references.contains(id) { references.append(id) }
        let attribution = "On \(attributionDate(original.date, zone: zone)), \(original.from?.displayName ?? "someone") wrote:"
        let quotedText = original.plainBody.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
        let quotedHTML = original.html ?? HTMLSanitizer.plainTextToHTML(original.plainBody)
        return OutgoingMessage(
            from: account, to: to, cc: cc, subject: replySubject(original.subject),
            html: html.map { "\($0)<br><br><div class=\"gmail_quote\">\(HTMLSanitizer.escape(attribution))<br><blockquote class=\"gmail_quote\" style=\"margin:0 0 0 .8ex;border-left:1px solid #ccc;padding-left:1ex\">\(quotedHTML)</blockquote></div>" },
            text: text + "\n\n" + attribution + "\n" + quotedText,
            inReplyTo: original.messageIDHeader, references: references, threadID: original.threadID)
    }

    /// A forward: `Fwd:` subject, the original's header block and body below, same thread, attachments passed in.
    public static func forward(_ original: MailMessage, from account: EmailAddress, to: [EmailAddress], html: String?, text: String,
                               attachments: [OutgoingAttachment] = [], zone: TimeZone = .current) -> OutgoingMessage {
        let headerLines = [
            "---------- Forwarded message ---------",
            "From: \(original.from?.description ?? "")",
            "Date: \(RFC2822Date.string(original.date, zone: zone))",
            "Subject: \(original.subject)",
            "To: \(original.to.map(\.description).joined(separator: ", "))",
        ] + (original.cc.isEmpty ? [] : ["Cc: \(original.cc.map(\.description).joined(separator: ", "))"])
        let forwardedHTML = original.html ?? HTMLSanitizer.plainTextToHTML(original.plainBody)
        return OutgoingMessage(
            from: account, to: to, subject: forwardSubject(original.subject),
            html: html.map { "\($0)<br><br><div class=\"gmail_quote\">\(headerLines.map(HTMLSanitizer.escape).joined(separator: "<br>"))<br><br>\(forwardedHTML)</div>" },
            text: text + "\n\n" + headerLines.joined(separator: "\n") + "\n\n" + original.plainBody,
            references: original.messageIDHeader.map { original.references + [$0] } ?? original.references,
            threadID: original.threadID, attachments: attachments)
    }

    /// "Thu, Sep 24 at 2:14 PM" (the design's attribution line).
    public static func attributionDate(_ date: Date, zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        return formatter.string(from: date)
    }
}
