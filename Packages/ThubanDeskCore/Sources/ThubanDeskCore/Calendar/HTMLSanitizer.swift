import Foundation
import SwiftSoup

/// HTML cleaning for event descriptions (rich text shown natively) and mail bodies (shown in a sandboxed WKWebView).
public enum HTMLSanitizer {
    /// True when the text contains markup (Google stores descriptions as HTML or plain text).
    public static func looksLikeHTML(_ text: String) -> Bool {
        text.range(of: #"<(/?[a-zA-Z][a-zA-Z0-9]*)(\s[^>]*)?/?>"#, options: .regularExpression) != nil
            || text.range(of: #"&(amp|lt|gt|nbsp|quot|#\d+);"#, options: .regularExpression) != nil
    }

    /// Event description → safe HTML fragment: formatting and links kept; scripts, styles, embeds, forms, images and
    /// event handlers removed (design: "Formatting and links are kept; scripts and embeds are removed").
    /// Plain-text descriptions are escaped and their line breaks and URLs kept.
    public static func eventDescription(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        guard looksLikeHTML(raw) else { return plainTextToHTML(raw) }
        do {
            let whitelist = try Whitelist.basic()
            try whitelist.addTags("h1", "h2", "h3", "h4", "span", "div", "hr")
            return try SwiftSoup.clean(raw, "", whitelist, OutputSettings().prettyPrint(pretty: false)) ?? escape(raw)
        } catch {
            return escape(plainText(raw))
        }
    }

    /// Visible text (block elements become line breaks), whitespace collapsed within lines.
    public static func plainText(_ html: String?, limit: Int? = nil) -> String {
        guard let html, !html.isEmpty else { return "" }
        var text: String
        if looksLikeHTML(html), let document = try? SwiftSoup.parseBodyFragment(html), let body = document.body() {
            text = blockText(body)
        } else {
            text = html
        }
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        let lines = text.components(separatedBy: "\n").map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
        var collapsed: [String] = []
        for line in lines {
            if line.isEmpty, collapsed.last?.isEmpty ?? true { continue }
            collapsed.append(line)
        }
        text = collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if let limit, text.count > limit { text = String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" }
        return text
    }

    /// Rich text for native display (bold, italic, links, list bullets, paragraphs) built from a sanitized fragment.
    public static func richText(_ raw: String?) -> AttributedString {
        let html = eventDescription(raw)
        guard !html.isEmpty, let document = try? SwiftSoup.parseBodyFragment(html), let body = document.body() else { return AttributedString() }
        var builder = RichTextBuilder()
        builder.walk(body, style: .init())
        return builder.finish()
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Escapes, links bare URLs and keeps line breaks.
    public static func plainTextToHTML(_ text: String) -> String {
        let escaped = escape(text)
        let linked = escaped.replacingOccurrences(of: #"(https?://[^\s<]+[^\s<.,;:!?)\]'"])"#, with: "<a href=\"$1\">$1</a>", options: .regularExpression)
        return linked.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "<br>")
    }

    static let blockTags: Set<String> = ["p", "div", "br", "li", "ul", "ol", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "table", "hr", "pre"]

    private static func blockText(_ element: Element) -> String {
        var out = ""
        for node in element.getChildNodes() {
            if let text = node as? TextNode {
                out += text.text()
            } else if let child = node as? Element {
                let tag = child.tagName().lowercased()
                if ["script", "style", "head", "title"].contains(tag) { continue }
                if tag == "br" { out += "\n"; continue }
                let inner = blockText(child)
                if blockTags.contains(tag) {
                    if !out.isEmpty, !out.hasSuffix("\n") { out += "\n" }
                    out += (tag == "li" ? "• " : "") + inner
                    if !out.hasSuffix("\n") { out += "\n" }
                } else {
                    out += inner
                }
            }
        }
        return out
    }
}

/// Walks a sanitized fragment into an `AttributedString`.
private struct RichTextBuilder {
    struct Style {
        var bold = false
        var italic = false
        var strike = false
        var link: URL?
        var listDepth = 0
    }

    var result = AttributedString()

    mutating func walk(_ element: Element, style: Style) {
        for node in element.getChildNodes() {
            if let text = node as? TextNode {
                append(text.text(), style)
            } else if let child = node as? Element {
                var next = style
                let tag = child.tagName().lowercased()
                switch tag {
                case "b", "strong": next.bold = true
                case "i", "em": next.italic = true
                case "s", "strike", "del": next.strike = true
                case "a": next.link = (try? child.attr("href")).flatMap { URL(string: $0) }
                case "ul", "ol": next.listDepth += 1
                case "br": newline(); continue
                default: break
                }
                let isBlock = HTMLSanitizer.blockTags.contains(tag)
                if isBlock { ensureLineStart() }
                if tag == "li" { append(String(repeating: "   ", count: max(0, style.listDepth - 1)) + "• ", style) }
                walk(child, style: next)
                if isBlock { ensureLineStart() }
                if tag == "p" { newline() }
            }
        }
    }

    mutating func append(_ raw: String, _ style: Style) {
        // HTML whitespace rules: runs collapse to one space; no space at the start of a line.
        var text = raw.replacingOccurrences(of: #"[ \t\r\n]+"#, with: " ", options: .regularExpression)
        let current = String(result.characters)
        if current.isEmpty || current.hasSuffix("\n") || current.hasSuffix(" ") {
            while text.hasPrefix(" ") { text.removeFirst() }
        }
        guard !text.isEmpty else { return }
        var piece = AttributedString(text.replacingOccurrences(of: "\u{00A0}", with: " "))
        var intent: InlinePresentationIntent = []
        if style.bold { intent.insert(.stronglyEmphasized) }
        if style.italic { intent.insert(.emphasized) }
        if style.strike { intent.insert(.strikethrough) }
        if !intent.isEmpty { piece.inlinePresentationIntent = intent }
        if let link = style.link { piece.link = link }
        result += piece
    }

    mutating func newline() { result += AttributedString("\n") }

    mutating func ensureLineStart() {
        // Drop trailing spaces before breaking the line.
        while let last = result.characters.last, last == " " {
            result.removeSubrange(result.characters.index(before: result.endIndex)..<result.endIndex)
        }
        let text = String(result.characters)
        if !text.isEmpty, !text.hasSuffix("\n") { newline() }
    }

    mutating func finish() -> AttributedString {
        // Trim trailing newlines.
        while let last = result.characters.last, last == "\n" || last == " " {
            result.removeSubrange(result.characters.index(before: result.endIndex)..<result.endIndex)
        }
        return result
    }
}
