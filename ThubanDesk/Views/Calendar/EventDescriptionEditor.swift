import AppKit
import SwiftUI
import ThubanDeskCore

/// Commands from the description toolbar to the text view (bold, italic, underline, lists, link).
@MainActor
final class EventRichTextController {
    weak var textView: NSTextView?

    func toggleBold() { toggleTrait(.boldFontMask) }
    func toggleItalic() { toggleTrait(.italicFontMask) }

    func toggleUnderline() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else {
            var typing = textView.typingAttributes
            let on = (typing[.underlineStyle] as? Int ?? 0) != 0
            typing[.underlineStyle] = on ? 0 : NSUnderlineStyle.single.rawValue
            textView.typingAttributes = typing
            return
        }
        var allOn = true
        storage.enumerateAttribute(.underlineStyle, in: range) { value, _, _ in if (value as? Int ?? 0) == 0 { allOn = false } }
        edit(range) { storage.addAttribute(.underlineStyle, value: allOn ? 0 : NSUnderlineStyle.single.rawValue, range: range) }
    }

    private func toggleTrait(_ trait: NSFontTraitMask) {
        guard let textView, let storage = textView.textStorage else { return }
        let manager = NSFontManager.shared
        let range = textView.selectedRange()
        guard range.length > 0 else {
            var typing = textView.typingAttributes
            let font = (typing[.font] as? NSFont) ?? EventDescriptionEditor.baseFont
            let has = manager.traits(of: font).contains(trait)
            typing[.font] = has ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
            textView.typingAttributes = typing
            return
        }
        var allOn = true
        storage.enumerateAttribute(.font, in: range) { value, _, _ in
            if let font = value as? NSFont, !manager.traits(of: font).contains(trait) { allOn = false }
        }
        edit(range) {
            storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                let font = (value as? NSFont) ?? EventDescriptionEditor.baseFont
                storage.addAttribute(.font, value: allOn ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait), range: sub)
            }
        }
    }

    /// Adds or removes "• " / "1. " at the start of each selected line.
    func toggleList(numbered: Bool) {
        guard let textView, let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        let lines = text.lineRange(for: textView.selectedRange())
        var starts: [Int] = []
        text.enumerateSubstrings(in: lines, options: [.byLines, .substringNotRequired]) { _, range, _, _ in starts.append(range.location) }
        if starts.isEmpty { starts = [lines.location] }
        let allListed = starts.allSatisfy { start in
            let line = text.substring(from: start)
            guard let marker = DescriptionHTML.listMarker(of: line) else { return false }
            return (marker.kind == .numbered) == numbered
        }
        edit(lines) {
            // Work backwards so earlier offsets stay valid.
            for (index, start) in starts.enumerated().reversed() {
                let line = (storage.string as NSString).substring(from: start)
                if let marker = DescriptionHTML.listMarker(of: line) {
                    storage.deleteCharacters(in: NSRange(location: start, length: marker.length))
                }
                if !allListed {
                    let prefix = numbered ? "\(index + 1). " : "• "
                    let attributes = storage.length > start ? storage.attributes(at: min(start, storage.length - 1), effectiveRange: nil) : textView.typingAttributes
                    var clean = attributes
                    clean[.link] = nil
                    storage.insert(NSAttributedString(string: prefix, attributes: clean), at: start)
                }
            }
        }
    }

    /// Links the selection (or inserts the address as a link).
    func addLink(_ raw: String) {
        guard let textView, let storage = textView.textStorage else { return }
        var address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        if !address.contains("://"), !address.lowercased().hasPrefix("mailto:") {
            address = address.contains("@") && !address.contains("/") ? "mailto:\(address)" : "https://\(address)"
        }
        guard let url = URL(string: address) else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attributes = textView.typingAttributes
            attributes[.link] = url
            let insert = NSAttributedString(string: raw.trimmingCharacters(in: .whitespacesAndNewlines), attributes: attributes)
            let target = NSRange(location: range.location, length: 0)
            if textView.shouldChangeText(in: target, replacementString: insert.string) {
                storage.replaceCharacters(in: target, with: insert)
                textView.didChangeText()
            }
        } else {
            edit(range) { storage.addAttribute(.link, value: url, range: range) }
        }
    }

    private func edit(_ range: NSRange, _ change: () -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        change()
        storage.endEditing()
        textView.didChangeText()
        textView.window?.makeFirstResponder(textView)
    }
}

/// The description editor: native rich text (bold, italic, underline, bullet / numbered lines, links), saved as
/// sanitized HTML (`DescriptionHTML`) and loaded through `HTMLSanitizer` (scripts and embeds never survive).
struct EventDescriptionEditor: NSViewRepresentable {
    static let baseFont = NSFont.systemFont(ofSize: 14)

    var html: String
    var controller: EventRichTextController
    var theme: ResolvedTheme
    var isEditable: Bool
    var onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let view = EventShortcutTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.controller = controller
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = view
        view.isRichText = true
        view.allowsUndo = true
        view.importsGraphics = false
        view.isAutomaticQuoteSubstitutionEnabled = true
        view.isAutomaticLinkDetectionEnabled = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 8, height: 10)
        view.isEditable = isEditable
        view.delegate = context.coordinator
        style(view)
        view.textStorage?.setAttributedString(Self.attributed(from: html, theme: theme))
        view.typingAttributes = Self.baseAttributes(theme)
        controller.textView = view
        context.coordinator.textView = view
        view.setAccessibilityLabel("Description")
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        guard let view = scroll.documentView as? NSTextView else { return }
        view.isEditable = isEditable
        if context.coordinator.themeKey != theme.bg + theme.ink {
            context.coordinator.themeKey = theme.bg + theme.ink
            style(view)
            if let storage = view.textStorage {
                storage.addAttribute(.foregroundColor, value: NSColor(hex: theme.ink), range: NSRange(location: 0, length: storage.length))
            }
        }
    }

    private func style(_ view: NSTextView) {
        view.insertionPointColor = NSColor(hex: theme.ink)
        view.linkTextAttributes = [
            .foregroundColor: NSColor(hex: theme.isDark ? theme.accent : theme.accentText),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        view.selectedTextAttributes = [.backgroundColor: NSColor(hex: theme.accentTint)]
    }

    static func baseAttributes(_ theme: ResolvedTheme) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.18
        paragraph.paragraphSpacing = 3
        return [.font: baseFont, .foregroundColor: NSColor(hex: theme.ink), .paragraphStyle: paragraph]
    }

    /// Sanitized HTML → styled text for the text view.
    static func attributed(from html: String, theme: ResolvedTheme) -> NSAttributedString {
        let rich = HTMLSanitizer.richText(html)
        let result = NSMutableAttributedString()
        let manager = NSFontManager.shared
        for run in rich.runs {
            let text = String(rich[run.range].characters)
            var attributes = baseAttributes(theme)
            var font = baseFont
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { font = manager.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = manager.convert(font, toHaveTrait: .italicFontMask) }
                if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            }
            attributes[.font] = font
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }
        return result
    }

    /// Styled text → description HTML.
    static func html(from text: NSAttributedString) -> String {
        let manager = NSFontManager.shared
        let string = text.string as NSString
        var lines: [[DescriptionHTML.Run]] = []
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            var runs: [DescriptionHTML.Run] = []
            if lineRange.length > 0 {
                text.enumerateAttributes(in: lineRange) { attributes, range, _ in
                    let piece = string.substring(with: range)
                    let traits = (attributes[.font] as? NSFont).map { manager.traits(of: $0) } ?? []
                    let underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
                    let link: String? = (attributes[.link] as? URL)?.absoluteString ?? (attributes[.link] as? String)
                    runs.append(DescriptionHTML.Run(piece, bold: traits.contains(.boldFontMask), italic: traits.contains(.italicFontMask),
                                                    underline: underline, link: link))
                }
            }
            lines.append(runs.isEmpty ? [DescriptionHTML.Run("")] : runs)
        }
        return DescriptionHTML.html(lines: lines)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void
        weak var textView: NSTextView?
        var themeKey = ""

        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onChange(EventDescriptionEditor.html(from: textView.attributedString()))
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            // Links open in the browser only with ⌘-click, so editing text inside a link stays easy.
            guard NSEvent.modifierFlags.contains(.command) else { return true }
            if let url = link as? URL { NSWorkspace.shared.open(url) } else if let text = link as? String, let url = URL(string: text) { NSWorkspace.shared.open(url) }
            return true
        }
    }
}

/// ⌘B / ⌘I / ⌘U inside the description.
private final class EventShortcutTextView: NSTextView {
    weak var controller: EventRichTextController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": controller?.toggleBold(); return true
        case "i": controller?.toggleItalic(); return true
        case "u": controller?.toggleUnderline(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}
