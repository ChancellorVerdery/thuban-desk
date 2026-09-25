import SwiftUI
import ThubanDeskCore

/// Compose (design: Compose.dc.html): a 780 × 740 window over a scrim — From (account picker; replies keep the
/// thread's account), To / Cc / Bcc token fields, Subject, the formatting toolbar, the body with the collapsed
/// quote, attachments, and Discard · draft status · Save draft · Send (⌘↩). Send only opens the confirmation.
struct ComposeOverlay: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var model: ComposeModel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                theme.scrimColor
                    .contentShape(Rectangle())
                    .onTapGesture { }
                    .accessibilityHidden(true)
                ComposeWindow(model: model)
                    .frame(width: min(780, proxy.size.width - 40), height: min(740, proxy.size.height - 64))
                    .padding(.top, 44)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

struct ComposeWindow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var model: ComposeModel
    @State private var bodyHeight: CGFloat = 120
    @State private var linkOpen = false
    @State private var linkText = ""
    @State private var sizeOpen = false
    @State private var fromOpen = false
    @FocusState private var subjectFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            fieldRow("From") { fromPicker }
            fieldRow("To", trailing: ccBccButtons) {
                RecipientField(addresses: $model.draft.to, label: "To", autofocus: model.draft.to.isEmpty) { model.edited() }
            }
            .zIndex(3)
            if model.showCc {
                fieldRow("Cc") { RecipientField(addresses: $model.draft.cc, label: "Cc", autofocus: model.draft.cc.isEmpty) { model.edited() } }
                    .zIndex(2)
            }
            if model.showBcc {
                fieldRow("Bcc") { RecipientField(addresses: $model.draft.bcc, label: "Bcc", autofocus: model.draft.bcc.isEmpty) { model.edited() } }
                    .zIndex(1)
            }
            fieldRow("Subject") {
                TextField("", text: $model.draft.subject)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.inkColor)
                    .frame(height: 30)
                    .focused($subjectFocused)
                    .onChange(of: model.draft.subject) { _, _ in model.edited() }
                    .accessibilityLabel("Subject")
            }
            formatBar
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    RichTextEditor(model: model, theme: theme, height: $bodyHeight)
                        .frame(height: bodyHeight)
                        .frame(maxWidth: .infinity)
                    if let original = model.draft.original {
                        quote(original)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { model.editor.focus() }
            }
            .frame(maxHeight: .infinity)
            if !model.draft.attachments.isEmpty { attachmentStrip }
            footer
        }
        .background(theme.panelColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
        .shadow(color: theme.inkColor.opacity(theme.isDark ? 0 : 0.10), radius: 24, y: 10)
        .onExitCommand { model.closeKeepingDraft() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.draft.windowTitle)
    }

    // MARK: Title bar

    private var titleBar: some View {
        ZStack {
            Text(model.draft.windowTitle)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(theme.inkDimColor)
                .lineLimit(1)
                .padding(.horizontal, 60)
            HStack {
                IconButton(.close, label: "Close (keeps the draft)", size: 26, iconSize: 13) { model.closeKeepingDraft() }
                    .keyboardShortcut("w", modifiers: .command)
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .thubanHairline(.bottom, color: theme.lineColor)
    }

    // MARK: Rows

    private func fieldRow<Content: View, Trailing: View>(_ label: String, trailing: Trailing = EmptyView(), @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label).font(.system(size: 13.5)).foregroundStyle(theme.inkDimColor).frame(width: 56, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .frame(minHeight: 46)
        .thubanHairline(.bottom, color: theme.lineColor)
    }

    @ViewBuilder
    private var ccBccButtons: some View {
        HStack(spacing: 2) {
            if !model.showCc { MailToolButton(title: "Cc", icon: nil, fontSize: 13, height: 28) { model.showCc = true } }
            if !model.showBcc { MailToolButton(title: "Bcc", icon: nil, fontSize: 13, height: 28) { model.showBcc = true } }
        }
    }

    private var fromPicker: some View {
        let from = model.fromAddress
        return HStack(spacing: 6) {
            Button { fromOpen = true } label: {
                HStack(spacing: 8) {
                    TintDot(tint: app.mail.accountTint(model.draft.account), size: 8)
                    Text(from?.name ?? model.draft.account).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.inkColor)
                    Text(model.draft.account).font(.system(size: 14)).foregroundStyle(theme.inkDimColor)
                    Icon(.upDown, size: 13).foregroundStyle(theme.inkFaintColor)
                }
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(theme.fieldColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send from \(model.draft.account)")
            .popover(isPresented: $fromOpen, arrowEdge: .bottom) {
                MenuPopoverList(items: app.activeAccounts.map { account in
                    MenuPopoverItem(title: account.id, icon: nil, checked: account.id == model.draft.account,
                                    disabled: !model.draft.canChangeAccount && account.id != model.draft.account) { model.setAccount(account.id) }
                }) { fromOpen = false }
                .environment(\.thubanTheme, theme)
            }
            Text(model.draft.canChangeAccount ? (app.accounts.count > 1 ? "New mail goes from this account" : "") : "Same account the thread arrived in")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.inkFaintColor)
                .padding(.leading, 6)
                .lineLimit(1)
        }
    }

    // MARK: Formatting

    private var formatBar: some View {
        HStack(spacing: 2) {
            Button { sizeOpen = true } label: {
                HStack(spacing: 6) {
                    Text(model.editor.currentSize.rawValue).font(.system(size: 13)).foregroundStyle(theme.inkColor)
                    Icon(.chevronDown, size: 12).foregroundStyle(theme.inkFaintColor)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(theme.fieldColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Text size")
            .popover(isPresented: $sizeOpen, arrowEdge: .bottom) {
                MenuPopoverList(items: ComposeTextSize.allCases.map { size in
                    MenuPopoverItem(title: size.rawValue, checked: size == model.editor.currentSize) { model.editor.setSize(size) }
                }) { sizeOpen = false }
                .environment(\.thubanTheme, theme)
            }
            separator
            letterButton("B", label: "Bold (⌘B)", font: .system(size: 16, weight: .bold, design: .serif)) { model.editor.toggleTrait(.boldFontMask) }
            letterButton("I", label: "Italic (⌘I)", font: .system(size: 16, design: .serif).italic()) { model.editor.toggleTrait(.italicFontMask) }
            letterButton("U", label: "Underline (⌘U)", font: .system(size: 16, design: .serif), underline: true) { model.editor.toggleAttribute(.underlineStyle) }
            letterButton("S", label: "Strikethrough", font: .system(size: 16, design: .serif), strike: true) { model.editor.toggleAttribute(.strikethroughStyle) }
            separator
            formatIcon(.bulletList, "Bulleted list") { model.editor.toggleList(ordered: false) }
            formatIcon(.numberedList, "Numbered list") { model.editor.toggleList(ordered: true) }
            formatIcon(.quote, "Quote") { model.editor.toggleQuote() }
            separator
            formatIcon(.link, "Insert link") { linkOpen = true }
                .popover(isPresented: $linkOpen, arrowEdge: .bottom) { linkForm }
            formatIcon(.clearFormat, "Clear formatting") { model.editor.clearFormatting() }
            separator
            Button { model.addAttachments() } label: {
                HStack(spacing: 6) {
                    Icon(.attach, size: 16)
                    Text("Attach").font(.system(size: 13.5, weight: .semibold))
                }
                .foregroundStyle(theme.inkDimColor)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(GhostButtonStyle(height: 30, horizontalPadding: 0))
            .accessibilityLabel("Attach file")
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(theme.bgColor)
        .thubanHairline(.bottom, color: theme.lineColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting")
    }

    private var separator: some View {
        Rectangle().fill(theme.line2Color).frame(width: 1, height: 18).padding(.horizontal, 6)
    }

    private func letterButton(_ letter: String, label: String, font: Font, underline: Bool = false, strike: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(letter)
                .font(font)
                .underline(underline)
                .strikethrough(strike)
                .foregroundStyle(theme.inkDimColor)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(GhostButtonStyle(height: 30, horizontalPadding: 0))
        .help(label)
        .accessibilityLabel(label)
    }

    private func formatIcon(_ icon: IconName, _ label: String, action: @escaping () -> Void) -> some View {
        IconButton(icon, label: label, size: 30, iconSize: 16, action: action)
    }

    private var linkForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Link").font(ThubanFont.micro).kerning(0.96).textCase(.uppercase).foregroundStyle(theme.inkDimColor)
            TextField("https://…", text: $linkText)
                .textFieldStyle(.plain)
                .font(ThubanFont.body(14))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(theme.fieldColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                .onSubmit(applyLink)
            HStack {
                Spacer()
                Button("Cancel") { linkOpen = false }.buttonStyle(SecondaryButtonStyle(height: 30))
                Button("Add link", action: applyLink).buttonStyle(PrimaryButtonStyle(height: 30)).disabled(linkText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(theme.panelColor)
    }

    private func applyLink() {
        model.editor.setLink(linkText)
        linkText = ""
        linkOpen = false
    }

    // MARK: Quote

    private func quote(_ original: MailMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { model.quoteExpanded.toggle() } label: {
                Text("···")
                    .font(.system(size: 13, weight: .bold))
                    .kerning(1.3)
                    .foregroundStyle(theme.inkDimColor)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.quoteExpanded ? "Hide quoted text" : "Show quoted text")
            if model.draft.isForward {
                quoteBody(["---------- Forwarded message ---------",
                           "From: \(original.from?.description ?? "")",
                           "Subject: \(original.subject)"].joined(separator: "\n"),
                          body: model.quoteExpanded ? original.plainBody : ComposeDraft.quoteExcerpt(original))
            } else {
                quoteBody(ComposeDraft.quoteAttribution(original, zone: app.zone),
                          body: model.quoteExpanded ? original.plainBody : ComposeDraft.quoteExcerpt(original))
            }
        }
    }

    private func quoteBody(_ head: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(head)
            Text(body)
        }
        .font(.system(size: 14))
        .lineSpacing(3)
        .foregroundStyle(theme.inkDimColor)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, 14)
        .overlay(alignment: .leading) { Rectangle().fill(theme.line2Color).frame(width: 2) }
    }

    // MARK: Attachments

    private var attachmentStrip: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Array(model.draft.attachments.enumerated()), id: \.offset) { index, file in
                HStack(spacing: 6) {
                    Icon(.attach, size: 13).foregroundStyle(theme.brassInkColor)
                    Text(file.filename).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkColor).lineLimit(1)
                    Text(ByteSize.text(file.data.count)).font(.system(size: 12)).foregroundStyle(theme.inkDimColor)
                    Button { model.removeAttachment(at: index) } label: {
                        Icon(.close, size: 11).foregroundStyle(theme.inkFaintColor).frame(width: 18, height: 18).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(file.filename)")
                }
                .padding(.leading, 9)
                .padding(.trailing, 4)
                .frame(height: 28)
                .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
            }
            Color.clear.frame(width: 1, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .thubanHairline(.top, color: theme.lineColor)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            IconButton(.trash, label: "Discard draft", size: 34, iconSize: 15) { model.discard() }
            if let status = model.statusText {
                HStack(spacing: 6) {
                    switch model.saveState {
                    case .saved: Icon(.check, size: 13, lineWidth: 2.2).foregroundStyle(theme.posTextColor)
                    case .failed: Icon(.info, size: 13).foregroundStyle(theme.negTextColor)
                    case .saving: ProgressView().controlSize(.mini)
                    default: EmptyView()
                    }
                    Text(status)
                        .foregroundStyle(isFailure ? theme.negTextColor : theme.inkDimColor)
                        .lineLimit(1)
                }
                .font(.system(size: 13))
            }
            Spacer(minLength: 8)
            Button("Save draft") { Task { await model.saveDraft() } }
                .buttonStyle(SecondaryButtonStyle(height: 34))
                .disabled(!app.settings.writesEnabled)
                .help(app.settings.writesEnabled ? "Save to Gmail Drafts" : "Changes are off in Settings")
                .keyboardShortcut("s", modifiers: .command)
            Button { model.requestSend() } label: {
                HStack(spacing: 7) {
                    Icon(.sent, size: 15)
                    Text("Send")
                }
                .padding(.horizontal, 2)
            }
            .buttonStyle(PrimaryButtonStyle(height: 34))
            .keyboardShortcut(.return, modifiers: .command)
            .help("Send (⌘↩) — asks first")
            Text("⌘↩").font(ThubanFont.mono(12)).foregroundStyle(theme.inkFaintColor)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(theme.bgColor)
        .thubanHairline(.top, color: theme.lineColor)
    }

    private var isFailure: Bool {
        if case .failed = model.saveState { return true }
        return false
    }
}

// MARK: - Recipient tokens

/// A To / Cc / Bcc field: person chips (avatar, name, address, remove) + a text field; Return, comma or Tab turn
/// typed text into chips; Delete on an empty field removes the last chip; suggestions come from loaded mail.
struct RecipientField: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Binding var addresses: [EmailAddress]
    var label: String
    var autofocus: Bool = false
    var onChange: () -> Void
    @State private var typed = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    var body: some View {
        let suggestions = ComposeDraft.suggestions(typed, contacts: app.mail.contacts, excluding: addresses, own: app.ownAddresses)
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(addresses.enumerated()), id: \.offset) { index, address in
                chip(address, index: index)
            }
            TextField("", text: $typed)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(theme.inkColor)
                .frame(minWidth: 120)
                .frame(height: 30)
                .focused($focused)
                .accessibilityLabel("Add \(label) recipient")
                .onSubmit { commit(suggestions) }
                .onChange(of: typed) { _, text in
                    highlighted = 0
                    if text.contains(",") || text.contains(";") || (text.contains(" ") && ComposeDraft.isValidAddress(text.trimmingCharacters(in: .whitespaces))) {
                        commit([])
                    }
                }
                .onKeyPress(.delete) {
                    guard typed.isEmpty, !addresses.isEmpty else { return .ignored }
                    addresses.removeLast()
                    onChange()
                    return .handled
                }
                .onKeyPress(.tab) {
                    guard !typed.trimmingCharacters(in: .whitespaces).isEmpty else { return .ignored }
                    commit(suggestions)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard !suggestions.isEmpty else { return .ignored }
                    highlighted = min(highlighted + 1, suggestions.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !suggestions.isEmpty else { return .ignored }
                    highlighted = max(highlighted - 1, 0)
                    return .handled
                }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused, ComposeDraft.isValidAddress(typed.trimmingCharacters(in: .whitespaces)) { commit([]) }
                }
        }
        .overlay(alignment: .bottomLeading) {
            if focused, !suggestions.isEmpty {
                suggestionList(suggestions)
                    .offset(y: CGFloat(suggestions.count) * 34 + 14)
            }
        }
        .zIndex(focused ? 10 : 0)
        .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
    }

    private func chip(_ address: EmailAddress, index: Int) -> some View {
        HStack(spacing: 6) {
            AvatarView(name: address.displayName, tint: MailAvatarTint.tint(for: address, own: app.ownAddresses), size: 22)
            if let name = address.name {
                Text(name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(theme.inkColor)
                Text(address.email).font(.system(size: 12.5)).foregroundStyle(theme.inkDimColor)
            } else {
                Text(address.email).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(ComposeDraft.isValidAddress(address.email) ? theme.inkColor : theme.negTextColor)
            }
            Button {
                addresses.remove(at: index)
                onChange()
            } label: {
                Icon(.close, size: 11).foregroundStyle(theme.inkFaintColor).frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(address.displayName)")
        }
        .lineLimit(1)
        .padding(.leading, 3)
        .padding(.trailing, 4)
        .frame(height: 28)
        .background(theme.panel2Color, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.line2Color, lineWidth: 1))
        .help(address.description)
    }

    private func suggestionList(_ suggestions: [EmailAddress]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, contact in
                Button { pick(contact) } label: {
                    HStack(spacing: 8) {
                        AvatarView(name: contact.displayName, tint: MailAvatarTint.tint(for: contact, own: app.ownAddresses), size: 22)
                        Text(contact.name ?? contact.email).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(theme.inkColor)
                        if contact.name != nil { Text(contact.email).font(.system(size: 12.5)).foregroundStyle(theme.inkDimColor) }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(index == highlighted ? theme.panel2Color : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 380)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
        .shadow(color: theme.inkColor.opacity(theme.isDark ? 0 : 0.08), radius: 12, y: 6)
    }

    private func pick(_ contact: EmailAddress) {
        addresses = ComposeDraft.adding([contact], to: addresses)
        typed = ""
        onChange()
    }

    private func commit(_ suggestions: [EmailAddress]) {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let parsed = ComposeDraft.parseRecipients(text)
        if parsed.addresses.isEmpty, suggestions.indices.contains(highlighted) {
            pick(suggestions[highlighted])
            return
        }
        addresses = ComposeDraft.adding(parsed.addresses, to: addresses)
        // Keep an unfinished entry as a (red) chip so nothing typed is lost.
        let rest = parsed.rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,;"))
        if !rest.isEmpty { addresses.append(EmailAddress(rest)) }
        typed = ""
        onChange()
    }
}
