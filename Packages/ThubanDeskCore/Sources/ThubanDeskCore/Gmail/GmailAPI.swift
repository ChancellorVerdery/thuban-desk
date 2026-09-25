import Foundation

/// Typed Gmail v1 requests (`users/me/…`). Sends (`messages.send`, `drafts.send`) are `.send` requests: the client's
/// `WriteGate` must allow sending, and the app only builds them from a confirmed `ConfirmWriteSheet`.
public enum GmailEndpoints {
    static var base: URL { GoogleEndpoints.gmail }

    public static func profile() -> GoogleRequest { .get(base, ["profile"]) }

    // MARK: Labels

    public static func labels() -> GoogleRequest { .get(base, ["labels"]) }
    public static func createLabel(_ label: NewLabel) -> GoogleRequest { .json("POST", base, ["labels"], body: label) }

    // MARK: Threads

    /// `labelIDs` are ANDed; `query` uses Gmail search syntax. Spam and Trash need `includeSpamTrash`.
    public static func threads(labelIDs: [String] = [], query: String? = nil, pageToken: String? = nil, maxResults: Int = 50,
                               includeSpamTrash: Bool = false) -> GoogleRequest {
        var items: [(String, String?)] = labelIDs.map { ("labelIds", $0) }
        items += [("q", query?.isEmpty == false ? query : nil), ("maxResults", String(maxResults)), ("pageToken", pageToken),
                  ("includeSpamTrash", includeSpamTrash ? "true" : nil)]
        return .get(base, ["threads"], query: items)
    }

    public enum Format: String, Sendable { case full, metadata, minimal }

    public static let metadataHeaders = ["From", "To", "Cc", "Subject", "Date", "Message-ID", "List-Id", "List-Unsubscribe", "Precedence", "Auto-Submitted", "Reply-To"]

    public static func thread(_ id: String, format: Format = .full) -> GoogleRequest {
        var query: [(String, String?)] = [("format", format.rawValue)]
        if format == .metadata { query += metadataHeaders.map { ("metadataHeaders", $0) } }
        return .get(base, ["threads", id], query: query)
    }

    /// Adds / removes labels on every message of a thread (archive = remove INBOX, read = remove UNREAD, star …).
    public static func modifyThread(_ id: String, add: [String] = [], remove: [String] = []) -> GoogleRequest {
        .json("POST", base, ["threads", id, "modify"], body: ModifyBody(addLabelIds: add, removeLabelIds: remove))
    }

    public static func trashThread(_ id: String) -> GoogleRequest { .bodiless("POST", base, ["threads", id, "trash"]) }
    public static func untrashThread(_ id: String) -> GoogleRequest { .bodiless("POST", base, ["threads", id, "untrash"]) }
    /// Permanent. Needs the full-mail scope; irreversible — confirm first.
    public static func deleteThread(_ id: String) -> GoogleRequest { .bodiless("DELETE", base, ["threads", id]) }

    // MARK: Messages

    public static func message(_ id: String, format: Format = .full) -> GoogleRequest {
        .get(base, ["messages", id], query: [("format", format.rawValue)])
    }

    public static func modifyMessages(_ ids: [String], add: [String] = [], remove: [String] = []) -> GoogleRequest {
        .json("POST", base, ["messages", "batchModify"], body: BatchModifyBody(ids: ids, addLabelIds: add, removeLabelIds: remove))
    }

    public static func attachment(messageID: String, attachmentID: String) -> GoogleRequest {
        .get(base, ["messages", messageID, "attachments", attachmentID])
    }

    /// Sends a message (the send path — confirm first; never called by tests or smoke).
    public static func send(_ message: OutgoingMessage, date: Date = Date()) -> GoogleRequest {
        .json("POST", base, ["messages", "send"], body: RawMessage(raw: MIMEBuilder.raw(message, date: date), threadId: message.threadID), kind: .send)
    }

    // MARK: Drafts

    public static func drafts(pageToken: String? = nil) -> GoogleRequest {
        .get(base, ["drafts"], query: [("maxResults", "100"), ("pageToken", pageToken)])
    }

    public static func createDraft(_ message: OutgoingMessage, date: Date = Date()) -> GoogleRequest {
        .json("POST", base, ["drafts"], body: DraftBody(id: nil, message: RawMessage(raw: MIMEBuilder.raw(message, date: date), threadId: message.threadID)))
    }

    public static func updateDraft(_ id: String, _ message: OutgoingMessage, date: Date = Date()) -> GoogleRequest {
        .json("PUT", base, ["drafts", id], body: DraftBody(id: id, message: RawMessage(raw: MIMEBuilder.raw(message, date: date), threadId: message.threadID)))
    }

    /// Sends a saved draft (the send path — confirm first).
    public static func sendDraft(_ id: String) -> GoogleRequest {
        .json("POST", base, ["drafts", "send"], body: DraftID(id: id), kind: .send)
    }

    public static func deleteDraft(_ id: String) -> GoogleRequest { .bodiless("DELETE", base, ["drafts", id]) }

    // MARK: Settings

    public static func filters() -> GoogleRequest { .get(base, ["settings", "filters"]) }
    public static func createFilter(_ filter: GmailFilter) -> GoogleRequest { .json("POST", base, ["settings", "filters"], body: filter) }
    public static func deleteFilter(_ id: String) -> GoogleRequest { .bodiless("DELETE", base, ["settings", "filters", id]) }
    public static func sendAs() -> GoogleRequest { .get(base, ["settings", "sendAs"]) }

    struct ModifyBody: Encodable { var addLabelIds: [String]; var removeLabelIds: [String] }
    struct BatchModifyBody: Encodable { var ids: [String]; var addLabelIds: [String]; var removeLabelIds: [String] }
    struct RawMessage: Encodable { var raw: String; var threadId: String? }
    struct DraftBody: Encodable { var id: String?; var message: RawMessage }
    struct DraftID: Encodable { var id: String }
}

/// One mailbox action on threads, as label changes (what the toolbar and bulk actions do).
public enum MailAction: Hashable, Sendable {
    case archive, moveToInbox
    case markRead, markUnread
    case star, unstar
    case spam, notSpam
    case trash, untrash
    case addLabel(String), removeLabel(String)

    /// Label ids to add / remove. Trash / untrash use their own endpoints (`nil`).
    public var labelChange: (add: [String], remove: [String])? {
        switch self {
        case .archive: return ([], [GmailSystemLabel.inbox])
        case .moveToInbox: return ([GmailSystemLabel.inbox], [])
        case .markRead: return ([], [GmailSystemLabel.unread])
        case .markUnread: return ([GmailSystemLabel.unread], [])
        case .star: return ([GmailSystemLabel.starred], [])
        case .unstar: return ([], [GmailSystemLabel.starred])
        case .spam: return ([GmailSystemLabel.spam], [GmailSystemLabel.inbox])
        case .notSpam: return ([GmailSystemLabel.inbox], [GmailSystemLabel.spam])
        case .addLabel(let id): return ([id], [])
        case .removeLabel(let id): return ([], [id])
        case .trash, .untrash: return nil
        }
    }

    public func request(threadID: String) -> GoogleRequest {
        switch self {
        case .trash: return GmailEndpoints.trashThread(threadID)
        case .untrash: return GmailEndpoints.untrashThread(threadID)
        default:
            let change = labelChange ?? ([], [])
            return GmailEndpoints.modifyThread(threadID, add: change.add, remove: change.remove)
        }
    }

    /// Applies the action to a local label set (optimistic UI update).
    public func apply(to labels: [String]) -> [String] {
        var set = Set(labels)
        switch self {
        case .trash: set.insert(GmailSystemLabel.trash); set.remove(GmailSystemLabel.inbox)
        case .untrash: set.remove(GmailSystemLabel.trash); set.insert(GmailSystemLabel.inbox)
        default:
            if let change = labelChange {
                set.subtract(change.remove)
                set.formUnion(change.add)
            }
        }
        return set.sorted()
    }
}

extension GoogleClient {
    public func gmailProfile() async throws -> GmailProfile { try await decode(GmailProfile.self, GmailEndpoints.profile()) }

    public func labels() async throws -> [GmailLabel] { try await decode(GmailLabelList.self, GmailEndpoints.labels()).labels ?? [] }

    public func createLabel(named name: String) async throws -> GmailLabel {
        try await decode(GmailLabel.self, GmailEndpoints.createLabel(NewLabel(name: name)))
    }

    /// Thread ids (+ snippets) for a label set / query, up to `limit`.
    public func threadRefs(labelIDs: [String] = [], query: String? = nil, limit: Int = 50, includeSpamTrash: Bool = false) async throws -> [GmailThreadRef] {
        try await paginate(GmailThreadList.self, limit: limit) {
            GmailEndpoints.threads(labelIDs: labelIDs, query: query, pageToken: $0, maxResults: min(100, limit), includeSpamTrash: includeSpamTrash)
        }
    }

    public func thread(_ id: String, format: GmailEndpoints.Format = .full) async throws -> MailThread {
        MailThread(account: accountID, try await decode(GmailThread.self, GmailEndpoints.thread(id, format: format)))
    }

    /// Row models for thread ids, fetched with `format=metadata`, at most `concurrency` at a time, in input order.
    /// Threads that vanished meanwhile (404) are skipped.
    public func threadSummaries(ids: [String], concurrency: Int = 8) async throws -> [ThreadSummary] {
        var results: [Int: ThreadSummary] = [:]
        var index = 0
        try await withThrowingTaskGroup(of: (Int, ThreadSummary?).self) { group in
            func addNext() {
                guard index < ids.count else { return }
                let position = index, id = ids[index]
                index += 1
                group.addTask {
                    do { return (position, try await self.thread(id, format: .metadata).summary) } catch let error as ThubanError where error.isNotFound {
                        return (position, nil)
                    }
                }
            }
            for _ in 0..<max(1, concurrency) { addNext() }
            while let (position, summary) = try await group.next() {
                results[position] = summary
                addNext()
            }
        }
        return (0..<ids.count).compactMap { results[$0] }
    }

    /// One page of a folder as summaries.
    public func threadSummaries(labelIDs: [String] = [], query: String? = nil, limit: Int = 50, includeSpamTrash: Bool = false) async throws -> [ThreadSummary] {
        let refs = try await threadRefs(labelIDs: labelIDs, query: query, limit: limit, includeSpamTrash: includeSpamTrash)
        return try await threadSummaries(ids: refs.map(\.id))
    }

    public func perform(_ action: MailAction, threadID: String) async throws {
        try await data(action.request(threadID: threadID))
    }

    /// Permanently deletes a thread (irreversible; confirm first).
    public func deleteThreadForever(_ id: String) async throws { try await data(GmailEndpoints.deleteThread(id)) }

    /// "Empty trash": permanently deletes every thread in Trash (irreversible; confirm first). Returns the count.
    @discardableResult
    public func emptyTrash() async throws -> Int {
        let refs = try await threadRefs(labelIDs: [GmailSystemLabel.trash], limit: 5000, includeSpamTrash: true)
        for ref in refs { try await deleteThreadForever(ref.id) }
        return refs.count
    }

    public func attachmentData(messageID: String, attachmentID: String) async throws -> Data {
        let body = try await decode(GmailAttachmentBody.self, GmailEndpoints.attachment(messageID: messageID, attachmentID: attachmentID))
        return body.data.flatMap(Base64URL.decode) ?? Data()
    }

    // MARK: Compose

    /// Sends. The send path: only ever called from a confirmed ConfirmWriteSheet.
    @discardableResult
    public func send(_ message: OutgoingMessage) async throws -> GmailMessage {
        if let draftID = message.draftID {
            return try await decode(GmailMessage.self, GmailEndpoints.sendDraft(draftID))
        }
        return try await decode(GmailMessage.self, GmailEndpoints.send(message))
    }

    /// Saves (creates or updates) a draft; returns the draft id.
    @discardableResult
    public func saveDraft(_ message: OutgoingMessage) async throws -> GmailDraft {
        if let id = message.draftID { return try await decode(GmailDraft.self, GmailEndpoints.updateDraft(id, message)) }
        return try await decode(GmailDraft.self, GmailEndpoints.createDraft(message))
    }

    public func deleteDraft(_ id: String) async throws { try await data(GmailEndpoints.deleteDraft(id)) }

    public func drafts() async throws -> [GmailDraft] {
        try await paginate(GmailDraftList.self) { GmailEndpoints.drafts(pageToken: $0) }
    }

    // MARK: Settings

    public func filters() async throws -> [GmailFilter] { try await decode(GmailFilterList.self, GmailEndpoints.filters()).filter ?? [] }

    @discardableResult
    public func createFilter(_ filter: GmailFilter) async throws -> GmailFilter {
        try await decode(GmailFilter.self, GmailEndpoints.createFilter(filter))
    }

    public func deleteFilter(_ id: String) async throws { try await data(GmailEndpoints.deleteFilter(id)) }

    public func sendAs() async throws -> [GmailSendAs] { try await decode(GmailSendAsList.self, GmailEndpoints.sendAs()).sendAs ?? [] }
}
