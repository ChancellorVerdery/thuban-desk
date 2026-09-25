import AppKit
import SwiftUI
import ThubanDeskCore

extension NSAttributedString.Key {
    /// A paragraph inside a quote block (Compose → `<blockquote>`).
    static let deskQuote = NSAttributedString.Key("ThubanDeskQuote")
    /// Secondary text (signature second line) drawn in inkDim.
    static let deskDim = NSAttributedString.Key("ThubanDeskDim")
}

/// Text sizes in the Compose toolbar (Gmail's four).
enum ComposeTextSize: String, CaseIterable, Identifiable {
    case small = "Small", normal = "Normal", large = "Large", huge = "Huge"
    var id: String { rawValue }
    var points: CGFloat {
        switch self {
        case .small: return 13
        case .normal: return 15
        case .large: return 19
        case .huge: return 24
        }
    }

    init(points: CGFloat) {
        self = Self.allCases.min { abs($0.points - points) < abs($1.points - points) } ?? .normal
    }
}

/// Formatting commands from the Compose toolbar, applied to the editor's selection (or typing attributes).
@MainActor
final class RichTextController {
    weak var textView: ComposeTextView?
    var theme: ResolvedTheme = ThemeResolver.resolve(.default, systemIsDark: false)

    var baseFont: NSFont { NSFont.systemFont(ofSize: ComposeTextSize.normal.points) }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func toggleTrait(_ trait: NSFontTraitMask) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        let manager = NSFontManager.shared
        if range.length == 0 {
            let font = (textView.typingAttributes[.font] as? NSFont) ?? baseFont
            let has = manager.traits(of: font).contains(trait)
            textView.typingAttributes[.font] = has ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
            return
        }
        let first = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? baseFont
        let remove = manager.traits(of: first).contains(trait)
        edit(range) {
            storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                let font = (value as? NSFont) ?? self.baseFont
                storage.addAttribute(.font, value: remove ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait), range: sub)
            }
        }
    }

    func toggleAttribute(_ key: NSAttributedString.Key) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        let on = NSUnderlineStyle.single.rawValue
        if range.length == 0 {
            let current = (textView.typingAttributes[key] as? Int) ?? 0
            textView.typingAttributes[key] = current == 0 ? on : 0
            return
        }
        let current = (storage.attribute(key, at: range.location, effectiveRange: nil) as? Int) ?? 0
        edit(range) {
            if current == 0 { storage.addAttribute(key, value: on, range: range) } else { storage.removeAttribute(key, range: range) }
        }
    }

    func setSize(_ size: ComposeTextSize) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        let manager = NSFontManager.shared
        if range.length == 0 {
            let font = (textView.typingAttributes[.font] as? NSFont) ?? baseFont
            textView.typingAttributes[.font] = manager.convert(font, toSize: size.points)
            return
        }
        edit(range) {
            storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                storage.addAttribute(.font, value: manager.convert((value as? NSFont) ?? self.baseFont, toSize: size.points), range: sub)
            }
        }
    }

    var currentSize: ComposeTextSize {
        guard let textView else { return .normal }
        let font = textView.selectedRange().length == 0 || textView.textStorage?.length == 0
            ? textView.typingAttributes[.font] as? NSFont
            : textView.textStorage?.attribute(.font, at: min(textView.selectedRange().location, max(0, (textView.textStorage?.length ?? 1) - 1)), effectiveRange: nil) as? NSFont
        return ComposeTextSize(points: font?.pointSize ?? 15)
    }

    /// Bulleted / numbered list on the selected paragraphs (toggles off when they already are that list).
    func toggleList(ordered: Bool) {
        guard let textView, let storage = textView.textStorage else { return }
        let string = storage.string as NSString
        let range = string.paragraphRange(for: textView.selectedRange())
        var paragraphs: [NSRange] = []
        string.enumerateSubstrings(in: range, options: [.byParagraphs, .substringNotRequired]) { _, sub, enclosing, _ in paragraphs.append(enclosing) }
        if paragraphs.isEmpty { paragraphs = [range] }
        let format: NSTextList.MarkerFormat = ordered ? .decimal : .disc
        let alreadyThis = paragraphs.allSatisfy { p in
            guard p.location < storage.length, let style = storage.attribute(.paragraphStyle, at: p.location, effectiveRange: nil) as? NSParagraphStyle else { return false }
            return style.textLists.last?.markerFormat == format
        }
        let list = NSTextList(markerFormat: format, options: 0)
        let result = NSMutableAttributedString()
        for (index, p) in paragraphs.enumerated() {
            let piece = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: p))
            RichTextFormat.stripMarker(piece)
            let attrs = piece.length > 0 ? piece.attributes(at: 0, effectiveRange: nil) : textView.typingAttributes
            let style = ((attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? RichTextFormat.paragraphStyle()
            if alreadyThis {
                style.textLists = []
                style.headIndent = 0
                style.firstLineHeadIndent = 0
                style.tabStops = []
            } else {
                style.textLists = [list]
                style.tabStops = [NSTextTab(textAlignment: .left, location: 10), NSTextTab(textAlignment: .left, location: 28)]
                style.headIndent = 28
                style.firstLineHeadIndent = 0
                var markerAttrs = attrs
                markerAttrs[.font] = baseFont
                piece.insert(NSAttributedString(string: "\t\(list.marker(forItemNumber: index + 1))\t", attributes: markerAttrs), at: 0)
            }
            piece.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: piece.length))
            result.append(piece)
        }
        replace(range, with: result)
    }

    /// Quote block on the selected paragraphs (indented, dim; sent as `<blockquote>`).
    func toggleQuote() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = (storage.string as NSString).paragraphRange(for: textView.selectedRange())
        let isQuote = range.location < storage.length && storage.attribute(.deskQuote, at: range.location, effectiveRange: nil) != nil
        if range.length == 0 {
            let style = RichTextFormat.paragraphStyle(quote: !isQuote)
            textView.typingAttributes[.paragraphStyle] = style
            textView.typingAttributes[.deskQuote] = isQuote ? nil : true
            textView.typingAttributes[.foregroundColor] = NSColor(hex: isQuote ? theme.ink : theme.inkDim)
            return
        }
        edit(range) {
            if isQuote {
                storage.removeAttribute(.deskQuote, range: range)
                storage.addAttribute(.paragraphStyle, value: RichTextFormat.paragraphStyle(), range: range)
                storage.addAttribute(.foregroundColor, value: NSColor(hex: self.theme.ink), range: range)
            } else {
                storage.addAttribute(.deskQuote, value: true, range: range)
                storage.addAttribute(.paragraphStyle, value: RichTextFormat.paragraphStyle(quote: true), range: range)
                storage.addAttribute(.foregroundColor, value: NSColor(hex: self.theme.inkDim), range: range)
            }
        }
    }

    func setLink(_ text: String) {
        guard let textView, let storage = textView.textStorage else { return }
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        if !raw.contains("://"), !raw.hasPrefix("mailto:") { raw = (raw.contains("@") && !raw.contains("/") ? "mailto:" : "https://") + raw }
        guard let url = URL(string: raw), ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return }
        var range = textView.selectedRange()
        if range.length == 0 {
            let shown = NSAttributedString(string: text.trimmingCharacters(in: .whitespaces), attributes: textView.typingAttributes)
            replace(range, with: shown)
            range = NSRange(location: range.location, length: shown.length)
        }
        edit(range) { storage.addAttribute(.link, value: url, range: range) }
    }

    func clearFormatting() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        let plain = RichTextFormat.baseAttributes(theme: theme)
        if range.length == 0 {
            textView.typingAttributes = plain
            return
        }
        let paragraphs = (storage.string as NSString).paragraphRange(for: range)
        edit(paragraphs) {
            let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: paragraphs))
            RichTextFormat.stripAllMarkers(text)
            storage.replaceCharacters(in: paragraphs, with: NSAttributedString(string: text.string, attributes: plain))
        }
    }

    private func edit(_ range: NSRange, _ change: () -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        change()
        storage.endEditing()
        textView.didChangeText()
    }

    private func replace(_ range: NSRange, with text: NSAttributedString) {
        guard let textView, let storage = textView.textStorage else { return }
        guard textView.shouldChangeText(in: range, replacementString: text.string) else { return }
        storage.replaceCharacters(in: range, with: text)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + text.length, length: 0))
    }

    /// Recolours ink / dim text after a theme change.
    func applyTheme(_ theme: ResolvedTheme) {
        guard let textView, let storage = textView.textStorage else { self.theme = theme; return }
        self.theme = theme
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor(hex: theme.ink), range: whole)
        storage.enumerateAttribute(.deskDim, in: whole) { value, sub, _ in
            if value != nil { storage.addAttribute(.foregroundColor, value: NSColor(hex: theme.inkDim), range: sub) }
        }
        storage.enumerateAttribute(.deskQuote, in: whole) { value, sub, _ in
            if value != nil { storage.addAttribute(.foregroundColor, value: NSColor(hex: theme.inkDim), range: sub) }
        }
        storage.endEditing()
        textView.typingAttributes[.foregroundColor] = NSColor(hex: theme.ink)
        textView.insertionPointColor = NSColor(hex: theme.ink)
        textView.linkTextAttributes = [.foregroundColor: NSColor(hex: theme.isDark ? theme.accent : theme.accentText), .cursor: NSCursor.pointingHand]
        textView.selectedTextAttributes = [.backgroundColor: NSColor(hex: theme.accentTint)]
    }
}

/// The body text view: ⌘B / ⌘I / ⌘U format; ⌘↩ asks to send.
final class ComposeTextView: NSTextView {
    weak var controller: RichTextController?
    var onSend: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": controller?.toggleTrait(.boldFontMask); return true
        case "i": controller?.toggleTrait(.italicFontMask); return true
        case "u": controller?.toggleAttribute(.underlineStyle); return true
        case "\r": onSend?(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}

/// Auto-growing rich-text editor (TextKit 1 `NSTextView`, no scroll view of its own; the Compose body scrolls).
struct RichTextEditor: NSViewRepresentable {
    var model: ComposeModel
    var theme: ResolvedTheme
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(model: model, height: $height) }

    func makeNSView(context: Context) -> ComposeTextView {
        let view = ComposeTextView(usingTextLayoutManager: false)
        view.isRichText = true
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = true
        view.isAutomaticDashSubstitutionEnabled = true
        view.isContinuousSpellCheckingEnabled = true
        view.isAutomaticLinkDetectionEnabled = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.usesFontPanel = false
        view.setAccessibilityLabel("Message body")
        view.delegate = context.coordinator
        view.controller = model.editor
        view.onSend = { [weak model] in model?.requestSend() }
        model.editor.textView = view
        model.editor.theme = theme
        view.typingAttributes = RichTextFormat.baseAttributes(theme: theme)
        view.textStorage?.setAttributedString(model.initialBody)
        model.editor.applyTheme(theme)
        context.coordinator.lastTheme = theme
        DispatchQueue.main.async { context.coordinator.measure(view) }
        return view
    }

    func updateNSView(_ view: ComposeTextView, context: Context) {
        if context.coordinator.lastTheme != theme {
            context.coordinator.lastTheme = theme
            model.editor.applyTheme(theme)
        }
        if model.bodyRevision != context.coordinator.bodyRevision, let body = model.replacementBody {
            context.coordinator.bodyRevision = model.bodyRevision
            view.textStorage?.setAttributedString(body)
            model.editor.applyTheme(theme)
            context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        }
        DispatchQueue.main.async { context.coordinator.measure(view) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: ComposeModel
        var height: Binding<CGFloat>
        var lastTheme: ResolvedTheme?
        var bodyRevision = 0

        init(model: ComposeModel, height: Binding<CGFloat>) {
            self.model = model
            self.height = height
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, let storage = view.textStorage else { return }
            let out = RichTextFormat.html(from: storage)
            model.bodyChanged(html: out.html, text: out.text)
            measure(view)
        }

        func measure(_ view: NSTextView) {
            guard let manager = view.layoutManager, let container = view.textContainer else { return }
            manager.ensureLayout(for: container)
            let used = manager.usedRect(for: container).height
            let line = (view.typingAttributes[.font] as? NSFont).map { manager.defaultLineHeight(for: $0) } ?? 20
            let target = max(used, line) + 4
            if abs(target - height.wrappedValue) > 0.5 { height.wrappedValue = target }
        }
    }
}

/// Body attributes, the starting body, and the HTML / plain-text serializer for Compose.
enum RichTextFormat {
    static func paragraphStyle(quote: Bool = false) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.22
        style.paragraphSpacing = 2
        if quote {
            style.headIndent = 14
            style.firstLineHeadIndent = 14
        }
        return style
    }

    static func baseAttributes(theme: ResolvedTheme) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: ComposeTextSize.normal.points), .foregroundColor: NSColor(hex: theme.ink), .paragraphStyle: paragraphStyle()]
    }

    /// An empty line to type on, then the signature (first line ink, the rest dim), as in the design.
    static func startingBody(signature: String?, theme: ResolvedTheme) -> NSAttributedString {
        let out = NSMutableAttributedString(string: "\n", attributes: baseAttributes(theme: theme))
        guard let signature else { return out }
        out.append(NSAttributedString(string: "\n", attributes: baseAttributes(theme: theme)))
        let lines = signature.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            var attrs = baseAttributes(theme: theme)
            if index > 0 {
                attrs[.foregroundColor] = NSColor(hex: theme.inkDim)
                attrs[.deskDim] = true
            }
            out.append(NSAttributedString(string: line + (index < lines.count - 1 ? "\n" : ""), attributes: attrs))
        }
        return out
    }

    static func body(fromDraftText text: String, theme: ResolvedTheme) -> NSAttributedString {
        NSAttributedString(string: text.trimmingCharacters(in: .whitespacesAndNewlines), attributes: baseAttributes(theme: theme))
    }

    /// Removes a leading "\t•\t" / "\t3.\t" list marker.
    static func stripMarker(_ text: NSMutableAttributedString) {
        let string = text.string as NSString
        guard string.hasPrefix("\t"), let regex = try? NSRegularExpression(pattern: #"^\t[^\t\n]{1,6}\t"#) else { return }
        if let match = regex.firstMatch(in: text.string, range: NSRange(location: 0, length: min(12, string.length))) {
            text.deleteCharacters(in: match.range)
        }
    }

    static func stripAllMarkers(_ text: NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^\t[^\t\n]{1,6}\t"#) else { return }
        for match in regex.matches(in: text.string, range: NSRange(location: 0, length: (text.string as NSString).length)).reversed() {
            text.deleteCharacters(in: match.range)
        }
    }

    /// HTML (Gmail-style `<div>` lines, lists, blockquotes, b/i/u/s, links, sizes) and the plain-text twin.
    static func html(from text: NSAttributedString) -> (html: String, text: String) {
        enum Block: Equatable { case line, bullet, number, quote }
        var html = ""
        var plain: [String] = []
        var open: Block?
        var numberIndex = 0
        let string = text.string as NSString
        func close() {
            switch open {
            case .bullet: html += "</ul>"
            case .number: html += "</ol>"
            case .quote: html += "</blockquote>"
            default: break
            }
            open = nil
        }
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            let para = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
            let style = range.length > 0 ? text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle : nil
            let isQuote = range.length > 0 && text.attribute(.deskQuote, at: range.location, effectiveRange: nil) != nil
            var block: Block = .line
            if let list = style?.textLists.last {
                block = list.markerFormat == .decimal ? .number : .bullet
                stripMarker(para)
            } else if isQuote {
                block = .quote
            }
            if block != open {
                close()
                switch block {
                case .bullet: html += "<ul>"
                case .number: html += "<ol>"; numberIndex = 0
                case .quote: html += "<blockquote style=\"margin:0 0 0 .8ex;border-left:1px solid #ccc;padding-left:1ex\">"
                case .line: break
                }
                open = block == .line ? nil : block
            }
            let inner = inlineHTML(para)
            switch block {
            case .bullet: html += "<li>\(inner)</li>"; plain.append("• " + para.string)
            case .number: numberIndex += 1; html += "<li>\(inner)</li>"; plain.append("\(numberIndex). " + para.string)
            case .quote: html += "<div>\(inner.isEmpty ? "<br>" : inner)</div>"; plain.append("> " + para.string)
            case .line: html += "<div>\(inner.isEmpty ? "<br>" : inner)</div>"; plain.append(para.string)
            }
        }
        close()
        // Trailing empty lines add nothing.
        while html.hasSuffix("<div><br></div>") { html.removeLast("<div><br></div>".count) }
        while plain.last?.isEmpty == true { plain.removeLast() }
        return (html, plain.joined(separator: "\n"))
    }

    private static func inlineHTML(_ text: NSAttributedString) -> String {
        var out = ""
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            let raw = (text.string as NSString).substring(with: range)
            guard !raw.isEmpty else { return }
            var piece = HTMLSanitizer.escape(raw)
            let font = attrs[.font] as? NSFont
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            if traits.contains(.boldFontMask) { piece = "<b>\(piece)</b>" }
            if traits.contains(.italicFontMask) { piece = "<i>\(piece)</i>" }
            if (attrs[.underlineStyle] as? Int ?? 0) != 0 { piece = "<u>\(piece)</u>" }
            if (attrs[.strikethroughStyle] as? Int ?? 0) != 0 { piece = "<s>\(piece)</s>" }
            if let size = font?.pointSize, abs(size - ComposeTextSize.normal.points) > 0.5 {
                piece = "<span style=\"font-size:\(Int(size))px\">\(piece)</span>"
            }
            if attrs[.deskDim] != nil { piece = "<span style=\"color:#6b6456\">\(piece)</span>" }
            if let link = (attrs[.link] as? URL)?.absoluteString ?? attrs[.link] as? String {
                piece = "<a href=\"\(HTMLSanitizer.escape(link))\">\(piece)</a>"
            }
            out += piece
        }
        return out
    }
}
