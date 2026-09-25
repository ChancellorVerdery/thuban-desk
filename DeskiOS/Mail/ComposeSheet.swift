import SwiftUI
import ThubanDeskCore
import UIKit
import UniformTypeIdentifiers

/// Board "Reply sheet": Cancel / Reply / Send; To chips (+), Cc/Bcc, From (a picker for new mail; for a reply the
/// thread's account with the reason under it), Subject, the body, "Show quoted text", and a bottom bar with attach,
/// bold, italic, bullets and "Draft saved 2:41 PM". Send opens the confirm sheet; nothing is sent without it.
struct ComposeSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    @Bindable var model: PhoneComposeModel
    @State private var editor = RichTextController()
    @State private var importing = false
    @FocusState private var toFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            // Fixed fields on top; the body fills everything down to the quoted-text chip and the formatting bar
            // and scrolls inside itself with no indicator.
            VStack(alignment: .leading, spacing: 0) {
                if let error = model.error {
                    PhoneBanner(text: error) { model.error = nil }.padding(.horizontal, 16).padding(.vertical, 8)
                }
                recipientRow("To", list: $model.draft.to, text: $model.toText, focus: $toFocused, addButton: true)
                divider
                if model.showCcBcc {
                    recipientRow("Cc", list: $model.draft.cc, text: $model.ccText, focus: nil, addButton: false)
                    divider
                    recipientRow("Bcc", list: $model.draft.bcc, text: $model.bccText, focus: nil, addButton: false)
                    divider
                } else {
                    Button { model.showCcBcc = true } label: {
                        fieldLabel("Cc/Bcc").frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, 16).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add Cc or Bcc")
                    divider
                }
                fromRow
                divider
                HStack(spacing: 8) {
                    fieldLabel("Subject").frame(width: 72, alignment: .leading)
                    TextField("", text: $model.draft.subject)
                        .font(PhoneFont.body)
                        .foregroundStyle(theme.inkColor)
                        .accessibilityLabel("Subject")
                        .onChange(of: model.draft.subject) { _, _ in model.scheduleSave() }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                divider
            }
            RichTextView(controller: editor, initial: model.initialBody, placeholder: "Message") { text in
                model.bodyChanged(text)
            }
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .accessibilityLabel("Message")
            if !model.draft.attachments.isEmpty { attachments }
            quote
            toolbar
        }
        .background(theme.panelColor.ignoresSafeArea())
        .presentationBackground(theme.panelColor)
        .presentationCornerRadius(12)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(true)
        .confirmHost(active: true)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            attach(result)
        }
        .onAppear {
            guard !SmokeHarness.isEnabled else { return }
            if model.draft.to.isEmpty { toFocused = true } else { editor.focus() }
        }
    }

    private var divider: some View { Rectangle().fill(theme.lineColor).frame(height: 1) }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(PhoneFont.body).foregroundStyle(theme.inkFaintColor)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            NavTextButton("Cancel") {
                Task {
                    await model.saveDraft()
                    model.close()
                    router.compose = nil
                }
            }
            Spacer()
            Text(model.title).font(PhoneFont.inlineTitle).foregroundStyle(theme.inkColor).accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                model.requestSend { router.compose = nil }
            } label: {
                HStack(spacing: 6) {
                    Text("↑").font(.body.weight(.bold)).accessibilityHidden(true)
                    Text("Send").font(PhoneFont.bodySemibold)
                }
                .foregroundStyle(theme.onAccentInk)
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
                .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(minHeight: PhoneMetrics.hit)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send")
            .accessibilityHint("Asks before sending")
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.top, 12)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { divider }
    }

    // MARK: Fields

    private func recipientRow(_ label: String, list: Binding<[EmailAddress]>, text: Binding<String>, focus: FocusState<Bool>.Binding?, addButton: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            fieldLabel(label).frame(width: 72, alignment: .leading)
            FlowChips(addresses: list.wrappedValue) { address in
                list.wrappedValue.removeAll { $0.normalized == address.normalized }
                model.scheduleSave()
            }
            recipientField(text: text, list: list, focus: focus, label: label)
            if addButton {
                Menu {
                    let suggestions = app.mail.contacts.filter { contact in !list.wrappedValue.contains { $0.normalized == contact.normalized } }.prefix(8)
                    ForEach(Array(suggestions), id: \.normalized) { contact in
                        Button(contact.name.map { "\($0) <\(contact.email)>" } ?? contact.email) {
                            list.wrappedValue = ComposeDraft.adding([contact], to: list.wrappedValue)
                        }
                    }
                } label: {
                    ZStack {
                        Circle().strokeBorder(theme.brassInkColor, lineWidth: 1.5).frame(width: 22, height: 22)
                        Icon(.plus, size: 14, lineWidth: 2).foregroundStyle(theme.brassInkColor)
                    }
                    .frame(width: PhoneMetrics.hit, height: PhoneMetrics.hit)
                }
                .accessibilityLabel("Add recipient")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, addButton ? 4 : 16)
        .frame(minHeight: 48)
    }

    @ViewBuilder private func recipientField(text: Binding<String>, list: Binding<[EmailAddress]>, focus: FocusState<Bool>.Binding?, label: String) -> some View {
        let field = TextField("", text: text)
            .font(PhoneFont.body)
            .foregroundStyle(theme.inkColor)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .accessibilityLabel("\(label) recipients")
            .onSubmit { commit(text, into: list) }
            .onChange(of: text.wrappedValue) { _, value in
                if value.hasSuffix(",") || value.hasSuffix(" ") || value.hasSuffix(";") { commit(text, into: list) }
            }
        if let focus { field.focused(focus) } else { field }
    }

    private func commit(_ text: Binding<String>, into list: Binding<[EmailAddress]>) {
        let parsed = ComposeDraft.parseRecipients(text.wrappedValue)
        guard !parsed.addresses.isEmpty else { return }
        list.wrappedValue = ComposeDraft.adding(parsed.addresses, to: list.wrappedValue)
        text.wrappedValue = parsed.rest
        model.scheduleSave()
    }

    private var fromRow: some View {
        let from = model.fromAddress
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                fieldLabel("From").frame(width: 72, alignment: .leading)
                Menu {
                    ForEach(app.activeAccounts) { account in
                        Button(account.email) { model.draft.account = account.id; model.scheduleSave() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(theme.color(for: app.mail.accountTint(model.draft.account))).frame(width: 7, height: 7)
                        Text(from?.email ?? model.draft.account).font(PhoneFont.body).foregroundStyle(theme.inkColor).lineLimit(1)
                        Spacer(minLength: 4)
                        if model.draft.canChangeAccount { Icon(.upDown, size: 14).foregroundStyle(theme.chevronColor) }
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .disabled(!model.draft.canChangeAccount)
                .accessibilityLabel("From, \(from?.email ?? model.draft.account)")
            }
            if !model.draft.canChangeAccount {
                Text("The thread arrived in this account, so the \(model.draft.isForward ? "forward" : "reply") goes from it.")
                    .font(.caption).foregroundStyle(theme.inkDimColor)
                    .padding(.leading, 80)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var quote: some View {
        if let chip = model.quoteChip {
            VStack(alignment: .leading, spacing: 8) {
                Button { model.showQuote.toggle() } label: {
                    Text(model.showQuote ? "Hide quoted text" : chip)
                        .font(PhoneFont.footnoteSemibold)
                        .foregroundStyle(theme.inkDimColor)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                        .background(theme.fillColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                if model.showQuote, let text = model.quoteText {
                    ScrollView {
                        Text(text)
                            .font(PhoneFont.footnote)
                            .foregroundStyle(theme.inkDimColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 10)
                            .overlay(alignment: .leading) { Rectangle().fill(theme.line2Color).frame(width: 2) }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: 180)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
    }

    private var attachments: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(model.draft.attachments.enumerated()), id: \.offset) { index, file in
                HStack(spacing: 8) {
                    Icon(.attach, size: 16).foregroundStyle(theme.inkDimColor)
                    Text(file.filename).font(PhoneFont.footnoteSemibold).foregroundStyle(theme.inkColor).lineLimit(1)
                    Text(ByteSize.text(file.data.count)).font(PhoneFont.footnote).foregroundStyle(theme.inkFaintColor)
                    Spacer()
                    Button { model.draft.attachments.remove(at: index); model.scheduleSave() } label: {
                        Icon(.close, size: 13, lineWidth: 2).foregroundStyle(theme.inkDimColor).frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(file.filename)")
                }
                .padding(.leading, 10)
                .background(theme.fillColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            toolButton("Attach file") { Icon(.attach, size: 22) } action: { importing = true }
            toolButton("Bold") { Text("B").font(.system(size: 18, weight: .bold)) } action: { editor.toggle(.traitBold) }
            toolButton("Italic") { Text("I").font(.system(size: 18, design: .serif).italic()) } action: { editor.toggle(.traitItalic) }
            toolButton("Bulleted list") { Icon(.bulletList, size: 22) } action: { editor.toggleBullet() }
            Spacer()
            Text(savedText).font(PhoneFont.footnote).foregroundStyle(theme.inkFaintColor).lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(minHeight: 52)
        .background(theme.fillColor.opacity(0.6).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { divider }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting")
    }

    private var savedText: String {
        if model.isSaving { return "Saving draft…" }
        guard let saved = model.savedAt else { return "" }
        return "Draft saved \(CalendarText.clock(saved, zone: app.zone))"
    }

    private func toolButton<Label: View>(_ name: String, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(theme.inkDimColor)
                .frame(width: PhoneMetrics.hit, height: PhoneMetrics.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }

    private func attach(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            model.draft.attachments.append(OutgoingAttachment(filename: url.lastPathComponent, mimeType: type, data: data))
        }
        let total = model.draft.attachments.reduce(0) { $0 + $1.data.count }
        if total > ByteSize.gmailLimit { model.error = "Attachments add up to \(ByteSize.text(total)); Gmail allows 25 MB." }
        model.scheduleSave()
    }
}

/// Recipient chips (accent tint, tap to remove).
private struct FlowChips: View {
    @Environment(\.thubanTheme) private var theme
    var addresses: [EmailAddress]
    var remove: (EmailAddress) -> Void

    var body: some View {
        if !addresses.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(addresses, id: \.normalized) { address in
                        Button { remove(address) } label: {
                            Text(address.name ?? address.email)
                                .font(PhoneFont.secondarySemibold)
                                .foregroundStyle(theme.brassInkColor)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 30)
                                .background(theme.accentTintColor, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(address.displayName), \(address.email)")
                        .accessibilityHint("Removes this recipient")
                    }
                }
            }
            .fixedSize(horizontal: addresses.count < 3, vertical: false)
        }
    }
}

// MARK: - Rich text

/// Talks to the composer's UITextView (bold / italic / bullets, focus).
@MainActor
final class RichTextController {
    weak var textView: UITextView?
    var onChange: ((NSAttributedString) -> Void)?

    func focus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.textView?.becomeFirstResponder() }
    }

    func toggle(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let view = textView else { return }
        let range = view.selectedRange
        let base = UIFont.preferredFont(forTextStyle: .body)
        if range.length == 0 {
            let current = (view.typingAttributes[.font] as? UIFont) ?? base
            view.typingAttributes[.font] = Self.font(current, toggling: trait)
            return
        }
        let text = NSMutableAttributedString(attributedString: view.attributedText)
        let turnOn = !Self.allHave(trait, in: text, range: range)
        text.enumerateAttribute(.font, in: range) { value, sub, _ in
            let font = (value as? UIFont) ?? base
            var traits = font.fontDescriptor.symbolicTraits
            if turnOn { traits.insert(trait) } else { traits.remove(trait) }
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
            text.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: sub)
        }
        view.attributedText = text
        view.selectedRange = range
        onChange?(view.attributedText)
    }

    /// Adds or removes "• " at the start of the selected lines.
    func toggleBullet() {
        guard let view = textView else { return }
        let text = NSMutableAttributedString(attributedString: view.attributedText)
        let string = text.string as NSString
        let lineRange = string.lineRange(for: view.selectedRange)
        var starts: [Int] = []
        string.enumerateSubstrings(in: lineRange, options: [.byLines, .substringNotRequired]) { _, range, _, _ in starts.append(range.location) }
        if starts.isEmpty { starts = [lineRange.location] }
        let prefix = RichRuns.bulletPrefix
        let allBulleted = starts.allSatisfy { string.length >= $0 + prefix.count && string.substring(with: NSRange(location: $0, length: prefix.count)) == prefix }
        let attributes = view.typingAttributes
        var shift = 0
        for start in starts {
            let location = start + shift
            if allBulleted {
                text.deleteCharacters(in: NSRange(location: location, length: prefix.count))
                shift -= prefix.count
            } else if !(text.string as NSString).substring(from: location).hasPrefix(prefix) {
                text.insert(NSAttributedString(string: prefix, attributes: attributes), at: location)
                shift += prefix.count
            }
        }
        view.attributedText = text
        view.selectedRange = NSRange(location: max(0, min(text.length, view.selectedRange.location + shift)), length: 0)
        onChange?(view.attributedText)
    }

    static func font(_ font: UIFont, toggling trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
        return UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor, size: font.pointSize)
    }

    static func allHave(_ trait: UIFontDescriptor.SymbolicTraits, in text: NSAttributedString, range: NSRange) -> Bool {
        var all = true
        text.enumerateAttribute(.font, in: range) { value, _, stop in
            if !((value as? UIFont)?.fontDescriptor.symbolicTraits.contains(trait) ?? false) { all = false; stop.pointee = true }
        }
        return all
    }
}

struct RichTextView: UIViewRepresentable {
    @Environment(\.thubanTheme) private var theme
    var controller: RichTextController
    var initial: NSAttributedString
    var placeholder: String
    var onChange: (NSAttributedString) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.isScrollEnabled = true
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.allowsEditingTextAttributes = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.delegate = context.coordinator
        view.attributedText = initial
        view.typingAttributes = [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor(theme.inkColor)]
        view.textColor = UIColor(theme.inkColor)
        view.tintColor = UIColor(theme.brassInkColor)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        controller.textView = view
        controller.onChange = { context.coordinator.onChange($0) }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onChange = onChange
        view.tintColor = UIColor(theme.brassInkColor)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        // Takes whatever height the sheet offers; the text view scrolls inside it.
        CGSize(width: proposal.width ?? 320, height: proposal.height ?? 220)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onChange: (NSAttributedString) -> Void
        init(onChange: @escaping (NSAttributedString) -> Void) { self.onChange = onChange }

        func textViewDidChange(_ textView: UITextView) {
            onChange(textView.attributedText)
        }
    }
}
