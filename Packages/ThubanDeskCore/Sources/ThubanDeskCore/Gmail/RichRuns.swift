import Foundation

/// The iOS composer's body as plain data — paragraphs of styled runs, some of them bullets — and its HTML for the
/// outgoing message. Platform-neutral (the app reads the runs out of its UITextView), so it is unit-tested here.
public enum RichRuns {
    public struct Run: Hashable, Sendable {
        public var text: String
        public var bold: Bool
        public var italic: Bool

        public init(_ text: String, bold: Bool = false, italic: Bool = false) {
            self.text = text
            self.bold = bold
            self.italic = italic
        }
    }

    public struct Paragraph: Hashable, Sendable {
        public var runs: [Run]
        public var bullet: Bool

        public init(_ runs: [Run], bullet: Bool = false) {
            self.runs = runs
            self.bullet = bullet
        }

        public var text: String { runs.map(\.text).joined() }
    }

    /// The bullet prefix the composer shows ("• ").
    public static let bulletPrefix = "• "

    /// Splits plain paragraphs out of text lines, marking "• " lines as bullets (prefix dropped).
    public static func paragraphs(fromLines lines: [[Run]]) -> [Paragraph] {
        lines.map { runs in
            let text = runs.map(\.text).joined()
            guard text.hasPrefix(bulletPrefix) else { return Paragraph(runs) }
            var remaining = bulletPrefix.count
            var trimmed: [Run] = []
            for run in runs {
                if remaining > 0 {
                    let drop = min(remaining, run.text.count)
                    remaining -= drop
                    let rest = String(run.text.dropFirst(drop))
                    if !rest.isEmpty { trimmed.append(Run(rest, bold: run.bold, italic: run.italic)) }
                } else {
                    trimmed.append(run)
                }
            }
            return Paragraph(trimmed, bullet: true)
        }
    }

    /// `<div>` per paragraph (empty ones as `<br>`), consecutive bullets in one `<ul>`, `<b>` / `<i>` runs, text escaped.
    public static func html(_ paragraphs: [Paragraph]) -> String {
        var out = ""
        var inList = false
        for paragraph in paragraphs {
            if paragraph.bullet, !inList { out += "<ul>"; inList = true }
            if !paragraph.bullet, inList { out += "</ul>"; inList = false }
            let body = paragraph.runs.map(runHTML).joined()
            if paragraph.bullet {
                out += "<li>\(body.isEmpty ? "<br>" : body)</li>"
            } else {
                out += "<div>\(body.isEmpty ? "<br>" : body)</div>"
            }
        }
        if inList { out += "</ul>" }
        return out
    }

    /// The plain-text twin ("- " for bullets).
    public static func plainText(_ paragraphs: [Paragraph]) -> String {
        paragraphs.map { ($0.bullet ? "- " : "") + $0.text }.joined(separator: "\n")
    }

    static func runHTML(_ run: Run) -> String {
        var text = escape(run.text)
        guard !text.isEmpty else { return "" }
        if run.italic { text = "<i>\(text)</i>" }
        if run.bold { text = "<b>\(text)</b>" }
        return text
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
