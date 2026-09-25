import SwiftUI
import ThubanDeskCore

/// The thread list (design 468 pt, panel): serif title + "4 unread · 2 accounts", then the All / Unread / Needs reply
/// filter — replaced by the bulk bar while threads are checked — and the rows (always-visible checkboxes).
/// Keyboard: ↑/↓ move, Return opens, Space checks, E archives, # or Delete trashes, S stars, U read/unread.
struct MailThreadList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @FocusState private var focused: Bool
    @State private var bulkLabel = false

    var body: some View {
        @Bindable var mail = app.mail
        let rows = mail.visibleThreads
        VStack(spacing: 0) {
            header
            if !mail.searchQuery.isEmpty { SearchEventsStrip() }
            if !mail.checked.isEmpty {
                bulkBar
            } else {
                HStack(spacing: 8) {
                    SegmentedPicker(selection: $mail.filter,
                                    options: MailListFilter.allCases.map { SegmentOption($0, $0.title) },
                                    segmentHeight: SegmentedPickerHeight.toolbar)
                    Spacer()
                    if mail.isLoadingList { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .thubanHairline(.bottom, color: theme.lineColor)
            }
            if let error = mail.listError, rows.isEmpty {
                EmptyState(icon: .info, title: "Mail couldn’t load", message: error) {
                    Button("Try again") { Task { await mail.loadList(force: true) } }.buttonStyle(SecondaryButtonStyle(height: 32))
                }
            } else if rows.isEmpty {
                if mail.hasLoadedList && !mail.isLoadingList {
                    EmptyState(icon: emptyIcon, title: emptyTitle, message: emptyMessage) { EmptyView() }
                } else {
                    LoadingRows()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { summary in
                                MailThreadRow(summary: summary)
                                    .id(summary.key)
                            }
                        }
                    }
                    .onChange(of: mail.selection) { _, key in
                        if let key { withAnimation(nil) { proxy.scrollTo(key) } }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.panelColor)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .onChange(of: app.mail.selection) { _, key in
            if key != nil, app.mail.compose == nil, app.pendingConfirmation == nil { focused = true }
        }
    }

    private var header: some View {
        let mail = app.mail
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(ThubanFont.display(22)).foregroundStyle(theme.inkColor).lineLimit(1)
            Text(subtitle).font(ThubanFont.small).foregroundStyle(theme.inkDimColor).lineLimit(1)
            Spacer(minLength: 0)
            if !mail.searchQuery.isEmpty {
                Button("Clear") { app.searchText = "" }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.brassInkColor)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
        .thubanHairline(.bottom, color: theme.lineColor)
    }

    private var title: String {
        let mail = app.mail
        if !mail.searchQuery.isEmpty { return "Search" }
        return mail.scope.title
    }

    private var subtitle: String {
        let mail = app.mail
        if !mail.searchQuery.isEmpty { return "“\(mail.searchQuery)” in \(mail.scope.title)" }
        let unread = mail.threads.filter(\.isUnread).count
        let accounts = mail.scope.account == nil ? app.activeAccounts.count : 1
        var parts: [String] = []
        switch mail.scope.folder {
        case .inbox, .label: parts.append("\(unread) unread")
        default: parts.append("\(mail.threads.count) conversation\(mail.threads.count == 1 ? "" : "s")")
        }
        if mail.scope.account == nil { parts.append("\(accounts) account\(accounts == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private var emptyIcon: IconName {
        switch app.mail.scope.folder {
        case .pinned: return .pin
        case .starred: return .star
        case .trash: return .trash
        case .spam: return .spam
        case .drafts: return .drafts
        default: return .inbox
        }
    }

    private var emptyTitle: String {
        let mail = app.mail
        if !mail.searchQuery.isEmpty { return "Nothing found" }
        if mail.filter == .unread { return "No unread mail" }
        if mail.filter == .needsReply { return "Nothing needs a reply" }
        switch mail.scope.folder {
        case .inbox: return "Inbox zero"
        case .pinned: return "Nothing pinned"
        default: return "Nothing in \(mail.scope.folder.title)"
        }
    }

    private var emptyMessage: String? {
        let mail = app.mail
        if !mail.searchQuery.isEmpty { return "Try other words, or search a different folder." }
        if mail.scope.folder == .pinned { return "Pin a conversation to keep it here. Pins stay on this Mac." }
        if mail.filter == .needsReply { return "Mail from a real person asking you something shows here until you answer." }
        return nil
    }

    // MARK: Bulk bar

    private var bulkBar: some View {
        let mail = app.mail
        let keys = mail.checkedKeys
        let anyUnread = keys.compactMap(mail.summary).contains(where: \.isUnread)
        return HStack(spacing: 2) {
            Text("\(mail.checked.count) selected")
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(theme.brassInkColor)
                .padding(.trailing, 6)
                .fixedSize()
            ViewThatFits(in: .horizontal) {
                bulkButtons(keys: keys, anyUnread: anyUnread, labels: 3)
                bulkButtons(keys: keys, anyUnread: anyUnread, labels: 2)
                bulkButtons(keys: keys, anyUnread: anyUnread, labels: 0)
            }
            Spacer(minLength: 0)
            IconButton(.close, label: "Clear selection", size: 28, iconSize: 14) { mail.checked = [] }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 44)
        .background(theme.accentTintColor)
        .thubanHairline(.bottom, color: theme.line2Color)
    }

    /// `labels`: how many of Archive / Mark / Label keep their text (the rest become icons) so the bar always fits.
    private func bulkButtons(keys: [ThreadKey], anyUnread: Bool, labels: Int) -> some View {
        let mail = app.mail
        return HStack(spacing: 2) {
            if mail.scope.folder == .trash {
                bulkAction("Restore", .inbox, labels > 0) { bulk(.untrash) }
            } else {
                bulkAction("Archive", .archive, labels > 0) { bulk(.archive) }
            }
            bulkAction(anyUnread ? "Mark read" : "Mark unread", .markUnread, labels > 1) { bulk(anyUnread ? .markRead : .markUnread) }
            bulkAction("Label", .label, labels > 2) { bulkLabel = true }
                .popover(isPresented: $bulkLabel, arrowEdge: .bottom) {
                    LabelPicker(targets: keys) { bulkLabel = false }
                        .environment(\.thubanTheme, theme)
                        .environment(app)
                }
            bulkIcon(.spam, label: "Report spam") { bulk(.spam) }
            if mail.scope.folder == .trash {
                bulkIcon(.trash, label: "Delete forever") { MailActions.deleteForever(keys, app: app) }
            } else {
                bulkIcon(.trash, label: "Move to trash") { bulk(.trash) }
            }
        }
    }

    @ViewBuilder
    private func bulkAction(_ title: String, _ icon: IconName, _ showsLabel: Bool, action: @escaping () -> Void) -> some View {
        if showsLabel {
            MailToolButton(title: title, icon: icon, fontSize: 13, height: 28, ink: true, action: action)
        } else {
            bulkIcon(icon, label: title, action: action)
        }
    }

    private func bulkIcon(_ icon: IconName, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 15).foregroundStyle(theme.inkColor).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(GhostButtonStyle(height: 28, horizontalPadding: 0))
        .help(label)
        .accessibilityLabel(label)
    }

    private func bulk(_ action: MailAction) {
        let keys = app.mail.checkedKeys
        Task { await app.mail.perform(action, on: keys) }
    }

    // MARK: Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let mail = app.mail
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        let rows = mail.visibleThreads
        let index = mail.selection.flatMap { key in rows.firstIndex { $0.key == key } }
        func move(_ delta: Int) {
            guard !rows.isEmpty else { return }
            let next = index.map { min(max($0 + delta, 0), rows.count - 1) } ?? 0
            Task { await mail.open(rows[next].key) }
        }
        switch press.key {
        case .downArrow: move(1); return .handled
        case .upArrow: move(-1); return .handled
        case .space:
            if let key = mail.selection { if mail.checked.contains(key) { mail.checked.remove(key) } else { mail.checked.insert(key) } }
            return .handled
        case .escape:
            if !mail.checked.isEmpty { mail.checked = []; return .handled }
            return .ignored
        case .delete, .deleteForward:
            perform(.trash); return .handled
        default: break
        }
        switch press.characters {
        case "j": move(1); return .handled
        case "k": move(-1); return .handled
        case "e": perform(.archive); return .handled
        case "#": perform(.trash); return .handled
        case "s":
            let starred = mail.actionTargets.compactMap(mail.summary).allSatisfy(\.isStarred)
            perform(starred ? .unstar : .star); return .handled
        case "u":
            let unread = mail.actionTargets.compactMap(mail.summary).contains(where: \.isUnread)
            perform(unread ? .markRead : .markUnread); return .handled
        case "r":
            if let key = mail.selection, let last = mail.detail(key)?.messages.last(where: { !$0.isDraft }) {
                ComposeModel.openReply(to: last, in: key, all: false, app: app); return .handled
            }
            return .ignored
        default: return .ignored
        }
    }

    private func perform(_ action: MailAction) {
        let targets = app.mail.actionTargets
        guard !targets.isEmpty else { return }
        Task { await app.mail.perform(action, on: targets) }
    }
}

/// Placeholder rows while the first page loads.
private struct LoadingRows: View {
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(theme.panel2Color).frame(width: 160, height: 12)
                    RoundedRectangle(cornerRadius: 4).fill(theme.panel2Color).frame(width: 260, height: 11)
                    RoundedRectangle(cornerRadius: 4).fill(theme.panel2Color.opacity(0.7)).frame(maxWidth: .infinity).frame(height: 10)
                }
                .padding(EdgeInsets(top: 14, leading: 42, bottom: 14, trailing: 16))
                .thubanHairline(.bottom, color: theme.lineColor)
            }
            Spacer()
        }
        .accessibilityLabel("Loading mail")
    }
}

/// One thread row (design): checkbox column, then sender (bold when unread) · message count · account tag ·
/// pin / star · time; subject; snippet + label chips. The open thread gets the tint ground and an accent bar.
struct MailThreadRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var summary: ThreadSummary
    @State private var hovering = false

    var body: some View {
        let mail = app.mail
        let key = summary.key
        let selected = mail.selection == key
        let checked = mail.checked.contains(key)
        let unread = summary.isUnread
        let pinned = mail.isPinned(key)
        let labels = mail.labelNames(for: summary)
        HStack(alignment: .top, spacing: 0) {
            Button {
                if checked { mail.checked.remove(key) } else { mail.checked.insert(key) }
            } label: {
                MailCheckbox(isOn: checked)
                    .frame(width: 42)
                    .padding(.top, 14)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select thread from \(sender)")
            .accessibilityAddTraits(checked ? [.isSelected] : [])

            Button {
                Task { await mail.open(key) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Circle().fill(unread ? theme.unreadDotColor : .clear).frame(width: 8, height: 8)
                        Text(sender)
                            .font(.system(size: 14.5, weight: unread ? .bold : .medium))
                            .foregroundStyle(theme.inkColor)
                            .lineLimit(1)
                            .layoutPriority(1)
                        if summary.messageCount > 1 {
                            Text(String(summary.messageCount))
                                .font(ThubanFont.mono(11.5))
                                .foregroundStyle(theme.inkDimColor)
                                .padding(.horizontal, 5)
                                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                        }
                        if mail.scope.account == nil, app.accounts.count > 1 {
                            HStack(spacing: 4) {
                                TintDot(tint: mail.accountTint(summary.account), size: 6)
                                Text(summary.accountDomain).font(.system(size: 11.5)).foregroundStyle(theme.inkFaintColor).lineLimit(1)
                            }
                            .fixedSize()
                        }
                        Spacer(minLength: 6)
                        HStack(spacing: 6) {
                            if summary.hasAttachments { Icon(.attach, size: 13).foregroundStyle(theme.inkFaintColor) }
                            if pinned { Icon(.pin, size: 13).foregroundStyle(theme.brassInkColor) }
                            if summary.isStarred { FilledIcon(.star, size: 13).foregroundStyle(theme.accentColor) }
                            Text(DeskFormat.listDate(summary.date, now: app.now(), zone: app.zone))
                                .font(.system(size: 12.5, weight: unread ? .semibold : .regular))
                                .foregroundStyle(unread ? theme.brassInkColor : theme.inkDimColor)
                                .lineLimit(1)
                        }
                        .fixedSize()
                    }
                    Text(summary.subject.isEmpty ? "(no subject)" : summary.subject)
                        .font(.system(size: 14, weight: unread ? .semibold : .regular))
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(1)
                        .padding(.leading, 15)
                    HStack(spacing: 6) {
                        Text(summary.snippet)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.inkDimColor)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(labels.prefix(2), id: \.self) { name in
                            LabelChip(name: name, tint: mail.labelTint(name), compact: true)
                        }
                    }
                    .padding(.leading, 15)
                }
                .padding(EdgeInsets(top: 11, leading: 0, bottom: 11, trailing: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(unread ? "Unread. " : "")\(sender). \(summary.subject). \(summary.snippet)")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        }
        .background(selected ? theme.accentTintColor : (hovering ? theme.panel2Color.opacity(0.5) : theme.panelColor))
        .overlay(alignment: .leading) {
            if selected {
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 3, topTrailingRadius: 3, style: .continuous)
                    .fill(theme.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
        .thubanHairline(.bottom, color: theme.lineColor)
        .onHover { hovering = $0 }
        .contextMenu { contextMenu(key: key, pinned: pinned) }
    }

    private var sender: String {
        if app.mail.scope.folder == .sent || app.mail.scope.folder == .drafts {
            let others = summary.participants.filter { !app.ownAddresses.contains($0.normalized) }
            return others.first.map { "To: \($0.displayName)" } ?? summary.from?.displayName ?? "(unknown)"
        }
        return summary.from?.displayName ?? "(unknown sender)"
    }

    @ViewBuilder
    private func contextMenu(key: ThreadKey, pinned: Bool) -> some View {
        let mail = app.mail
        let keys = mail.checked.contains(key) ? mail.checkedKeys : [key]
        Button(summary.isUnread ? "Mark as read" : "Mark as unread") { Task { await mail.perform(summary.isUnread ? .markRead : .markUnread, on: keys) } }
        Button(summary.isStarred ? "Unstar" : "Star") { Task { await mail.perform(summary.isStarred ? .unstar : .star, on: keys) } }
        Button(pinned ? "Unpin" : "Pin") { for k in keys { mail.setPinned(!pinned, k) } }
        Divider()
        if summary.isInInbox {
            Button("Archive") { Task { await mail.perform(.archive, on: keys) } }
        } else {
            Button("Move to Inbox") { Task { await mail.perform(.moveToInbox, on: keys) } }
        }
        if summary.labelIDs.contains(GmailSystemLabel.spam) {
            Button("Not spam") { Task { await mail.perform(.notSpam, on: keys) } }
        } else {
            Button("Report spam") { Task { await mail.perform(.spam, on: keys) } }
        }
        if summary.labelIDs.contains(GmailSystemLabel.trash) {
            Button("Restore from Trash") { Task { await mail.perform(.untrash, on: keys) } }
            Button("Delete forever…") { MailActions.deleteForever(keys, app: app) }
        } else {
            Button("Move to Trash") { Task { await mail.perform(.trash, on: keys) } }
        }
        Divider()
        Button("Select") { mail.checked.insert(key) }
    }
}
