import SwiftUI
import ThubanDeskCore

/// Board "Mail · Inbox": back to Mailboxes, Select, Compose; "All inboxes" + "Synced 2:38 PM"; search; All / Unread /
/// Needs reply; rows with unread dot, sender, count, account dot, time, subject, label chip, preview. Swipe left for
/// Archive / Trash, right for read / unread. Select mode (board "Mail · Dark Brass") checks rows and swaps the tab bar
/// for Archive / Mark read / Label / Spam / Trash.
struct InboxScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    var scope: MailScope
    /// iPad: rows select into the detail column instead of pushing.
    var onOpen: ((ThreadKey) -> Void)?
    var showsBack = true
    @State private var search = ""

    var body: some View {
        let mail = app.mail
        VStack(spacing: 0) {
            navRow
            header
            if let error = mail.listError, mail.threads.isEmpty {
                PhoneBanner(text: error).padding(.horizontal, 16).padding(.bottom, 8)
            }
            list
            if router.mailSelecting { SelectionBar() }
        }
        .background(theme.bgColor.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: scope) {
            if mail.scope != scope { mail.scope = scope }
            search = mail.searchQuery
        }
        .onDisappear { if router.mailSelecting, onOpen == nil, router.openThread == nil { router.mailSelecting = false } }
    }

    // MARK: Header

    private var navRow: some View {
        HStack(spacing: 4) {
            if router.mailSelecting {
                NavTextButton("Select all") { app.mail.checked = Set(app.mail.visibleThreads.map(\.key)) }
                    .padding(.leading, 8)
                Spacer()
                NavTextButton("Done", bold: true) { router.mailSelecting = false; app.mail.checked = [] }
            } else {
                if showsBack {
                    BackButton(title: "Mailboxes") { router.mailPath = [] }
                }
                Spacer()
                NavTextButton("Select") { router.mailSelecting = true }
                NavIconButton(.compose, label: "Compose") { app.requestCompose() }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: PhoneMetrics.navHeight)
    }

    private var header: some View {
        let mail = app.mail
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(scope.title).font(PhoneFont.largeTitle).foregroundStyle(theme.inkColor).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if router.mailSelecting {
                    Text(mail.checked.isEmpty ? "None selected" : "\(mail.checked.count) selected")
                        .font(PhoneFont.secondarySemibold).foregroundStyle(theme.brassInkColor)
                } else {
                    Text(syncedText).font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor)
                }
            }
            if !router.mailSelecting {
                PhoneSearchField(text: $search, placeholder: "Search mail") { app.mail.searchQuery = search }
            }
            PhoneSegmented(options: filterOptions, selection: Binding(get: { mail.filter }, set: { mail.filter = $0 }), accessibilityName: "Filter")
        }
        .padding(.horizontal, PhoneMetrics.gutter)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    private var syncedText: String {
        if app.isSyncing { return "Syncing…" }
        guard let last = app.lastSync else { return "" }
        return "Synced \(CalendarText.clock(last, zone: app.zone))"
    }

    private var filterOptions: [(value: MailListFilter, label: String)] {
        let mail = app.mail
        let unread = mail.threads.filter(\.isUnread).count
        let needs = mail.threads.filter { mail.needsReply[$0.key]?.needsReply == true }.count
        return [(.all, "All"), (.unread, unread > 0 ? "Unread · \(unread)" : "Unread"), (.needsReply, needs > 0 ? "Needs reply · \(needs)" : "Needs reply")]
    }

    // MARK: List

    private var list: some View {
        let mail = app.mail
        let threads = mail.visibleThreads
        return List {
            if threads.isEmpty {
                Group {
                    if mail.isLoadingList || !mail.hasLoadedList {
                        HStack { Spacer(); ProgressView().tint(theme.brassInkColor); Spacer() }.padding(40)
                    } else {
                        PhoneEmptyState(icon: .inbox, text: emptyText)
                    }
                }
                .listRowBackground(theme.bgColor)
                .listRowSeparator(.hidden)
            }
            ForEach(threads) { summary in
                ThreadRow(summary: summary, selecting: router.mailSelecting, checked: mail.checked.contains(summary.key),
                          selected: onOpen != nil && router.padThread == summary.key)
                    .contentShape(Rectangle())
                    .onTapGesture { tap(summary) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(theme.panelColor)
                    .listRowSeparatorTint(theme.lineColor)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 30 }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { Task { await mail.perform(.trash, on: [summary.key]) } } label: {
                            Label { Text("Trash") } icon: { IconImage(.trash) }
                        }
                        .tint(theme.negColor)
                        Button { Task { await mail.perform(.archive, on: [summary.key]) } } label: {
                            Label { Text("Archive") } icon: { IconImage(.archive) }
                        }
                        .tint(theme.signalColor)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { Task { await mail.perform(summary.isUnread ? .markRead : .markUnread, on: [summary.key]) } } label: {
                            Label { Text(summary.isUnread ? "Read" : "Unread") } icon: { IconImage(.markUnread) }
                        }
                        .tint(theme.accentColor)
                    }
                    .contextMenu { ThreadMenu(keys: [summary.key], summary: summary) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: "Archive") { Task { await mail.perform(.archive, on: [summary.key]) } }
                    .accessibilityAction(named: "Trash") { Task { await mail.perform(.trash, on: [summary.key]) } }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.panelColor)
        .overlay(alignment: .top) { Rectangle().fill(theme.lineColor).frame(height: 1) }
        .environment(\.defaultMinListRowHeight, 1)
        .refreshable {
            await app.mail.loadList(force: true)
            await app.mail.loadLabels()
        }
    }

    private var emptyText: String {
        if !app.mail.searchQuery.isEmpty { return "No mail matches “\(app.mail.searchQuery)”." }
        switch app.mail.filter {
        case .unread: return "Nothing unread here."
        case .needsReply: return "Nothing is waiting on your reply."
        case .all: return scope.folder == .inbox ? "Inbox zero. Nice." : "Nothing in \(scope.title)."
        }
    }

    private func tap(_ summary: ThreadSummary) {
        if router.mailSelecting {
            if app.mail.checked.contains(summary.key) { app.mail.checked.remove(summary.key) } else { app.mail.checked.insert(summary.key) }
            return
        }
        if let onOpen { onOpen(summary.key); return }
        router.mailPath.append(.thread(summary.key))
        Task { await app.mail.open(summary.key) }
    }
}

/// A design icon as a template `Image` (swipe actions and menus only take images).
struct IconImage: View {
    var name: IconName
    init(_ name: IconName) { self.name = name }

    var body: some View {
        Image(uiImage: Self.image(name))
    }

    @MainActor private static var cache: [IconName: UIImage] = [:]

    @MainActor static func image(_ name: IconName, size: CGFloat = 22) -> UIImage {
        if let hit = cache[name] { return hit }
        let renderer = ImageRenderer(content: Icon(name, size: size).foregroundStyle(.black))
        renderer.scale = 3
        let image = (renderer.uiImage ?? UIImage()).withRenderingMode(.alwaysTemplate)
        cache[name] = image
        return image
    }
}

/// One thread row (88 pt): unread dot, sender · count · account dot · time, subject + label chip, preview.
struct ThreadRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var summary: ThreadSummary
    var selecting = false
    var checked = false
    var selected = false

    var body: some View {
        let mail = app.mail
        let label = mail.labelNames(for: summary).first
        HStack(alignment: .top, spacing: 8) {
            if selecting {
                ZStack {
                    Circle().strokeBorder(checked ? Color.clear : theme.line2Color, lineWidth: 1.5)
                    if checked {
                        Circle().fill(theme.accentColor)
                        Icon(.check, size: 14, lineWidth: 2.4).foregroundStyle(theme.onAccentInk)
                    }
                }
                .frame(width: 24, height: 24)
                .padding(.top, 2)
                .padding(.leading, 4)
                .accessibilityHidden(true)
            }
            Circle().fill(summary.isUnread ? theme.accentColor : .clear).frame(width: 9, height: 9).padding(.top, 7)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(senderText).font(PhoneFont.bodySemibold).foregroundStyle(theme.inkColor).lineLimit(1)
                    if summary.messageCount > 1 {
                        Text("\(summary.messageCount)").font(PhoneFont.footnote).foregroundStyle(theme.inkFaintColor)
                    }
                    Circle().fill(theme.color(for: mail.accountTint(summary.account))).frame(width: 6, height: 6)
                    Spacer(minLength: 4)
                    if app.mail.isPinned(summary.key) { Icon(.pin, size: 13).foregroundStyle(theme.inkFaintColor) }
                    Text(DeskFormat.listDate(summary.date, now: app.now(), zone: app.zone)).font(PhoneFont.footnote).foregroundStyle(theme.inkFaintColor)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(summary.subject.isEmpty ? "(no subject)" : summary.subject)
                        .font(summary.isUnread ? PhoneFont.secondarySemibold : PhoneFont.secondary)
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let label { PhoneChip(text: label, tint: labelTint(label)) }
                }
                Text(summary.snippet).font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor).lineLimit(1)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 88)
        .background(selected ? theme.accentTintColor : (checked ? theme.accentTintColor.opacity(0.5) : Color.clear))
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(checked || selected ? .isSelected : [])
    }

    private var senderText: String {
        let own = app.ownAddresses
        let others = summary.participants.filter { !own.contains($0.normalized) }
        if summary.labelIDs.contains(GmailSystemLabel.sent), others.isEmpty { return "Me" }
        return summary.from?.displayName ?? others.first?.displayName ?? "Unknown"
    }

    /// A user label whose Gmail colour is the neutral grey reads as the plain chip of the design.
    private func labelTint(_ name: String) -> CalendarTint? {
        let tint = app.mail.labelTint(name)
        return tint == .grey ? nil : tint
    }

    private var accessibilityText: String {
        var parts = [senderText, summary.subject, summary.snippet, DeskFormat.listDate(summary.date, now: app.now(), zone: app.zone)]
        if summary.isUnread { parts.insert("Unread", at: 0) }
        return parts.joined(separator: ", ")
    }
}

/// Reply / star / pin / label / archive / trash for one or more threads (context menus, Thread's More menu).
struct ThreadMenu: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    var keys: [ThreadKey]
    var summary: ThreadSummary?

    var body: some View {
        let mail = app.mail
        if let key = keys.first, keys.count == 1 {
            Button { app.requestReply(to: key) } label: { Label { Text("Reply") } icon: { IconImage(.reply) } }
            Button { app.requestReply(to: key, all: true) } label: { Label { Text("Reply all") } icon: { IconImage(.replyAll) } }
            Button { app.requestForward(key) } label: { Label { Text("Forward") } icon: { IconImage(.forward) } }
            Divider()
            let pinned = mail.isPinned(key)
            Button { mail.setPinned(!pinned, key) } label: { Label { Text(pinned ? "Unpin" : "Pin") } icon: { IconImage(.pin) } }
            let starred = summary?.isStarred ?? mail.detail(key)?.isStarred ?? false
            Button { Task { await mail.perform(starred ? .unstar : .star, on: keys) } } label: {
                Label { Text(starred ? "Remove star" : "Star") } icon: { IconImage(.star) }
            }
        }
        Button { router.labelTargets = keys } label: { Label { Text("Label…") } icon: { IconImage(.label) } }
        Button { Task { await mail.perform(.markUnread, on: keys) } } label: { Label { Text("Mark unread") } icon: { IconImage(.markUnread) } }
        Button { Task { await mail.perform(.spam, on: keys) } } label: { Label { Text("Report spam") } icon: { IconImage(.spam) } }
        Divider()
        Button { Task { await mail.perform(.archive, on: keys) } } label: { Label { Text("Archive") } icon: { IconImage(.archive) } }
        Button(role: .destructive) { Task { await mail.perform(.trash, on: keys) } } label: { Label { Text("Trash") } icon: { IconImage(.trash) } }
    }
}

/// Select mode's bottom bar (board "Mail · Dark Brass"): Archive, Mark read, Label, Spam, Trash on the checked threads.
struct SelectionBar: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let keys = app.mail.checkedKeys
        HStack(spacing: 0) {
            item(.archive, "Archive") { await app.mail.perform(.archive, on: keys) }
            item(.mail, "Mark read") { await app.mail.perform(.markRead, on: keys) }
            barButton(.label, "Label", tint: theme.brassInkColor) { router.labelTargets = keys }
            item(.spam, "Spam") { await app.mail.perform(.spam, on: keys) }
            item(.trash, "Trash", tint: theme.negTextColor) { await app.mail.perform(.trash, on: keys) }
        }
        .disabled(keys.isEmpty)
        .opacity(keys.isEmpty ? 0.5 : 1)
        .padding(.horizontal, 8)
        .background(theme.panelColor.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(theme.lineColor).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions for selected threads")
    }

    private func item(_ icon: IconName, _ title: String, tint: Color? = nil, _ action: @escaping () async -> Void) -> some View {
        barButton(icon, title, tint: tint ?? theme.brassInkColor) {
            Task {
                await action()
                app.mail.checked = []
            }
        }
    }

    private func barButton(_ icon: IconName, _ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Icon(icon, size: 24)
                Text(title).font(PhoneFont.tabLabel)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 49)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
