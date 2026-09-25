import AppKit
import SwiftUI
import ThubanDeskCore
import UniformTypeIdentifiers

/// The reader (design): serif subject, label chips + account chip + "3 messages", earlier messages collapsed to one
/// line each (click to expand), the latest message as a card — header with Filter sender and ⋯, the body in a
/// sandboxed web view (remote images blocked until "Load images"), attachments, the invitation card with RSVP —
/// and Reply / Reply all / Forward.
struct MailReaderPane: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var error: String?

    var body: some View {
        let mail = app.mail
        Group {
            if let key = mail.selection {
                if let thread = mail.detail(key) {
                    ScrollView {
                        MailThreadView(thread: thread)
                            .padding(EdgeInsets(top: 22, leading: 28, bottom: 28, trailing: 28))
                            .frame(maxWidth: 900, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id(key)
                } else if let error {
                    EmptyState(icon: .info, title: "This conversation couldn’t load", message: error) {
                        Button("Try again") { load(key) }.buttonStyle(SecondaryButtonStyle(height: 32))
                    }
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task(id: key) { load(key) }
                }
            } else if !mail.checked.isEmpty {
                EmptyState(icon: .check, title: "\(mail.checked.count) selected", message: "Use the bar above the list to archive, label or trash them together.") { EmptyView() }
            } else {
                EmptyState(icon: .mail, title: "No conversation open", message: "Choose a conversation from the list. ↑ and ↓ move between them.") { EmptyView() }
            }
        }
        .background(theme.bgColor)
    }

    private func load(_ key: ThreadKey) {
        error = nil
        Task {
            do { _ = try await app.mail.thread(key) } catch { self.error = error.localizedDescription }
        }
    }
}

struct MailThreadView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var thread: MailThread

    var body: some View {
        let mail = app.mail
        let showTrashed = mail.scope.folder == .trash
        let visible = thread.messages.filter { !$0.isDraft && (showTrashed || !$0.labelIDs.contains(GmailSystemLabel.trash)) }
        let drafts = thread.messages.filter(\.isDraft)
        let summary = thread.summary
        let labels = mail.labelNames(for: summary)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(thread.subject)
                    .font(ThubanFont.display(24))
                    .foregroundStyle(theme.inkColor)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    ForEach(labels, id: \.self) { name in LabelChip(name: name, tint: mail.labelTint(name)) }
                    HStack(spacing: 6) {
                        TintDot(tint: mail.accountTint(thread.account), size: 7)
                        Text(thread.account)
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.inkDimColor)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .help("Arrived in \(thread.account)")
                    Text("\(visible.count) message\(visible.count == 1 ? "" : "s")")
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                        .padding(.leading, 4)
                }
            }
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, message in
                let isLast = index == visible.count - 1
                if isLast || mail.expandedMessages.contains(message.id) || (message.isUnread && visible.count > 1) {
                    MailMessageCard(thread: thread, message: message, showsReplyButtons: isLast)
                } else {
                    CollapsedMessageRow(message: message) { mail.expandedMessages.insert(message.id) }
                }
            }
            ForEach(drafts) { draft in
                DraftRow(thread: thread, message: draft)
            }
        }
    }
}

/// An earlier message, one line: avatar · name · snippet · date.
struct CollapsedMessageRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var message: MailMessage
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AvatarView(name: message.from?.displayName ?? "?", tint: MailAvatarTint.tint(for: message.from, own: app.ownAddresses), size: 30)
                Text(message.from?.displayName ?? "(unknown)").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.inkColor).lineLimit(1).fixedSize()
                Text(message.snippet.isEmpty ? message.plainBody : message.snippet)
                    .font(.system(size: 13.5)).foregroundStyle(theme.inkDimColor).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(MailDateText.reader(message.date, now: app.now(), zone: app.zone)).font(.system(size: 12.5)).foregroundStyle(theme.inkDimColor).fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(hovering ? theme.panel2Color : theme.panelColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Message from \(message.from?.displayName ?? "unknown"), \(MailDateText.reader(message.date, now: app.now(), zone: app.zone)). Expand.")
    }
}

/// A saved draft in the thread: continue it in Compose.
struct DraftRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var thread: MailThread
    var message: MailMessage

    var body: some View {
        Button {
            ComposeModel.openDraft(message, in: thread, app: app)
        } label: {
            HStack(spacing: 12) {
                Icon(.drafts, size: 16).foregroundStyle(theme.brassInkColor).frame(width: 30)
                Text("Draft").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.brassInkColor)
                Text(message.plainBody.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 13.5)).foregroundStyle(theme.inkDimColor).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Continue").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.brassInkColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(theme.accentTintColor.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.lineColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue your draft")
    }
}

/// The expanded message card.
struct MailMessageCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var thread: MailThread
    var message: MailMessage
    var showsReplyButtons: Bool
    @State private var bodyHeight: CGFloat = 60
    @State private var filterOpen = false
    @State private var moreOpen = false

    var body: some View {
        let mail = app.mail
        let own = app.ownAddresses
        let allowImages = app.settings.loadRemoteImages || mail.imagesAllowed.contains(thread.key)
        let designed = MailReaderStyle.isDesigned(message.html)
        let paper = designed && theme.isDark
        let prepared = PreparedBodies.body(for: message, allowImages: allowImages, theme: theme, scale: textScale, paper: paper) {
            MailHTML.prepare(html: message.html, text: message.text, allowRemoteImages: allowImages,
                             css: MailReaderStyle.css(theme: theme, fontSize: 15 * textScale, paper: paper),
                             inlineImages: inlineImages, inlineTypes: inlineTypes)
        }
        let invite = mail.invitation(for: message)
        let fromSelf = message.from.map { own.contains($0.normalized) } ?? false
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                AvatarView(name: message.from?.displayName ?? "?", tint: MailAvatarTint.tint(for: message.from, own: own), size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(message.from?.displayName ?? "(unknown sender)").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(theme.inkColor)
                        if let email = message.from?.email, message.from?.name != nil {
                            Text("<\(email)>").font(.system(size: 13)).foregroundStyle(theme.inkDimColor)
                        }
                    }
                    .lineLimit(1)
                    .textSelection(.enabled)
                    Text("\(recipientsText(own: own)) · \(MailDateText.reader(message.date, now: app.now(), zone: app.zone))")
                        .font(.system(size: 13)).foregroundStyle(theme.inkDimColor).lineLimit(1)
                        .help(fullRecipients)
                }
                Spacer(minLength: 8)
                if let from = message.from, !fromSelf {
                    MailToolButton(title: "Filter sender", icon: .filter, fontSize: 13, height: 30, help: "Always file mail from \(from.email)") { filterOpen = true }
                        .popover(isPresented: $filterOpen, arrowEdge: .bottom) {
                            FilterSenderForm(sender: from, account: thread.account) { filterOpen = false }
                                .environment(\.thubanTheme, theme)
                                .environment(app)
                        }
                }
                MenuPopoverButton(icon: .more, label: "More actions", size: 30, iconSize: 15) { moreItems }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .thubanHairline(.bottom, color: theme.lineColor)

            VStack(alignment: .leading, spacing: 12) {
                if prepared.hasRemoteImages && !allowImages {
                    RemoteImagesBar { mail.imagesAllowed.insert(thread.key) }
                }
                MailWebView(document: prepared.document, height: $bodyHeight, frozen: mail.compose != nil || app.pendingConfirmation != nil)
                    .frame(height: bodyHeight)
                    .clipShape(RoundedRectangle(cornerRadius: paper ? 8 : 0, style: .continuous))
                let files = message.attachments.filter { !$0.isInline }
                if !files.isEmpty {
                    AttachmentList(files: files, messageID: message.id, account: thread.account)
                }
                if let invite {
                    InvitationCard(invite: invite)
                }
            }
            .padding(EdgeInsets(top: 16, leading: 62, bottom: 18, trailing: 18))

            if showsReplyButtons {
                HStack(spacing: 8) {
                    replyButton("Reply", .reply) { ComposeModel.openReply(to: message, in: thread.key, all: false, app: app) }
                    replyButton("Reply all", .replyAll) { ComposeModel.openReply(to: message, in: thread.key, all: true, app: app) }
                    replyButton("Forward", .forward) { ComposeModel.openForward(message, in: thread.key, app: app) }
                }
                .padding(EdgeInsets(top: 0, leading: 62, bottom: 16, trailing: 18))
            }
        }
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
    }

    private var inlineImages: [String: Data] {
        Dictionary(message.attachments.compactMap { a in a.contentID.flatMap { cid in a.data.map { (cid, $0) } } }, uniquingKeysWith: { a, _ in a })
    }

    private var inlineTypes: [String: String] {
        Dictionary(message.attachments.compactMap { a in a.contentID.map { ($0, a.mimeType) } }, uniquingKeysWith: { a, _ in a })
    }

    private var moreItems: [MenuPopoverItem] {
        let mail = app.mail
        return [
            MenuPopoverItem(title: "Reply", icon: .reply) { ComposeModel.openReply(to: message, in: thread.key, all: false, app: app) },
            MenuPopoverItem(title: "Reply all", icon: .replyAll) { ComposeModel.openReply(to: message, in: thread.key, all: true, app: app) },
            MenuPopoverItem(title: "Forward", icon: .forward) { ComposeModel.openForward(message, in: thread.key, app: app) },
            .separator,
            MenuPopoverItem(title: "Mark unread", icon: .markUnread) { Task { await mail.perform(.markUnread, on: [thread.key]) } },
            MenuPopoverItem(title: "Load images", icon: .eye, disabled: mail.imagesAllowed.contains(thread.key) || app.settings.loadRemoteImages) {
                mail.imagesAllowed.insert(thread.key)
            },
            MenuPopoverItem(title: "Copy sender address", icon: .mail, disabled: message.from == nil) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.from?.email ?? "", forType: .string)
            },
        ]
    }

    /// "to me", "to MATH 2210 students", "to Priya", "to me, Maya +2".
    private func recipientsText(own: Set<String>) -> String {
        let people = message.to + message.cc
        if people.isEmpty { return "to undisclosed recipients" }
        let names = people.map { own.contains($0.normalized) ? "me" : ($0.name.map { String($0.split(separator: " ").first ?? Substring($0)) } ?? $0.email) }
        let shown = names.prefix(2).joined(separator: ", ")
        return "to " + shown + (names.count > 2 ? " +\(names.count - 2)" : "")
    }

    private var fullRecipients: String {
        var lines = ["To: " + message.to.map(\.description).joined(separator: ", ")]
        if !message.cc.isEmpty { lines.append("Cc: " + message.cc.map(\.description).joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }

    private func replyButton(_ title: String, _ icon: IconName, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Icon(icon, size: 15)
                Text(title)
            }
        }
        .buttonStyle(SecondaryButtonStyle(height: 32))
        .accessibilityLabel(title)
    }
}

/// "Images are hidden to protect your privacy · Load images".
struct RemoteImagesBar: View {
    @Environment(\.thubanTheme) private var theme
    var load: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Icon(.eye, size: 14).foregroundStyle(theme.inkDimColor)
            Text("Remote images are hidden, so the sender can’t tell you opened this.")
                .font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Load images", action: load)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.brassInkColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Attachment chips: icon, name, size; click saves (Save panel), Quick Look is the system's job after that.
struct AttachmentList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var files: [MailAttachment]
    var messageID: String
    var account: String
    @State private var busy: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(files) { file in
                    Button { save(file) } label: {
                        HStack(spacing: 8) {
                            Icon(.attach, size: 14).foregroundStyle(theme.brassInkColor)
                            Text(file.filename).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkColor).lineLimit(1)
                            Text(ByteSize.text(file.size)).font(.system(size: 12)).foregroundStyle(theme.inkDimColor)
                            if busy == file.id { ProgressView().controlSize(.mini) }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Save \(file.filename)")
                    .accessibilityLabel("Attachment \(file.filename), \(ByteSize.text(file.size)). Save.")
                }
                Color.clear.frame(width: 1, height: 1)
            }
            if let error { Text(error).font(ThubanFont.small).foregroundStyle(theme.negTextColor) }
        }
    }

    private func save(_ file: MailAttachment) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.filename
        if let type = UTType(mimeType: file.mimeType) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = file.id
        Task {
            defer { busy = nil }
            do {
                let data = try await app.mail.attachmentData(file, messageID: messageID, account: account)
                try data.write(to: url, options: .atomic)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Sanitized bodies are parsed once per message / theme / image choice (SwiftSoup is not free; the card re-renders
/// whenever the mail store changes).
@MainActor
enum PreparedBodies {
    private static var cache: [String: MailHTML.Prepared] = [:]
    private static var order: [String] = []

    static func body(for message: MailMessage, allowImages: Bool, theme: ResolvedTheme, scale: Double, paper: Bool,
                     make: () -> MailHTML.Prepared) -> MailHTML.Prepared {
        let key = "\(message.id)|\(allowImages)|\(theme.schemeId)|\(theme.isDark)|\(theme.ink)|\(scale)|\(paper)"
        if let hit = cache[key] { return hit }
        let made = make()
        cache[key] = made
        order.append(key)
        if order.count > 48 { cache[order.removeFirst()] = nil }
        return made
    }
}
