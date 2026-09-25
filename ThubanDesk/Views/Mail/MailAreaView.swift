import SwiftUI
import ThubanDeskCore

/// Mail (design: Mail.dc.html / MailDark.dc.html): a 48 pt toolbar (Compose, sync time, actions on the open or
/// checked threads), then the folder sidebar (236), the thread list (resizable, remembered) and the reader.
/// Compose opens as a window over the area (Compose.dc.html).
struct MailAreaView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            MailToolbar()
            // After a failed refresh the list is what was saved: say so, with Retry.
            if !app.syncErrors.isEmpty && !app.isSyncing {
                OfflineBanner(text: "Offline · showing saved mail — \(app.syncErrors.values.sorted().first ?? "")") {
                    await app.refreshAll()
                }
            }
            HStack(spacing: 0) {
                MailSidebar()
                MailSplitView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if let compose = app.mail.compose {
                ComposeOverlay(model: compose)
                    .transition(.opacity)
            }
        }
        .animation(app.settings.reduceMotion ? nil : .easeOut(duration: 0.15), value: app.mail.compose?.id)
        .task {
            if app.mail.threads.isEmpty && !app.isSyncing { await app.mail.loadList() }
            if app.mail.searchQuery != app.searchText.trimmingCharacters(in: .whitespaces) { applySearch(app.searchText, immediately: true) }
        }
        .onChange(of: app.searchText) { _, text in applySearch(text, immediately: false) }
        .onChange(of: app.newItemRequest) { _, _ in
            if app.area == .mail, app.mail.compose == nil { ComposeModel.openNew(app: app) }
        }
    }

    /// The title-bar search runs a Gmail search (`q=`) over the current folder, debounced.
    private func applySearch(_ text: String, immediately: Bool) {
        searchTask?.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask = Task { @MainActor in
            if !immediately { try? await Task.sleep(nanoseconds: 450_000_000) }
            guard !Task.isCancelled, app.mail.searchQuery != query else { return }
            app.mail.searchQuery = query
        }
    }
}

/// List + draggable divider + reader. The list width is remembered (`settings.mailListWidth`).
struct MailSplitView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var dragStart: Double?
    @State private var liveWidth: Double?

    static let minList: Double = 340
    static let minReader: Double = 420

    var body: some View {
        GeometryReader { proxy in
            let maxList = max(Self.minList, proxy.size.width - Self.minReader)
            let width = min(max(liveWidth ?? app.settings.mailListWidth, Self.minList), maxList)
            HStack(spacing: 0) {
                MailThreadList()
                    .frame(width: width)
                    .clipped()
                MailSplitter()
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStart ?? width
                                if dragStart == nil { dragStart = width }
                                liveWidth = min(max(start + value.translation.width, Self.minList), maxList)
                            }
                            .onEnded { _ in
                                if let liveWidth { app.settings.mailListWidth = liveWidth.rounded() }
                                dragStart = nil
                                liveWidth = nil
                            }
                    )
                MailReaderPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// The 9 pt drag target with a 1 px line and a small handle (design splitter).
struct MailSplitter: View {
    @Environment(\.thubanTheme) private var theme
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle().fill(theme.line2Color).frame(width: 1)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(theme.panelColor)
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(hovering ? theme.accentColor : theme.line2Color, lineWidth: 1))
                .frame(width: 5, height: 30)
        }
        .frame(width: 9)
        .frame(maxHeight: .infinity)
        .padding(.horizontal, -4)
        .contentShape(Rectangle())
        .zIndex(2)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .accessibilityElement()
        .accessibilityLabel("Resize thread list")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Toolbar

/// Design: [Compose] ⟳ Synced 2:38 PM … Archive · Spam · Trash · Mark unread · Label | ☆ · pin · ⋯
/// Actions apply to the checked threads, else the open one. In Trash / Spam the actions become Restore / Not spam
/// and Delete forever (confirmed).
struct MailToolbar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var labelPicker = false

    var body: some View {
        let mail = app.mail
        let targets = mail.actionTargets
        let summaries = targets.compactMap(mail.summary)
        let hasTargets = !targets.isEmpty
        HStack(spacing: 12) {
            Button {
                ComposeModel.openNew(app: app)
            } label: {
                HStack(spacing: 7) {
                    Icon(.plus, size: 15)
                    Text("Compose")
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 32))
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("Compose (⌘N)")

            HStack(spacing: 6) {
                Icon(.sync, size: 13)
                Text(syncText).font(ThubanFont.small)
            }
            .foregroundStyle(theme.inkFaintColor)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                switch mail.scope.folder {
                case .trash:
                    MailToolButton(title: "Restore", icon: .inbox) { act(.untrash) }.disabled(!hasTargets)
                    MailToolButton(title: "Delete forever", icon: .trash) { MailActions.deleteForever(targets, app: app) }.disabled(!hasTargets)
                    MailToolButton(title: "Empty Trash", icon: nil) { MailActions.emptyTrash(app: app) }
                case .spam:
                    MailToolButton(title: "Not spam", icon: .inbox) { act(.notSpam) }.disabled(!hasTargets)
                    MailToolButton(title: "Delete forever", icon: .trash) { MailActions.deleteForever(targets, app: app) }.disabled(!hasTargets)
                default:
                    if mail.scope.folder == .archive || (summaries.first.map { !$0.isInInbox } ?? false) && mail.scope.folder != .inbox {
                        MailToolButton(title: "Move to Inbox", icon: .inbox) { act(.moveToInbox) }.disabled(!hasTargets)
                    } else {
                        MailToolButton(title: "Archive", icon: .archive) { act(.archive) }.disabled(!hasTargets)
                    }
                    MailToolButton(title: "Spam", icon: .spam) { act(.spam) }.disabled(!hasTargets)
                    MailToolButton(title: "Trash", icon: .trash) { act(.trash) }.disabled(!hasTargets)
                }
                let anyUnread = summaries.contains(where: \.isUnread)
                MailToolButton(title: anyUnread ? "Mark read" : "Mark unread", icon: .markUnread) { act(anyUnread ? .markRead : .markUnread) }
                    .disabled(!hasTargets)
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                MailToolButton(title: "Label", icon: .label) { labelPicker = true }
                    .disabled(!hasTargets)
                    .popover(isPresented: $labelPicker, arrowEdge: .bottom) {
                        LabelPicker(targets: targets) { labelPicker = false }
                            .environment(\.thubanTheme, theme)
                            .environment(app)
                    }
                Rectangle().fill(theme.line2Color).frame(width: 1, height: 20).padding(.horizontal, 4)
                let starred = !summaries.isEmpty && summaries.allSatisfy(\.isStarred)
                starButton(starred: starred, targets: targets)
                let pinned = !targets.isEmpty && targets.allSatisfy(mail.isPinned)
                IconButton(.pin, label: pinned ? "Unpin" : "Pin", size: 32, iconSize: 15, tinted: pinned) {
                    for key in targets { mail.setPinned(!pinned, key) }
                }
                .disabled(!hasTargets)
                MenuPopoverButton(icon: .more, label: "More actions", size: 32, iconSize: 15) { moreItems(targets: targets, summaries: summaries) }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(theme.bgColor)
        .thubanHairline(.bottom, color: theme.lineColor)
    }

    private var syncText: String {
        if app.isSyncing || app.mail.isLoadingList { return "Syncing…" }
        // A failed refresh wins over the time of the last good one (which would read as "all is well").
        if !app.syncErrors.isEmpty { return "Offline · showing saved mail" }
        if let last = app.lastSync { return "Synced \(DeskFormat.time(last, zone: app.zone))" }
        return "Not synced yet"
    }

    private func starButton(starred: Bool, targets: [ThreadKey]) -> some View {
        Button {
            act(starred ? .unstar : .star)
        } label: {
            Group {
                if starred { FilledIcon(.star, size: 15).foregroundStyle(theme.accentColor) } else { Icon(.star, size: 15).foregroundStyle(theme.inkDimColor) }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(targets.isEmpty)
        .help(starred ? "Unstar" : "Star")
        .accessibilityLabel(starred ? "Unstar" : "Star")
    }

    private func act(_ action: MailAction) {
        let targets = app.mail.actionTargets
        guard !targets.isEmpty else { return }
        Task { await app.mail.perform(action, on: targets) }
    }

    private func moreItems(targets: [ThreadKey], summaries: [ThreadSummary]) -> [MenuPopoverItem] {
        let mail = app.mail
        var items: [MenuPopoverItem] = []
        if let key = mail.selection, let thread = mail.detail(key), let last = thread.messages.last(where: { !$0.isDraft }) {
            items.append(MenuPopoverItem(title: "Reply", icon: .reply) { ComposeModel.openReply(to: last, in: key, all: false, app: app) })
            items.append(MenuPopoverItem(title: "Reply all", icon: .replyAll) { ComposeModel.openReply(to: last, in: key, all: true, app: app) })
            items.append(MenuPopoverItem(title: "Forward", icon: .forward) { ComposeModel.openForward(last, in: key, app: app) })
            items.append(.separator)
        }
        if mail.scope.folder != .inbox && mail.scope.folder != .trash {
            items.append(MenuPopoverItem(title: "Move to Inbox", icon: .inbox, disabled: targets.isEmpty) { act(.moveToInbox) })
        }
        items.append(MenuPopoverItem(title: "Delete forever…", icon: .trash, destructive: true, disabled: targets.isEmpty) {
            MailActions.deleteForever(targets, app: app)
        })
        items.append(MenuPopoverItem(title: "Empty Trash…", icon: .trash, destructive: true) { MailActions.emptyTrash(app: app) })
        items.append(.separator)
        items.append(MenuPopoverItem(title: "Refresh", icon: .sync) { Task { await app.refreshAll() } })
        return items
    }
}

/// Confirmed (irreversible) mailbox actions.
@MainActor
enum MailActions {
    static func deleteForever(_ keys: [ThreadKey], app: AppModel) {
        guard !keys.isEmpty else { return }
        let count = keys.count
        let subject = keys.count == 1 ? app.mail.summary(keys[0])?.subject : nil
        app.confirm(ConfirmRequest(
            title: count == 1 ? "Delete this conversation forever?" : "Delete \(count) conversations forever?",
            message: (subject.map { "“\($0)” " } ?? (count == 1 ? "This conversation " : "These conversations "))
                + "will be permanently deleted from Gmail. This cannot be undone.",
            actionLabel: "Delete forever", destructive: true, workingLabel: "Deleting…") { confirmed in
                try await app.mail.deleteForever(keys, confirmed: confirmed)
            })
    }

    static func emptyTrash(app: AppModel) {
        let account = app.mail.scope.account
        let which = account.map { "in \(app.mail.accountDomain($0))" } ?? "in every account"
        app.confirm(ConfirmRequest(
            title: "Empty Trash?",
            message: "Every conversation in Trash \(which) will be permanently deleted from Gmail. This cannot be undone.",
            actionLabel: "Empty Trash", destructive: true, workingLabel: "Emptying…") { confirmed in
                try await app.mail.emptyTrash(account: account, confirmed: confirmed)
            })
    }
}
