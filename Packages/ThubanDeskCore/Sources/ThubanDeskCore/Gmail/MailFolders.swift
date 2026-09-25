import Foundation

/// The mail sidebar's folders. `label` is a user label by NAME: labels with the same name in several accounts are
/// one folder (each account resolves the name to its own id).
public enum MailFolder: Hashable, Codable, Sendable, CustomStringConvertible {
    case inbox, pinned, starred, sent, drafts, archive, spam, trash
    case label(String)

    public static let system: [MailFolder] = [.inbox, .pinned, .starred, .sent, .drafts, .archive, .spam, .trash]

    public var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .pinned: return "Pinned"
        case .starred: return "Starred"
        case .sent: return "Sent"
        case .drafts: return "Drafts"
        case .archive: return "Archive"
        case .spam: return "Spam"
        case .trash: return "Trash"
        case .label(let name): return name
        }
    }

    /// Persisted form (`AppSettings.lastMailFolder`).
    public var storageKey: String {
        if case .label(let name) = self { return "label:" + name }
        return description
    }

    public init?(storageKey: String) {
        if storageKey.hasPrefix("label:") { self = .label(String(storageKey.dropFirst(6))); return }
        guard let folder = MailFolder.system.first(where: { $0.description == storageKey }) else { return nil }
        self = folder
    }

    public var description: String {
        switch self {
        case .label(let name): return "label:\(name)"
        default: return title.lowercased()
        }
    }

    /// How to list this folder in one account: label ids + query (+ spam/trash flag). `nil` for Pinned (local ids)
    /// and for a label the account does not have. `search` is ANDed in.
    public func listing(labels: [GmailLabel], search: String? = nil) -> (labelIDs: [String], query: String?, includeSpamTrash: Bool)? {
        let q = search?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        switch self {
        case .inbox: return ([GmailSystemLabel.inbox], q, false)
        case .starred: return ([GmailSystemLabel.starred], q, false)
        case .sent: return ([GmailSystemLabel.sent], q, false)
        case .drafts: return ([GmailSystemLabel.draft], q, false)
        case .spam: return ([GmailSystemLabel.spam], q, true)
        case .trash: return ([GmailSystemLabel.trash], q, true)
        case .archive:
            let base = "-in:inbox -in:spam -in:trash -in:drafts -in:sent -in:chats"
            return ([], [base, q].compactMap { $0 }.joined(separator: " "), false)
        case .pinned: return nil
        case .label(let name):
            guard let label = labels.first(where: { $0.isUser && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
            return ([label.id], q, false)
        }
    }
}

/// Which mailbox the list shows: a folder across every account (`account == nil`, "All inboxes") or one account.
public struct MailScope: Hashable, Codable, Sendable {
    public var folder: MailFolder
    public var account: String?

    public init(folder: MailFolder = .inbox, account: String? = nil) {
        self.folder = folder
        self.account = account?.lowercased()
    }

    public var title: String {
        if folder == .inbox, account == nil { return "All inboxes" }
        if let account, folder == .inbox { return account.split(separator: "@").last.map(String.init) ?? account }
        return folder.title
    }
}

/// A user label merged across accounts by name.
public struct MergedLabel: Hashable, Sendable, Identifiable {
    public var name: String
    /// account → label id.
    public var ids: [String: String]
    public var unread: Int
    public var tint: CalendarTint

    public var id: String { name.lowercased() }
}

public enum MailMerge {
    /// Threads from several accounts, newest first (ties broken by account then id so order is stable).
    public static func merge(_ lists: [[ThreadSummary]]) -> [ThreadSummary] {
        lists.flatMap { $0 }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.account != $1.account { return $0.account < $1.account }
            return $0.id < $1.id
        }
    }

    /// User labels with equal names (case-insensitive) become one entry; unread counts add up; the first account's
    /// colour wins. Sorted by name. System labels are excluded.
    public static func mergeLabels(_ perAccount: [String: [GmailLabel]], accountOrder: [String]) -> [MergedLabel] {
        var merged: [String: MergedLabel] = [:]
        for account in accountOrder {
            for label in perAccount[account] ?? [] where label.isUser {
                let key = label.name.lowercased()
                if var existing = merged[key] {
                    existing.ids[account] = label.id
                    existing.unread += label.threadsUnread ?? 0
                    merged[key] = existing
                } else {
                    merged[key] = MergedLabel(name: label.name, ids: [account: label.id], unread: label.threadsUnread ?? 0, tint: label.tint)
                }
            }
        }
        return merged.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Display names of a thread's user labels (for row chips).
    public static func userLabelNames(_ labelIDs: [String], labels: [GmailLabel]) -> [String] {
        let byID = Dictionary(labels.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return labelIDs.compactMap { byID[$0] }.filter(\.isUser).map(\.name)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
