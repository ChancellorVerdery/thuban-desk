import Foundation

// MARK: - API payloads (Gmail v1 JSON)

public struct GmailLabel: Codable, Hashable, Sendable, Identifiable {
    public struct Color: Codable, Hashable, Sendable {
        public var textColor: String?
        public var backgroundColor: String?
        public init(textColor: String? = nil, backgroundColor: String? = nil) {
            self.textColor = textColor
            self.backgroundColor = backgroundColor
        }
    }

    public var id: String
    public var name: String
    /// "system" or "user".
    public var type: String?
    public var messageListVisibility: String?
    public var labelListVisibility: String?
    public var messagesTotal: Int?
    public var messagesUnread: Int?
    public var threadsTotal: Int?
    public var threadsUnread: Int?
    public var color: Color?

    public init(id: String, name: String, type: String? = "user", threadsUnread: Int? = nil, color: Color? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.threadsUnread = threadsUnread
        self.color = color
    }

    public var isUser: Bool { type == "user" }
    /// Colour role for the label chip (the theme's roles, never Google's hex).
    public var tint: CalendarTint { CalendarTint.from(googleHex: color?.backgroundColor) }
}

public struct GmailLabelList: Decodable, Sendable { public var labels: [GmailLabel]? }

/// Body for `labels.create`.
public struct NewLabel: Codable, Hashable, Sendable {
    public var name: String
    public var labelListVisibility: String = "labelShow"
    public var messageListVisibility: String = "show"
    public var color: GmailLabel.Color?
    public init(name: String, color: GmailLabel.Color? = nil) {
        self.name = name
        self.color = color
    }
}

public struct GmailMessagePart: Codable, Hashable, Sendable {
    public struct Body: Codable, Hashable, Sendable {
        public var attachmentId: String?
        public var size: Int?
        /// base64url.
        public var data: String?
        public init(attachmentId: String? = nil, size: Int? = nil, data: String? = nil) {
            self.attachmentId = attachmentId
            self.size = size
            self.data = data
        }
    }

    public var partId: String?
    public var mimeType: String?
    public var filename: String?
    public var headers: [MIMEHeader]?
    public var body: Body?
    public var parts: [GmailMessagePart]?

    public init(partId: String? = nil, mimeType: String? = nil, filename: String? = nil, headers: [MIMEHeader]? = nil, body: Body? = nil, parts: [GmailMessagePart]? = nil) {
        self.partId = partId
        self.mimeType = mimeType
        self.filename = filename
        self.headers = headers
        self.body = body
        self.parts = parts
    }

    /// The domain MIME tree (bodies base64url-decoded).
    public var mime: MIMEPart {
        var headers = self.headers ?? []
        if !headers.contains(where: { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }), let mimeType {
            headers.append(MIMEHeader(name: "Content-Type", value: mimeType))
        }
        let data = body?.data.flatMap(Base64URL.decode) ?? Data()
        return MIMEPart(headers: headers, body: data, parts: (parts ?? []).map(\.mime), partID: partId,
                        attachmentID: body?.attachmentId, size: body?.size ?? data.count)
    }

    /// Gmail's JSON shape for a MIME tree (fixtures). Bodies over `inlineLimit` bytes get an attachment id instead.
    public init(mime: MIMEPart, partID: String = "", inlineLimit: Int = .max) {
        partId = partID
        mimeType = mime.mimeType
        filename = mime.filename ?? ""
        headers = mime.headers
        if mime.isMultipart {
            body = Body(size: 0)
            parts = mime.parts.enumerated().map { index, child in
                GmailMessagePart(mime: child, partID: partID.isEmpty ? String(index) : "\(partID).\(index)", inlineLimit: inlineLimit)
            }
        } else if mime.body.count > inlineLimit || mime.attachmentID != nil {
            body = Body(attachmentId: mime.attachmentID ?? "att-\(partID)", size: mime.body.count)
        } else {
            body = Body(size: mime.body.count, data: Base64URL.encode(mime.body))
        }
    }
}

public struct GmailMessage: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var threadId: String?
    public var labelIds: [String]?
    public var snippet: String?
    public var historyId: String?
    /// Milliseconds since 1970, as a string.
    public var internalDate: String?
    public var payload: GmailMessagePart?
    public var sizeEstimate: Int?
    /// base64url RFC 2822 (format=raw, or when sending).
    public var raw: String?

    public init(id: String, threadId: String? = nil, labelIds: [String]? = nil, snippet: String? = nil, internalDate: String? = nil,
                payload: GmailMessagePart? = nil, raw: String? = nil) {
        self.id = id
        self.threadId = threadId
        self.labelIds = labelIds
        self.snippet = snippet
        self.internalDate = internalDate
        self.payload = payload
        self.raw = raw
    }

    public var date: Date? { internalDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) } }
}

public struct GmailThreadRef: Codable, Hashable, Sendable {
    public var id: String
    public var snippet: String?
    public var historyId: String?
}

public struct GmailThreadList: GooglePage {
    public var threads: [GmailThreadRef]?
    public var nextPageToken: String?
    public var resultSizeEstimate: Int?
    public var pageItems: [GmailThreadRef] { threads ?? [] }
}

public struct GmailThread: Codable, Hashable, Sendable {
    public var id: String
    public var historyId: String?
    public var snippet: String?
    public var messages: [GmailMessage]?
}

public struct GmailDraft: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var message: GmailMessage?
}

public struct GmailDraftList: GooglePage {
    public var drafts: [GmailDraft]?
    public var nextPageToken: String?
    public var pageItems: [GmailDraft] { drafts ?? [] }
}

public struct GmailFilter: Codable, Hashable, Sendable, Identifiable {
    public struct Criteria: Codable, Hashable, Sendable {
        public var from: String?
        public var to: String?
        public var subject: String?
        public var query: String?
        public var negatedQuery: String?
        public var hasAttachment: Bool?
        public init(from: String? = nil, to: String? = nil, subject: String? = nil, query: String? = nil) {
            self.from = from
            self.to = to
            self.subject = subject
            self.query = query
        }
    }

    public struct Action: Codable, Hashable, Sendable {
        public var addLabelIds: [String]?
        public var removeLabelIds: [String]?
        public var forward: String?
        public init(addLabelIds: [String]? = nil, removeLabelIds: [String]? = nil) {
            self.addLabelIds = addLabelIds
            self.removeLabelIds = removeLabelIds
        }
    }

    public var id: String?
    public var criteria: Criteria?
    public var action: Action?

    public init(id: String? = nil, criteria: Criteria, action: Action) {
        self.id = id
        self.criteria = criteria
        self.action = action
    }

    /// "From maya@… → add label, skip inbox" (the design's filter from a sender).
    public static func fromSender(_ email: String, addLabelID: String?, skipInbox: Bool) -> GmailFilter {
        GmailFilter(criteria: Criteria(from: email),
                    action: Action(addLabelIds: addLabelID.map { [$0] }, removeLabelIds: skipInbox ? [GmailSystemLabel.inbox] : nil))
    }
}

public struct GmailFilterList: Decodable, Sendable { public var filter: [GmailFilter]? }

public struct GmailProfile: Codable, Hashable, Sendable {
    public var emailAddress: String
    public var messagesTotal: Int?
    public var threadsTotal: Int?
    public var historyId: String?
}

/// `settings/sendAs` entry (display name and signature for the From line).
public struct GmailSendAs: Codable, Hashable, Sendable {
    public var sendAsEmail: String
    public var displayName: String?
    public var signature: String?
    public var isDefault: Bool?
    public var isPrimary: Bool?
}

public struct GmailSendAsList: Decodable, Sendable { public var sendAs: [GmailSendAs]? }

public struct GmailAttachmentBody: Decodable, Sendable {
    public var size: Int?
    public var data: String?
}

public enum GmailSystemLabel {
    public static let inbox = "INBOX"
    public static let unread = "UNREAD"
    public static let starred = "STARRED"
    public static let important = "IMPORTANT"
    public static let sent = "SENT"
    public static let draft = "DRAFT"
    public static let spam = "SPAM"
    public static let trash = "TRASH"
    public static let categoryPersonal = "CATEGORY_PERSONAL"
    public static let categorySocial = "CATEGORY_SOCIAL"
    public static let categoryPromotions = "CATEGORY_PROMOTIONS"
    public static let categoryUpdates = "CATEGORY_UPDATES"
    public static let categoryForums = "CATEGORY_FORUMS"
}

// MARK: - Domain

/// A message ready to show: decoded headers, best bodies, attachments.
public struct MailMessage: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var threadID: String
    public var labelIDs: [String]
    public var snippet: String
    public var date: Date
    public var from: EmailAddress?
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var bcc: [EmailAddress]
    public var replyTo: [EmailAddress]
    public var subject: String
    /// `Message-ID` header (with angle brackets) — used for In-Reply-To / References.
    public var messageIDHeader: String?
    public var references: [String]
    public var html: String?
    public var text: String?
    public var attachments: [MailAttachment]
    /// Headers used by the NeedsReply classifier and the "notification" heuristics (List-Id, List-Unsubscribe,
    /// Precedence, Auto-Submitted, …) — lower-cased names.
    public var extraHeaders: [String: String]

    public init(id: String, threadID: String, labelIDs: [String] = [], snippet: String = "", date: Date, from: EmailAddress?, to: [EmailAddress] = [],
                cc: [EmailAddress] = [], bcc: [EmailAddress] = [], replyTo: [EmailAddress] = [], subject: String = "", messageIDHeader: String? = nil,
                references: [String] = [], html: String? = nil, text: String? = nil, attachments: [MailAttachment] = [], extraHeaders: [String: String] = [:]) {
        self.id = id
        self.threadID = threadID
        self.labelIDs = labelIDs
        self.snippet = snippet
        self.date = date
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.replyTo = replyTo
        self.subject = subject
        self.messageIDHeader = messageIDHeader
        self.references = references
        self.html = html
        self.text = text
        self.attachments = attachments
        self.extraHeaders = extraHeaders
    }

    static let keptHeaders = ["list-id", "list-unsubscribe", "precedence", "auto-submitted", "x-auto-response-suppress", "x-mailer", "return-path", "sender"]

    /// Builds from a `format=full` (or `metadata`) message.
    public init(_ message: GmailMessage) {
        let root = message.payload?.mime ?? MIMEPart(headers: [])
        let content = message.payload?.body != nil || message.payload?.parts != nil ? MIMEContent.extract(root) : MIMEContent()
        let dateHeader = root.header("Date").flatMap(RFC2822Date.parse)
        var extras: [String: String] = [:]
        for header in root.headers where Self.keptHeaders.contains(header.name.lowercased()) { extras[header.name.lowercased()] = header.value }
        self.init(
            id: message.id,
            threadID: message.threadId ?? message.id,
            labelIDs: message.labelIds ?? [],
            snippet: Self.decodeEntities(message.snippet ?? ""),
            date: message.date ?? dateHeader ?? Date(timeIntervalSince1970: 0),
            from: EmailAddress.parseList(root.header("From")).first,
            to: EmailAddress.parseList(root.header("To")),
            cc: EmailAddress.parseList(root.header("Cc")),
            bcc: EmailAddress.parseList(root.header("Bcc")),
            replyTo: EmailAddress.parseList(root.header("Reply-To")),
            subject: root.decodedHeader("Subject") ?? "",
            messageIDHeader: root.header("Message-ID") ?? root.header("Message-Id"),
            references: (root.header("References") ?? "").split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init),
            html: content.html,
            text: content.text,
            attachments: content.attachments,
            extraHeaders: extras)
    }

    public var isUnread: Bool { labelIDs.contains(GmailSystemLabel.unread) }
    public var isStarred: Bool { labelIDs.contains(GmailSystemLabel.starred) }
    public var isDraft: Bool { labelIDs.contains(GmailSystemLabel.draft) }
    public var isSent: Bool { labelIDs.contains(GmailSystemLabel.sent) }
    public var hasAttachments: Bool { attachments.contains { !$0.isInline } }
    /// Best body as plain text (HTML converted when there is no text part).
    public var plainBody: String { text ?? HTMLSanitizer.plainText(html) }

    /// Gmail snippets arrive HTML-escaped.
    static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// A conversation in one account.
public struct MailThread: Codable, Hashable, Sendable, Identifiable {
    public var account: String
    public var id: String
    public var messages: [MailMessage]
    public var historyID: String?

    public init(account: String, id: String, messages: [MailMessage], historyID: String? = nil) {
        self.account = account.lowercased()
        self.id = id
        self.messages = messages.sorted { $0.date < $1.date }
        self.historyID = historyID
    }

    public init(account: String, _ thread: GmailThread) {
        self.init(account: account, id: thread.id, messages: (thread.messages ?? []).map(MailMessage.init), historyID: thread.historyId)
    }

    public var key: ThreadKey { ThreadKey(account: account, threadID: id) }
    public var subject: String { messages.first(where: { !$0.subject.isEmpty })?.subject ?? "(no subject)" }
    public var lastMessage: MailMessage? { messages.last }
    public var labelIDs: Set<String> { Set(messages.flatMap(\.labelIDs)) }
    public var isUnread: Bool { messages.contains(where: \.isUnread) }
    public var isStarred: Bool { messages.contains(where: \.isStarred) }

    /// The row model for lists.
    public var summary: ThreadSummary {
        let last = messages.last(where: { !$0.isDraft }) ?? messages.last
        let latestFromOthers = messages.last(where: { !$0.isSent && !$0.isDraft })
        return ThreadSummary(
            account: account, id: id, subject: subject, snippet: last?.snippet ?? "",
            from: latestFromOthers?.from ?? last?.from, date: last?.date ?? Date(timeIntervalSince1970: 0),
            messageCount: messages.filter { !$0.isDraft }.count, labelIDs: Array(labelIDs).sorted(),
            hasAttachments: messages.contains(where: \.hasAttachments),
            participants: Self.participants(messages))
    }

    static func participants(_ messages: [MailMessage]) -> [EmailAddress] {
        var seen = Set<String>()
        return messages.compactMap(\.from).filter { seen.insert($0.normalized).inserted }
    }
}

/// One row of a thread list (from `format=metadata`, or derived from a full thread).
public struct ThreadSummary: Codable, Hashable, Sendable, Identifiable {
    public var account: String
    public var id: String
    public var subject: String
    public var snippet: String
    /// The latest sender who is not the user (falls back to the last sender).
    public var from: EmailAddress?
    public var date: Date
    public var messageCount: Int
    public var labelIDs: [String]
    public var hasAttachments: Bool
    public var participants: [EmailAddress]

    public init(account: String, id: String, subject: String, snippet: String, from: EmailAddress?, date: Date, messageCount: Int,
                labelIDs: [String], hasAttachments: Bool = false, participants: [EmailAddress] = []) {
        self.account = account.lowercased()
        self.id = id
        self.subject = subject
        self.snippet = snippet
        self.from = from
        self.date = date
        self.messageCount = messageCount
        self.labelIDs = labelIDs
        self.hasAttachments = hasAttachments
        self.participants = participants
    }

    public var key: ThreadKey { ThreadKey(account: account, threadID: id) }
    public var isUnread: Bool { labelIDs.contains(GmailSystemLabel.unread) }
    public var isStarred: Bool { labelIDs.contains(GmailSystemLabel.starred) }
    public var isInInbox: Bool { labelIDs.contains(GmailSystemLabel.inbox) }
    /// "gmail.com" — the account tag rows show in All inboxes.
    public var accountDomain: String { String(account.split(separator: "@").last ?? Substring(account)) }
}

// MARK: - Dates in headers

public enum RFC2822Date {
    static let formats = ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z", "EEE, d MMM yyyy HH:mm:ss zzz", "EEE, d MMM yy HH:mm:ss Z"]

    public static func parse(_ text: String) -> Date? {
        // Drop trailing comments like "(UTC)".
        var value = text.trimmingCharacters(in: .whitespaces)
        if let paren = value.firstIndex(of: "(") { value = value[..<paren].trimmingCharacters(in: .whitespaces) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    /// `Thu, 24 Sep 2026 14:41:00 -0400`.
    public static func string(_ date: Date, zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}
