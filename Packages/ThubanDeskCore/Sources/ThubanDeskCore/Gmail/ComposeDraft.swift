import Foundation

/// The editable state of the Compose window, independent of the UI: who it is from, recipients, subject, body and
/// what it answers. `outgoing(…)` turns it into the `OutgoingMessage` that drafts and the (confirmed) send path use.
/// Replies and forwards are ALWAYS from the account the thread arrived in (`account` is fixed for them).
public struct ComposeDraft: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case new
        case reply(MailMessage, all: Bool)
        case forward(MailMessage)
    }

    public var kind: Kind
    /// The sending account (lower-cased address).
    public var account: String
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var bcc: [EmailAddress]
    public var subject: String
    /// Body the user wrote (HTML fragment and its plain-text twin), without the quoted original.
    public var html: String
    public var text: String
    public var attachments: [OutgoingAttachment]
    /// Gmail draft id once saved.
    public var draftID: String?

    public init(kind: Kind = .new, account: String, to: [EmailAddress] = [], cc: [EmailAddress] = [], bcc: [EmailAddress] = [],
                subject: String = "", html: String = "", text: String = "", attachments: [OutgoingAttachment] = [], draftID: String? = nil) {
        self.kind = kind
        self.account = account.lowercased()
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.html = html
        self.text = text
        self.attachments = attachments
        self.draftID = draftID
    }

    /// The message being answered or forwarded.
    public var original: MailMessage? {
        switch kind {
        case .new: return nil
        case .reply(let message, _), .forward(let message): return message
        }
    }

    public var isReply: Bool { if case .reply = kind { return true } else { return false } }
    public var isForward: Bool { if case .forward = kind { return true } else { return false } }
    /// Replies and forwards keep the thread's account; only new messages may pick one.
    public var canChangeAccount: Bool { original == nil }

    /// "Reply", "Reply all", "Forward", "New message".
    public var windowTitle: String {
        switch kind {
        case .new: return subject.isEmpty ? "New message" : subject
        case .reply(_, let all): return "\(all ? "Reply all" : "Reply") · \(Self.baseSubject(original?.subject ?? subject))"
        case .forward: return "Forward · \(Self.baseSubject(original?.subject ?? subject))"
        }
    }

    /// The subject without "Re:" / "Fwd:" prefixes ("Interview confirmed: Friday 3:00 PM").
    public static func baseSubject(_ subject: String) -> String {
        var text = subject.trimmingCharacters(in: .whitespaces)
        while let range = text.range(of: #"^(re|fwd?|fw)\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(range)
        }
        return text.isEmpty ? "(no subject)" : text
    }

    // MARK: Starting points

    /// A reply (or reply-all) to `original` from `account` (the account the thread arrived in).
    public static func reply(to original: MailMessage, account: EmailAddress, replyAll: Bool, ownAddresses: Set<String>) -> ComposeDraft {
        let base = MIMEBuilder.reply(to: original, from: account, replyAll: replyAll, html: nil, text: "", ownAddresses: ownAddresses)
        return ComposeDraft(kind: .reply(original, all: replyAll), account: account.email, to: base.to, cc: base.cc, subject: base.subject)
    }

    public static func forward(_ original: MailMessage, account: EmailAddress) -> ComposeDraft {
        ComposeDraft(kind: .forward(original), account: account.email, subject: MIMEBuilder.forwardSubject(original.subject))
    }

    // MARK: Output

    /// The message for drafts / send: the user's body plus the quoted original (reply) or forwarded message.
    public func outgoing(from address: EmailAddress, ownAddresses: Set<String> = [], zone: TimeZone = .current) -> OutgoingMessage {
        let bodyHTML = html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? HTMLSanitizer.plainTextToHTML(text) : html
        var message: OutgoingMessage
        switch kind {
        case .new:
            message = OutgoingMessage(from: address, subject: subject, html: bodyHTML, text: text)
        case .reply(let original, let all):
            message = MIMEBuilder.reply(to: original, from: address, replyAll: all, html: bodyHTML, text: text, ownAddresses: ownAddresses, zone: zone)
        case .forward(let original):
            message = MIMEBuilder.forward(original, from: address, to: to, html: bodyHTML, text: text, zone: zone)
        }
        message.from = address
        message.to = to
        message.cc = cc
        message.bcc = bcc
        message.subject = subject
        message.attachments = attachments
        message.draftID = draftID
        return message
    }

    /// Nothing typed and nothing attached (closing such a window leaves no draft).
    public var isEmpty: Bool {
        to.isEmpty && cc.isEmpty && bcc.isEmpty && attachments.isEmpty
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (original != nil || subject.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// Why Send is not possible yet (nil = ready).
    public var sendProblem: String? {
        let all = to + cc + bcc
        if all.isEmpty { return "Add at least one recipient." }
        if let bad = all.first(where: { !Self.isValidAddress($0.email) }) { return "“\(bad.email)” is not an email address." }
        return nil
    }

    // MARK: Recipients

    /// Parses what the user typed in a recipient field: `a@b.com, Name <c@d.org>; e@f`. Returns the addresses and any
    /// leftover text that is not an address yet.
    public static func parseRecipients(_ typed: String) -> (addresses: [EmailAddress], rest: String) {
        let parts = EmailAddress.parseList(typed)
        let valid = parts.filter { isValidAddress($0.email) }
        if valid.count == parts.count, !parts.isEmpty { return (valid, "") }
        if parts.isEmpty { return ([], typed.trimmingCharacters(in: .whitespaces)) }
        let invalid = parts.filter { !isValidAddress($0.email) }.map(\.email).joined(separator: ", ")
        return (valid, invalid)
    }

    public static func isValidAddress(_ email: String) -> Bool {
        let pieces = email.split(separator: "@", omittingEmptySubsequences: false)
        guard pieces.count == 2, !pieces[0].isEmpty, pieces[1].contains("."), !pieces[1].hasPrefix("."), !pieces[1].hasSuffix(".") else { return false }
        return !email.contains(where: { $0.isWhitespace || $0 == "<" || $0 == ">" || $0 == "," })
    }

    /// Adds addresses to a list, skipping duplicates (case-insensitive).
    public static func adding(_ new: [EmailAddress], to list: [EmailAddress]) -> [EmailAddress] {
        var seen = Set(list.map(\.normalized))
        return list + new.filter { seen.insert($0.normalized).inserted }
    }

    /// Contact suggestions for a partial entry: name or address contains `query` (case-insensitive), not already
    /// present, own addresses excluded; prefix matches first.
    public static func suggestions(_ query: String, contacts: [EmailAddress], excluding: [EmailAddress], own: Set<String>, limit: Int = 5) -> [EmailAddress] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let skip = Set(excluding.map(\.normalized)).union(own)
        var seen = Set<String>()
        let matches = contacts.filter { contact in
            !skip.contains(contact.normalized) && seen.insert(contact.normalized).inserted
                && (contact.normalized.contains(q) || (contact.name?.lowercased().contains(q) ?? false))
        }
        func rank(_ c: EmailAddress) -> Int {
            if c.normalized.hasPrefix(q) || (c.name?.lowercased().hasPrefix(q) ?? false) { return 0 }
            if c.name?.lowercased().split(separator: " ").contains(where: { $0.hasPrefix(q) }) ?? false { return 1 }
            return 2
        }
        return Array(matches.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element).prefix(limit))
    }

    // MARK: Quote

    /// The collapsed quote in the design: "On Thu, Sep 24 at 2:14 PM, Priya Shah wrote:" + a one-line excerpt.
    public static func quoteAttribution(_ original: MailMessage, zone: TimeZone = .current) -> String {
        "On \(MIMEBuilder.attributionDate(original.date, zone: zone)), \(original.from?.displayName ?? "someone") wrote:"
    }

    public static func quoteExcerpt(_ original: MailMessage, limit: Int = 80) -> String {
        let flat = original.plainBody.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard flat.count > limit else { return flat }
        let cut = flat.prefix(limit)
        let word = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return word.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:—-")) + "…"
    }
}

/// "2.4 MB", "820 KB", "12 bytes".
public enum ByteSize {
    public static func text(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) byte\(bytes == 1 ? "" : "s")" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return "\(Int(kb.rounded())) KB" }
        let mb = kb / 1024
        return mb < 10 ? String(format: "%.1f MB", mb) : "\(Int(mb.rounded())) MB"
    }

    /// Gmail's limit for a message's attachments.
    public static let gmailLimit = 25 * 1024 * 1024
}
