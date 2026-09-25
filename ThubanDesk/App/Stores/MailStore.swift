import Foundation
import Observation
import ThubanDeskCore

/// The list filter chips above the thread list (design: All / Unread / Needs reply).
enum MailListFilter: String, CaseIterable, Identifiable {
    case all, unread, needsReply
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .unread: return "Unread"
        case .needsReply: return "Needs reply"
        }
    }
}

/// Mail for every linked account: labels (merged by name), the current mailbox list (All inboxes merges accounts
/// by date), thread details, pins (local), optimistic mailbox actions, labels / filters, drafts, and the send path
/// (confirmed only). Views read `threads`, `visibleThreads`, `thread(_:)`, `mergedLabels`, `unreadCount`.
@MainActor
@Observable
final class MailStore {
    @ObservationIgnored weak var app: AppModel!

    var scope = MailScope() {
        didSet {
            guard scope != oldValue else { return }
            app?.settings.lastMailFolder = scope.folder.storageKey
            checked = []
            if !suppressReload { Task { await loadList() } }
        }
    }
    var filter: MailListFilter = .all
    /// Gmail search (`q=`) applied to the list; empty = none.
    var searchQuery = "" {
        didSet { if searchQuery != oldValue { Task { await loadList(force: true) } } }
    }

    private(set) var labels: [String: [GmailLabel]] = [:]
    private(set) var threads: [ThreadSummary] = []
    private(set) var isLoadingList = false
    private(set) var listError: String?
    private(set) var accountErrors: [String: String] = [:]
    /// Full threads fetched for the reader (and for NeedsReply).
    private(set) var details: [ThreadKey: MailThread] = [:]
    /// "Needs a reply" verdicts for inbox threads (computed by `loadNeedsReply`).
    private(set) var needsReply: [ThreadKey: NeedsReply.Verdict] = [:]
    /// Filters per account (Settings → Filters and "2 filters active").
    private(set) var filters: [String: [GmailFilter]] = [:]
    /// Display name + signature per account (`settings/sendAs`).
    private(set) var sendAs: [String: GmailSendAs] = [:]

    /// The open thread (reader pane).
    var selection: ThreadKey?
    /// Multi-select for bulk actions.
    var checked: Set<ThreadKey> = []

    // MARK: UI state (Mail area)

    /// The open Compose window (nil = closed). See `ComposeModel`.
    var compose: ComposeModel?
    /// Threads whose remote images the user allowed this session ("Load images").
    var imagesAllowed: Set<ThreadKey> = []
    /// Earlier messages the user expanded in the reader (message ids).
    var expandedMessages: Set<String> = []
    /// Set after the first list load finished (empty states wait for it).
    private(set) var hasLoadedList = false

    // MARK: Derived

    var accountOrder: [String] { app?.accounts.map(\.id) ?? [] }
    var mergedLabels: [MergedLabel] { MailMerge.mergeLabels(labels, accountOrder: accountOrder) }

    /// Unread inbox threads across accounts (title-bar badge, sidebar).
    var unreadCount: Int { accountOrder.reduce(0) { $0 + unreadInbox(account: $1) } }

    func unreadInbox(account: String) -> Int {
        labels[account]?.first { $0.id == GmailSystemLabel.inbox }?.threadsUnread ?? 0
    }

    /// `threads` after the list filter chip.
    var visibleThreads: [ThreadSummary] {
        switch filter {
        case .all: return threads
        case .unread: return threads.filter(\.isUnread)
        case .needsReply: return threads.filter { needsReply[$0.key]?.needsReply == true }
        }
    }

    /// Threads that need a reply, newest first (Today and the Needs reply chip).
    var needsReplyThreads: [(summary: ThreadSummary, verdict: NeedsReply.Verdict)] {
        details.values.compactMap { thread in
            guard let verdict = needsReply[thread.key], verdict.needsReply,
                  !(app?.settings.dismissedNeedsReply.contains(thread.key.description) ?? false) else { return nil }
            return (thread.summary, verdict)
        }.sorted { $0.summary.date > $1.summary.date }
    }

    func isPinned(_ key: ThreadKey) -> Bool { app?.settings.isPinned(key) ?? false }

    func setPinned(_ pinned: Bool, _ key: ThreadKey) {
        app.settings.setPinned(pinned, key)
        if scope.folder == .pinned { Task { await loadList(force: true) } }
    }

    /// User label names on a thread (row chips).
    func labelNames(for summary: ThreadSummary) -> [String] {
        MailMerge.userLabelNames(summary.labelIDs, labels: labels[summary.account] ?? [])
    }

    /// The From address for an account (display name from sendAs, else the account's name).
    func fromAddress(for account: String) -> EmailAddress {
        let id = account.lowercased()
        let name = sendAs[id]?.displayName ?? app.credentials.account(id)?.displayName
        return EmailAddress(sendAs[id]?.sendAsEmail ?? id, name: name)
    }

    /// Account new mail is sent from (Settings default, else primary).
    var defaultSendAccount: String? {
        if let chosen = app.settings.defaultSendAccount, app.credentials.account(chosen) != nil { return chosen.lowercased() }
        return app.primaryAccount?.id
    }

    var activeFilterCount: Int { filters.values.reduce(0) { $0 + $1.count } }

    // MARK: Loading

    @ObservationIgnored private var suppressReload = false
    @ObservationIgnored private var restoredFolder = false

    /// Labels, the current list, filters and the NeedsReply scan. The first refresh reopens the last folder.
    func refresh() async {
        if !restoredFolder {
            restoredFolder = true
            if let stored = app?.settings.lastMailFolder, let folder = MailFolder(storageKey: stored), folder != scope.folder {
                suppressReload = true
                scope = MailScope(folder: folder)
                suppressReload = false
            }
        }
        await loadLabels()
        await loadList(force: true)
        await loadNeedsReply()
        await loadSettings()
    }

    func loadLabels() async {
        guard let app else { return }
        await withTaskGroup(of: (String, Result<[GmailLabel], Error>)?.self) { group in
            for account in app.activeAccounts {
                guard let client = app.client(for: account.id) else { continue }
                group.addTask {
                    do { return (account.id, .success(try await client.labels())) } catch { return (account.id, .failure(error)) }
                }
            }
            for await item in group {
                guard let (account, result) = item else { continue }
                switch result {
                case .success(let list): labels[account] = list; accountErrors[account] = nil
                case .failure(let error): accountErrors[account] = error.localizedDescription
                }
            }
        }
    }

    /// Loads the current scope (cache first). All inboxes queries every account and merges by date.
    func loadList(force: Bool = false) async {
        guard let app else { return }
        let scope = self.scope
        let query = searchQuery
        let cacheKey = "mail|\(scope.folder.storageKey)|\(scope.account ?? "all")|\(query)"
        if threads.isEmpty || !force, let entry = await app.cache.entry(for: cacheKey),
           let cached = try? GoogleJSON.decoder.decode([ThreadSummary].self, from: entry.data), self.scope == scope {
            threads = cached
        }
        isLoadingList = true
        defer { isLoadingList = false }
        let accounts = app.activeAccounts.map(\.id).filter { scope.account == nil || $0 == scope.account }
        var lists: [[ThreadSummary]] = []
        var failures: [String] = []
        for account in accounts {
            guard let client = app.client(for: account) else { continue }
            do {
                if scope.folder == .pinned {
                    let ids = app.settings.pins[account] ?? []
                    lists.append(try await client.threadSummaries(ids: ids))
                } else if let listing = scope.folder.listing(labels: labels[account] ?? [], search: query) {
                    lists.append(try await client.threadSummaries(labelIDs: listing.labelIDs, query: listing.query, limit: 50,
                                                                  includeSpamTrash: listing.includeSpamTrash))
                }
                accountErrors[account] = nil
            } catch {
                accountErrors[account] = error.localizedDescription
                failures.append(error.localizedDescription)
            }
        }
        guard self.scope == scope, searchQuery == query else { return }
        if failures.count < max(1, accounts.count) || accounts.isEmpty {
            threads = MailMerge.merge(lists)
            listError = failures.first
            if let data = try? GoogleJSON.cacheEncoder.encode(threads) { await app.cache.store(data, for: cacheKey) }
        } else {
            listError = failures.first
        }
        hasLoadedList = true
    }

    /// The full thread (cached after the first fetch).
    func thread(_ key: ThreadKey, force: Bool = false) async throws -> MailThread {
        if !force, let cached = details[key] { return cached }
        guard let client = app.client(for: key.account) else { throw ThubanError.notSignedIn(key.account) }
        let thread = try await client.thread(key.threadID)
        details[key] = thread
        return thread
    }

    /// Opens a thread in the reader and marks it read (reversible, runs immediately like Gmail). `markRead: false`
    /// previews without changing anything.
    func open(_ key: ThreadKey, markRead: Bool = true) async {
        if selection != key { expandedMessages = [] }
        selection = key
        _ = try? await thread(key)
        if markRead, threads.first(where: { $0.key == key })?.isUnread == true {
            await perform(.markRead, on: [key])
        }
    }

    /// Scans inbox threads for "needs a reply" (fetches full threads; Today and the Mail chip use it).
    func loadNeedsReply() async {
        guard let app else { return }
        let own = app.ownAddresses
        let now = app.now()
        for account in app.activeAccounts.map(\.id) {
            guard let client = app.client(for: account) else { continue }
            guard let refs = try? await client.threadRefs(labelIDs: [GmailSystemLabel.inbox], query: "newer_than:7d", limit: 40) else { continue }
            for ref in refs {
                let key = ThreadKey(account: account, threadID: ref.id)
                guard let thread = try? await self.thread(key) else { continue }
                needsReply[key] = NeedsReply.classify(thread, ownAddresses: own, now: now)
            }
        }
    }

    func loadSettings() async {
        guard let app else { return }
        for account in app.activeAccounts.map(\.id) {
            guard let client = app.client(for: account) else { continue }
            if let list = try? await client.filters() { filters[account] = list }
            if let identities = try? await client.sendAs() {
                sendAs[account] = identities.first { $0.isDefault == true } ?? identities.first { $0.isPrimary == true } ?? identities.first
            }
        }
    }

    func forget(account: String) {
        let id = account.lowercased()
        labels[id] = nil
        filters[id] = nil
        sendAs[id] = nil
        threads.removeAll { $0.account == id }
        details = details.filter { $0.key.account != id }
        needsReply = needsReply.filter { $0.key.account != id }
        if selection?.account == id { selection = nil }
    }

    // MARK: Mailbox actions (reversible — run immediately, optimistic)

    /// Archive, read/unread, star, spam, trash … on one or many threads (bulk). Updates rows at once and
    /// reverts them if Google refuses.
    func perform(_ action: MailAction, on keys: [ThreadKey]) async {
        let before = threads
        for key in keys { applyLocally(action, key) }
        var failed = false
        for key in keys {
            guard let client = app.client(for: key.account) else { continue }
            do { try await client.perform(action, threadID: key.threadID) } catch {
                failed = true
                listError = error.localizedDescription
            }
        }
        if failed { threads = before }
        await loadLabels()
    }

    private func applyLocally(_ action: MailAction, _ key: ThreadKey) {
        guard let index = threads.firstIndex(where: { $0.key == key }) else { return }
        threads[index].labelIDs = action.apply(to: threads[index].labelIDs)
        if leavesScope(threads[index]) {
            threads.remove(at: index)
            if selection == key { selection = nil }
            checked.remove(key)
        }
        if var detail = details[key] {
            detail.messages = detail.messages.map { message in
                var copy = message
                copy.labelIDs = action.apply(to: message.labelIDs)
                return copy
            }
            details[key] = detail
        }
    }

    /// True when a row no longer belongs in the current folder (archived out of Inbox, trashed, …).
    private func leavesScope(_ summary: ThreadSummary) -> Bool {
        let labels = Set(summary.labelIDs)
        switch scope.folder {
        case .inbox: return !labels.contains(GmailSystemLabel.inbox)
        case .starred: return !labels.contains(GmailSystemLabel.starred)
        case .spam: return !labels.contains(GmailSystemLabel.spam)
        case .trash: return !labels.contains(GmailSystemLabel.trash)
        default: return labels.contains(GmailSystemLabel.trash) || labels.contains(GmailSystemLabel.spam)
        }
    }

    /// Applies a user label by name to threads in any account (creating the label in an account that lacks it).
    func applyLabel(named name: String, to keys: [ThreadKey]) async throws {
        for (account, group) in Dictionary(grouping: keys, by: \.account) {
            let id = try await labelID(named: name, account: account)
            await perform(.addLabel(id), on: group)
        }
    }

    func removeLabel(named name: String, from keys: [ThreadKey]) async {
        for (account, group) in Dictionary(grouping: keys, by: \.account) {
            guard let id = labels[account]?.first(where: { $0.isUser && $0.name.caseInsensitiveCompare(name) == .orderedSame })?.id else { continue }
            await perform(.removeLabel(id), on: group)
        }
    }

    /// The account's label id for `name`, creating the label when missing.
    func labelID(named name: String, account: String) async throws -> String {
        if let existing = labels[account]?.first(where: { $0.isUser && $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return existing.id }
        guard let client = app.client(for: account) else { throw ThubanError.notSignedIn(account) }
        let created = try await client.createLabel(named: name)
        labels[account, default: []].append(created)
        return created.id
    }

    /// "Filter sender": future mail from `sender` gets `labelName` and/or skips the inbox (Gmail filter).
    func filterSender(_ sender: String, account: String, labelName: String?, skipInbox: Bool) async throws {
        guard let client = app.client(for: account) else { throw ThubanError.notSignedIn(account) }
        let labelID = try await labelName.asyncMap { try await self.labelID(named: $0, account: account) }
        let created = try await client.createFilter(.fromSender(sender, addLabelID: labelID, skipInbox: skipInbox))
        filters[account, default: []].append(created)
    }

    // MARK: Compose

    /// Saves (creates or updates) the Gmail draft; returns the message with its `draftID`. Autosave calls this.
    func saveDraft(_ message: OutgoingMessage, account: String) async throws -> OutgoingMessage {
        guard let client = app.client(for: account) else { throw ThubanError.notSignedIn(account) }
        let draft = try await client.saveDraft(message)
        var saved = message
        saved.draftID = draft.id
        return saved
    }

    func discardDraft(_ id: String, account: String) async throws {
        guard let client = app.client(for: account) else { throw ThubanError.notSignedIn(account) }
        try await client.deleteDraft(id)
    }

    /// THE SEND PATH. Only callable with a `Confirmed` from the ConfirmWriteSheet; never from tests or smoke.
    func send(_ message: OutgoingMessage, account: String, confirmed: Confirmed) async throws {
        guard let client = app.client(for: account) else { throw ThubanError.notSignedIn(account) }
        // drafts.send sends what is stored: bring the saved draft up to date first.
        if message.draftID != nil { _ = try await client.saveDraft(message) }
        try await client.send(message)
        if let thread = message.threadID { _ = try? await self.thread(ThreadKey(account: account, threadID: thread), force: true) }
        await loadList(force: true)
    }

    /// Permanently deletes threads (irreversible; confirmed).
    func deleteForever(_ keys: [ThreadKey], confirmed: Confirmed) async throws {
        for key in keys {
            guard let client = app.client(for: key.account) else { continue }
            try requirePermanentDelete(key.account)
            try await client.deleteThreadForever(key.threadID)
            threads.removeAll { $0.key == key }
            details[key] = nil
            if selection == key { selection = nil }
        }
        await loadLabels()
    }

    /// Permanent deletion needs the full-mail scope; an account linked before it was requested is told to sign in
    /// again instead of getting a bare 403 from Google.
    private func requirePermanentDelete(_ account: String) throws {
        guard let granted = app.credentials.account(account.lowercased())?.scopes,
              !GoogleScopes.allowsPermanentDelete(granted) else { return }
        throw ThubanError.http(status: 403, message: "Insufficient permissions", reason: "insufficientPermissions")
    }

    /// Empties Trash in one account or all (irreversible; confirmed). Returns how many threads were deleted.
    @discardableResult
    func emptyTrash(account: String?, confirmed: Confirmed) async throws -> Int {
        var total = 0
        for id in (account.map { [$0.lowercased()] } ?? accountOrder) {
            guard let client = app.client(for: id) else { continue }
            try requirePermanentDelete(id)
            total += try await client.emptyTrash()
        }
        await loadList(force: true)
        return total
    }

    /// Bytes of an attachment (inline data when present, else fetched).
    func attachmentData(_ attachment: MailAttachment, messageID: String, account: String) async throws -> Data {
        if let data = attachment.data { return data }
        guard let id = attachment.attachmentID, let client = app.client(for: account) else { throw ThubanError.notSignedIn(account) }
        return try await client.attachmentData(messageID: messageID, attachmentID: id)
    }

    /// Hides a thread from "Needs a reply" (Today's Done button); local only.
    func dismissNeedsReply(_ key: ThreadKey) {
        app.settings.dismissedNeedsReply.insert(key.description)
    }
}

extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}
