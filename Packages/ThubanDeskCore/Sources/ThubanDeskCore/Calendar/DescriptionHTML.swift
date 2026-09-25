import Foundation

/// Builds the HTML Google stores for an event description from the editor's styled text (design: bold, italic,
/// underline, bulleted / numbered lists, links). The editor hands over lines of runs; lines starting with "• " or
/// "1. " become list items. The output only uses tags `HTMLSanitizer` keeps, so it round-trips through
/// `HTMLSanitizer.richText`.
public enum DescriptionHTML {
    public struct Run: Hashable, Sendable {
        public var text: String
        public var bold: Bool
        public var italic: Bool
        public var underline: Bool
        public var link: String?

        public init(_ text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false, link: String? = nil) {
            self.text = text
            self.bold = bold
            self.italic = italic
            self.underline = underline
            self.link = link
        }
    }

    public enum ListKind: Hashable, Sendable { case bullet, numbered }

    /// The list marker a line starts with ("• " or "12. "), and its length in characters.
    public static func listMarker(of line: String) -> (kind: ListKind, length: Int)? {
        if line.hasPrefix("• ") { return (.bullet, 2) }
        if line.hasPrefix("•\t") { return (.bullet, 2) }
        var digits = 0
        for character in line {
            if character.isASCII, character.isNumber { digits += 1 } else { break }
        }
        guard digits > 0, digits <= 3 else { return nil }
        let rest = line.dropFirst(digits)
        if rest.hasPrefix(". ") || rest.hasPrefix(".\t") { return (.numbered, digits + 2) }
        return nil
    }

    /// HTML for lines of runs (one array per line). Plain lines are joined with `<br>`; list lines are grouped into
    /// `<ul>` / `<ol>`. Empty input gives "".
    public static func html(lines: [[Run]]) -> String {
        var out = ""
        var openList: ListKind?
        var pendingBreak = false

        func closeList() {
            if let kind = openList { out += kind == .bullet ? "</ul>" : "</ol>" }
            openList = nil
        }

        // Drop trailing empty lines.
        var lines = lines
        while let last = lines.last, last.allSatisfy({ $0.text.isEmpty }) { lines.removeLast() }

        for line in lines {
            let text = line.map(\.text).joined()
            if let marker = listMarker(of: text) {
                if openList != marker.kind {
                    closeList()
                    out += marker.kind == .bullet ? "<ul>" : "<ol>"
                    openList = marker.kind
                }
                pendingBreak = false
                out += "<li>" + inline(dropping: marker.length, from: line) + "</li>"
            } else {
                let hadList = openList != nil
                closeList()
                if pendingBreak, !hadList { out += "<br>" }
                out += inline(dropping: 0, from: line)
                pendingBreak = true
            }
        }
        closeList()
        return out
    }

    /// Inline markup for one line, skipping the first `count` characters (the list marker).
    static func inline(dropping count: Int, from runs: [Run]) -> String {
        var remaining = count
        var out = ""
        for run in runs {
            var text = run.text
            if remaining > 0 {
                let cut = min(remaining, text.count)
                text = String(text.dropFirst(cut))
                remaining -= cut
            }
            guard !text.isEmpty else { continue }
            var piece = HTMLSanitizer.escape(text)
            if run.underline { piece = "<u>\(piece)</u>" }
            if run.italic { piece = "<i>\(piece)</i>" }
            if run.bold { piece = "<b>\(piece)</b>" }
            if let link = run.link, let scheme = URL(string: link)?.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
                piece = "<a href=\"\(HTMLSanitizer.escape(link))\">\(piece)</a>"
            }
            out += piece
        }
        return out
    }
}

extension CalendarText {
    /// Parses what someone types in a time box: "7", "7pm", "7:30 PM", "19:30", "730p", "noon". Minutes since midnight.
    public static func parseClock(_ raw: String) -> Int? {
        var text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        if text == "noon" { return 12 * 60 }
        if text == "midnight" { return 0 }
        var meridiem: Character?
        if text.hasSuffix("am") || text.hasSuffix("pm") { meridiem = text.dropLast().last; text = String(text.dropLast(2)) }
        else if text.hasSuffix("a") || text.hasSuffix("p") { meridiem = text.last; text = String(text.dropLast()) }
        let digits: String
        var hour: Int, minute: Int
        if text.contains(":") || text.contains(".") {
            let pieces = text.split(whereSeparator: { $0 == ":" || $0 == "." })
            guard pieces.count == 2, let h = Int(pieces[0]), let m = Int(pieces[1]), pieces[1].count == 2 else { return nil }
            hour = h
            minute = m
        } else {
            digits = text
            guard !digits.isEmpty, digits.count <= 4, let value = Int(digits) else { return nil }
            if digits.count <= 2 { hour = value; minute = 0 } else { hour = value / 100; minute = value % 100 }
        }
        guard minute < 60 else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "a" { hour = hour == 12 ? 0 : hour } else { hour = hour == 12 ? 12 : hour + 12 }
        }
        guard (0...23).contains(hour) else { return nil }
        return hour * 60 + minute
    }
}
