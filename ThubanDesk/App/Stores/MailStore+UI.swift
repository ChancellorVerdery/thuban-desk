import Foundation
import ThubanDeskCore

/// Derived values the Mail area draws: account colours, folder counts, contacts for recipient suggestions,
/// label colours, the invitation a message refers to, and Gmail draft lookup.
extension MailStore {
    /// Account colour roles in link order (primary = accent, then signal, pos, neg, grey) — the design's dots.
    func accountTint(_ account: String) -> CalendarTint {
        let order: [CalendarTint] = [.accent, .signal, .pos, .neg, .grey]
        guard let index = accountOrder.firstIndex(of: account.lowercased()) else { return .grey }
        return order[min(index, order.count - 1)]
    }

    /// "gmail.com" for the sidebar and row tags.
    func accountDomain(_ account: String) -> String {
        String(account.split(separator: "@").last ?? Substring(account))
    }

    /// Sidebar counts: unread for Inbox (per scope), totals for Pinned / Starred / Drafts; nil hides the number.
    func folderCount(_ folder: MailFolder, account: String? = nil) -> Int? {
        let accounts = account.map { [$0] } ?? accountOrder
        func sum(_ id: String, unread: Bool) -> Int {
            accounts.reduce(0) { total, account in
                let label = labels[account]?.first { $0.id == id }
                return total + ((unread ? label?.threadsUnread : label?.threadsTotal) ?? 0)
            }
        }
        let value: Int
        switch folder {
        case .inbox: value = sum(GmailSystemLabel.inbox, unread: true)
        case .pinned: value = accounts.reduce(0) { $0 + (app?.settings.pins[$1]?.count ?? 0) }
        case .starred: value = sum(GmailSystemLabel.starred, unread: false)
        case .drafts: value = sum(GmailSystemLabel.draft, unread: false)
        case .spam: value = sum(GmailSystemLabel.spam, unread: true)
        case .label(let name): value = mergedLabels.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.unread ?? 0
        default: return nil
        }
        return value > 0 ? value : nil
    }

    /// Colour role of a user label by name (first account's colour wins, as in `MailMerge`).
    func labelTint(_ name: String) -> CalendarTint {
        mergedLabels.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.tint ?? .grey
    }

    /// Everyone seen in loaded mail (senders and recipients), newest first — recipient suggestions.
    var contacts: [EmailAddress] {
        let own = app?.ownAddresses ?? []
        var seen = Set<String>()
        var out: [EmailAddress] = []
        let messages = details.values.flatMap(\.messages).sorted { $0.date > $1.date }
        for message in messages {
            for address in [message.from].compactMap({ $0 }) + message.to + message.cc
            where !own.contains(address.normalized) && seen.insert(address.normalized).inserted {
                out.append(address)
            }
        }
        for summary in threads {
            if let from = summary.from, !own.contains(from.normalized), seen.insert(from.normalized).inserted { out.append(from) }
        }
        return out
    }

    /// The loaded thread for the reader, if fetched.
    func detail(_ key: ThreadKey) -> MailThread? { details[key] }

    /// The invitation a message is about (an event from its sender), from the loaded calendar data.
    func invitation(for message: MailMessage) -> AgendaEvent? {
        guard let app else { return nil }
        let now = app.now()
        let candidates = app.calendar.events(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(90 * 86_400), includeHidden: true)
        return MailInvite.match(message, candidates: candidates, zone: app.zone)
    }

    /// The Gmail draft id that holds a draft message (drafts.list maps message → draft).
    func draftID(forMessage messageID: String, account: String) async -> String? {
        guard let client = app.client(for: account), let drafts = try? await client.drafts() else { return nil }
        return drafts.first { $0.message?.id == messageID }?.id
    }

    /// Checked threads in list order (bulk actions).
    var checkedKeys: [ThreadKey] { threads.map(\.key).filter(checked.contains) }

    /// The threads a toolbar action applies to: the checked ones, else the open one.
    var actionTargets: [ThreadKey] {
        if !checked.isEmpty { return checkedKeys }
        return selection.map { [$0] } ?? []
    }

    func summary(_ key: ThreadKey) -> ThreadSummary? { threads.first { $0.key == key } }
}
