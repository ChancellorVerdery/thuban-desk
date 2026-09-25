import SwiftUI
import ThubanDeskCore

/// Board "Thread": back to the mailbox, Star and More; the subject in serif; label / account / count chips; earlier
/// messages collapsed to one line each and the latest open (sanitized HTML body, the invitation card when the message
/// is about an event, attachments); a bottom bar with Archive, Trash, Label, Unread and Reply.
struct ThreadScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    var key: ThreadKey
    /// iPad detail column: no back button (the list is beside it).
    var embedded = false
    @State private var error: String?

    var body: some View {
        let thread = app.mail.detail(key)
        VStack(spacing: 0) {
            navRow(thread)
            ScrollView {
                if let thread {
                    content(thread)
                } else if let error {
                    PhoneEmptyState(icon: .mail, text: error)
                } else {
                    ProgressView().tint(theme.brassInkColor).padding(60).frame(maxWidth: .infinity)
                }
            }
            .scrollIndicators(.hidden)
            if !embedded { ThreadActionBar(key: key) }
        }
        .background(theme.bgColor.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: key) {
            do {
                _ = try await app.mail.thread(key)
                await app.mail.open(key)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func navRow(_ thread: MailThread?) -> some View {
        HStack(spacing: 4) {
            if !embedded {
                BackButton(title: router.currentMailScope.title) {
                    if case .thread = router.mailPath.last { router.mailPath.removeLast() }
                }
            }
            Spacer()
            if embedded {
                ThreadToolbarIcons(key: key)
            }
            let starred = thread?.isStarred ?? false
            Button { Task { await app.mail.perform(starred ? .unstar : .star, on: [key]); _ = try? await app.mail.thread(key, force: false) } } label: {
                ZStack {
                    if starred { IconFill(.star, size: 22).foregroundStyle(theme.accentColor) }
                    Icon(.star, size: 22).foregroundStyle(theme.brassInkColor)
                }
                    .frame(width: PhoneMetrics.hit, height: PhoneMetrics.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(starred ? "Remove star" : "Star")
            Menu {
                ThreadMenu(keys: [key], summary: app.mail.summary(key))
            } label: {
                Icon(.moreCircle, size: 22).foregroundStyle(theme.brassInkColor).frame(width: PhoneMetrics.hit, height: PhoneMetrics.hit)
            }
            .accessibilityLabel("More actions")
            if embedded {
                Button { app.requestReply(to: key) } label: {
                    HStack(spacing: 6) { Icon(.reply, size: 18); Text("Reply").font(PhoneFont.bodySemibold) }
                        .fixedSize()
                        .foregroundStyle(theme.onAccentInk)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: PhoneMetrics.navHeight + (embedded ? 12 : 0))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.lineColor).frame(height: 1) }
    }

    private func content(_ thread: MailThread) -> some View {
        let messages = thread.messages.filter { !$0.isDraft }
        let labels = MailMerge.userLabelNames(Array(thread.labelIDs), labels: app.mail.labels[key.account] ?? [])
        return VStack(alignment: .leading, spacing: 12) {
            Text(thread.subject)
                .font(PhoneFont.display(embedded ? .largeTitle : .title))
                .foregroundStyle(theme.inkColor)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                ForEach(labels, id: \.self) { PhoneChip(text: $0) }
                PhoneChip(text: key.account.split(separator: "@").last.map(String.init) ?? key.account, tint: .accent, dot: app.mail.accountTint(key.account))
                PhoneChip(text: "\(messages.count) message\(messages.count == 1 ? "" : "s")")
            }
            MessagesCard(thread: thread)
        }
        .padding(.horizontal, PhoneMetrics.gutter)
        .padding(.top, 14)
        .padding(.bottom, 28)
    }
}

/// iPad thread toolbar: Archive, Trash, Label, Unread (the phone has them in the bottom bar).
struct ThreadToolbarIcons: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    var key: ThreadKey

    var body: some View {
        NavIconButton(.archive, label: "Archive") { Task { await app.mail.perform(.archive, on: [key]); router.padThread = nil } }
        NavIconButton(.trash, label: "Trash") { Task { await app.mail.perform(.trash, on: [key]); router.padThread = nil } }
        NavIconButton(.label, label: "Label") { router.labelTargets = [key] }
        NavIconButton(.mail, label: "Mark unread") { Task { await app.mail.perform(.markUnread, on: [key]) } }
    }
}

/// The earlier messages (one line each, tap to open) and the open ones in full.
private struct MessagesCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var thread: MailThread

    var body: some View {
        let messages = thread.messages.filter { !$0.isDraft }
        let draft = thread.messages.last(where: \.isDraft)
        let mail = app.mail
        InsetCard {
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                if index > 0 { Rectangle().fill(theme.lineColor).frame(height: 1) }
                let open = index == messages.count - 1 || mail.expandedMessages.contains(message.id)
                if open {
                    MessageView(message: message, thread: thread)
                } else {
                    Button { mail.expandedMessages.insert(message.id) } label: { collapsedRow(message) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows the whole message")
                }
            }
            if let draft {
                Rectangle().fill(theme.lineColor).frame(height: 1)
                Button { app.requestReply(to: thread.key) } label: {
                    HStack(spacing: 10) {
                        Icon(.drafts, size: 18).foregroundStyle(theme.negTextColor)
                        Text("Draft").font(PhoneFont.secondarySemibold).foregroundStyle(theme.negTextColor)
                        Text(draft.snippet).font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(DeskFormat.listDate(draft.date, now: app.now(), zone: app.zone)).font(PhoneFont.footnote).foregroundStyle(theme.inkFaintColor)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens a reply")
            }
        }
    }

    private func collapsedRow(_ message: MailMessage) -> some View {
        let own = app.ownAddresses
        let isMe = message.from.map { own.contains($0.normalized) } ?? false
        return HStack(spacing: 10) {
            PhoneAvatar(name: isMe ? (app.primaryAccount?.displayName ?? "Me") : (message.from?.displayName ?? "?"),
                        tint: AvatarTint.tint(for: message.from, own: own), size: 30, ringed: isMe)
            VStack(alignment: .leading, spacing: 0) {
                Text(isMe ? "You" : (message.from?.displayName ?? "Unknown")).font(PhoneFont.secondarySemibold).foregroundStyle(theme.inkColor)
                Text(message.snippet).font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(DeskFormat.listDate(message.date, now: app.now(), zone: app.zone)).font(PhoneFont.footnote).foregroundStyle(theme.inkFaintColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

private struct MessageView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    var message: MailMessage
    var thread: MailThread
    @State private var height: CGFloat = 60

    var body: some View {
        let own = app.ownAddresses
        let isMe = message.from.map { own.contains($0.normalized) } ?? false
        let allowImages = app.settings.loadRemoteImages || app.mail.imagesAllowed.contains(thread.key)
        let prepared = MailHTML.prepare(html: message.html, text: message.text, allowRemoteImages: allowImages,
                                        css: MailReaderStyle.css(theme: app.theme, fontSize: bodySize))
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                PhoneAvatar(name: isMe ? (app.primaryAccount?.displayName ?? "Me") : (message.from?.displayName ?? "?"),
                            tint: AvatarTint.tint(for: message.from, own: own), size: 36, ringed: isMe)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isMe ? "You" : (message.from?.displayName ?? "Unknown")).font(PhoneFont.bodySemibold).foregroundStyle(theme.inkColor)
                    Text(recipientLine(own: own)).font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(DeskFormat.listDate(message.date, now: app.now(), zone: app.zone)).font(PhoneFont.footnote).foregroundStyle(theme.inkFaintColor)
            }
            .accessibilityElement(children: .combine)
            if prepared.hasRemoteImages, !allowImages {
                Button { app.mail.imagesAllowed.insert(thread.key) } label: {
                    HStack(spacing: 6) { Icon(.eye, size: 16); Text("Load images").font(PhoneFont.footnoteSemibold) }
                        .foregroundStyle(theme.brassInkColor)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .background(theme.fillColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            MailBodyView(document: prepared.document, height: $height)
                .frame(height: height)
            if let invite = app.mail.invitation(for: message) {
                InvitationCardView(item: invite, embedded: true)
            }
            let files = message.attachments.filter { !$0.isInline }
            if !files.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(files) { file in
                        HStack(spacing: 8) {
                            Icon(.attach, size: 16).foregroundStyle(theme.inkDimColor)
                            Text(file.filename).font(PhoneFont.footnoteSemibold).foregroundStyle(theme.inkColor).lineLimit(1)
                            Text(ByteSize.text(file.size)).font(PhoneFont.footnote).foregroundStyle(theme.inkFaintColor)
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 36)
                        .background(theme.fillColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(16)
    }

    private var bodySize: Double {
        switch typeSize {
        case .xSmall, .small: return 15
        case .medium: return 16
        case .large: return 17
        case .xLarge: return 19
        case .xxLarge: return 21
        case .xxxLarge: return 23
        default: return 26
        }
    }

    private func recipientLine(own: Set<String>) -> String {
        let to = message.to.map { own.contains($0.normalized) ? "me" : $0.displayName }
        var line = "to \(to.isEmpty ? "me" : to.joined(separator: ", "))"
        if let from = message.from { line += " · \(from.email)" }
        return line
    }
}

/// The thread's bottom bar (replaces the tab bar): Archive, Trash, Label, Unread, Reply.
struct ThreadActionBar: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    var key: ThreadKey

    var body: some View {
        HStack(spacing: 0) {
            item(.archive, "Archive") { Task { await app.mail.perform(.archive, on: [key]); pop() } }
            item(.trash, "Trash") { Task { await app.mail.perform(.trash, on: [key]); pop() } }
            item(.label, "Label") { router.labelTargets = [key] }
            item(.markUnread, "Unread") { Task { await app.mail.perform(.markUnread, on: [key]); pop() } }
            item(.reply, "Reply") { app.requestReply(to: key) }
        }
        .padding(.horizontal, 8)
        .background(theme.panelColor.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(theme.lineColor).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thread actions")
    }

    private func pop() {
        if case .thread = router.mailPath.last { router.mailPath.removeLast() }
    }

    private func item(_ icon: IconName, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Icon(icon, size: 24)
                Text(title).font(PhoneFont.tabLabel)
            }
            .foregroundStyle(theme.brassInkColor)
            .frame(maxWidth: .infinity, minHeight: 49)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
