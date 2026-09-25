import SwiftUI
import ThubanDeskCore

/// Mail: Mailboxes at the root with All inboxes pushed on top (like Mail on iPhone), threads pushed from the list.
struct MailTab: View {
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.mailPath) {
            MailboxesScreen()
                .navigationDestination(for: MailRoute.self) { route in
                    switch route {
                    case .mailbox(let scope): InboxScreen(scope: scope)
                    case .thread(let key): ThreadScreen(key: key)
                    }
                }
        }
    }
}

// MARK: - Mailboxes

/// Board "Mail · Mailboxes and labels": All inboxes / Pinned / Starred / Drafts / Sent, the accounts' inboxes, then the
/// labels merged across accounts ("2 filters active").
struct MailboxesScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    /// iPad sidebar: selecting sets the split view's list instead of pushing.
    var onSelect: ((MailScope) -> Void)?

    var body: some View {
        PhoneScreen(title: "Mailboxes") {
            EmptyView()
        } navTrailing: {
            NavIconButton(.compose, label: "Compose") { app.requestCompose() }
        } content: {
            MailboxList(onSelect: onSelect ?? { scope in router.mailPath = [.mailbox(scope)] })
                .padding(.horizontal, PhoneMetrics.gutter)
                .padding(.bottom, 24)
        }
        .refreshable { await app.refreshAll() }
    }
}

struct MailboxList: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    var onSelect: (MailScope) -> Void

    var body: some View {
        let mail = app.mail
        let current = router.currentMailScope
        VStack(alignment: .leading, spacing: 22) {
            InsetCard {
                let folders: [MailFolder] = [.inbox, .pinned, .starred, .drafts, .sent]
                ForEach(Array(folders.enumerated()), id: \.offset) { index, folder in
                    if index > 0 { RowDivider(inset: 51) }
                    let scope = MailScope(folder: folder)
                    mailboxRow(icon: icon(folder), title: scope.title, count: mail.folderCount(folder), selected: current == scope, strong: folder == .inbox) {
                        onSelect(scope)
                    }
                }
            }
            if !app.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Accounts").padding(.horizontal, 16)
                    InsetCard {
                        ForEach(Array(app.accounts.enumerated()), id: \.element.id) { index, account in
                            if index > 0 { RowDivider(inset: 51) }
                            let scope = MailScope(folder: .inbox, account: account.id)
                            Button { onSelect(scope) } label: {
                                PhoneRow(chevron: true, highlighted: current == scope) {
                                    HStack(spacing: 14) {
                                        Circle().fill(theme.color(for: mail.accountTint(account.id))).frame(width: 9, height: 9).frame(width: 22)
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(account.domain).font(PhoneFont.body).foregroundStyle(theme.inkColor)
                                            if account.id == app.primaryAccount?.id {
                                                Text("Primary").font(.caption).foregroundStyle(theme.inkDimColor)
                                            }
                                        }
                                    }
                                } trailing: {
                                    count(mail.unreadInbox(account: account.id))
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(account.email) inbox, \(mail.unreadInbox(account: account.id)) unread")
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Eyebrow("Labels")
                    Spacer()
                    if mail.activeFilterCount > 0 {
                        Text("\(mail.activeFilterCount) filter\(mail.activeFilterCount == 1 ? "" : "s") active")
                            .font(PhoneFont.footnoteSemibold).foregroundStyle(theme.brassInkColor)
                    }
                }
                .padding(.horizontal, 16)
                InsetCard {
                    if mail.mergedLabels.isEmpty {
                        Text("No labels yet.").font(PhoneFont.secondary).foregroundStyle(theme.inkDimColor).padding(16)
                    }
                    ForEach(Array(mail.mergedLabels.enumerated()), id: \.element.id) { index, label in
                        if index > 0 { RowDivider(inset: 51) }
                        let scope = MailScope(folder: .label(label.name))
                        mailboxRow(icon: .label, title: label.name, count: label.unread > 0 ? label.unread : nil, selected: current == scope, strong: false) {
                            onSelect(scope)
                        }
                    }
                }
            }
            InsetCard {
                let more: [MailFolder] = [.archive, .spam, .trash]
                ForEach(Array(more.enumerated()), id: \.offset) { index, folder in
                    if index > 0 { RowDivider(inset: 51) }
                    let scope = MailScope(folder: folder)
                    mailboxRow(icon: icon(folder), title: scope.title, count: mail.folderCount(folder), selected: current == scope, strong: false) {
                        onSelect(scope)
                    }
                }
            }
        }
    }

    private func mailboxRow(icon: IconName, title: String, count value: Int?, selected: Bool, strong: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PhoneRow(chevron: true, highlighted: selected) {
                HStack(spacing: 14) {
                    Icon(icon, size: 22).foregroundStyle(theme.brassInkColor).frame(width: 22)
                    Text(title).font(selected && strong ? PhoneFont.bodySemibold : PhoneFont.body).foregroundStyle(theme.inkColor)
                }
            } trailing: {
                count(value, strong: selected)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func count(_ value: Int?, strong: Bool = false) -> some View {
        if let value, value > 0 {
            Text("\(value)").font(strong ? PhoneFont.secondarySemibold : PhoneFont.secondary)
                .foregroundStyle(strong ? theme.brassInkColor : theme.inkDimColor)
        }
    }

    private func icon(_ folder: MailFolder) -> IconName {
        switch folder {
        case .inbox: return .inbox
        case .pinned: return .pin
        case .starred: return .star
        case .drafts: return .drafts
        case .sent: return .sent
        case .archive: return .archive
        case .spam: return .spam
        case .trash: return .trash
        case .label: return .label
        }
    }
}
