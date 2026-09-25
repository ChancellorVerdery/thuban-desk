import Foundation

/// `Name <user@host>`.
public struct EmailAddress: Codable, Hashable, Sendable, CustomStringConvertible {
    public var name: String?
    public var email: String

    public init(_ email: String, name: String? = nil) {
        // Line breaks never survive into a name or address (header injection in replies).
        self.email = HeaderValue.singleLine(email).trimmingCharacters(in: .whitespaces)
        let trimmed = name.map(HeaderValue.singleLine)?.trimmingCharacters(in: .whitespaces)
        self.name = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// Lower-cased address for comparisons.
    public var normalized: String { email.lowercased() }
    /// The name, else the part before `@`.
    public var displayName: String { name ?? String(email.split(separator: "@").first ?? Substring(email)) }
    /// "PS" initials for avatars.
    public var initials: String {
        let words = displayName.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" }).filter { $0.first?.isLetter ?? false }
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? String(displayName.prefix(1)).uppercased() : letters.joined()
    }
    public var domain: String { String(email.split(separator: "@").last ?? "") }

    /// Header form: `"Last, First" <a@b>`, `=?UTF-8?B?…?= <a@b>`, or the bare address.
    public var header: String {
        let email = HeaderValue.singleLine(self.email).replacingOccurrences(of: " ", with: "")
        guard let name = name.map(HeaderValue.singleLine) else { return email }
        if name.unicodeScalars.contains(where: { !$0.isASCII }) { return "\(RFC2047.encode(name)) <\(email)>" }
        let specials = CharacterSet(charactersIn: "()<>[]:;@\\,.\"")
        if name.rangeOfCharacter(from: specials) != nil {
            let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\" <\(email)>"
        }
        return "\(name) <\(email)>"
    }

    public var description: String { name.map { "\($0) <\(email)>" } ?? email }

    /// Parses one address (`nil` when there is no `@`).
    public static func parse(_ text: String) -> EmailAddress? { parseList(text).first }

    /// Parses an address list header (decoding RFC 2047 names; quoted names may contain commas; group syntax and
    /// comments are tolerated).
    public static func parseList(_ header: String?) -> [EmailAddress] {
        guard let header, !header.isEmpty else { return [] }
        var items: [String] = []
        var current = ""
        var inQuote = false, angle = 0, paren = 0
        var escape = false
        for char in header {
            if escape { current.append(char); escape = false; continue }
            switch char {
            case "\\" where inQuote: escape = true; current.append(char)
            case "\"": inQuote.toggle(); current.append(char)
            case "<" where !inQuote: angle += 1; current.append(char)
            case ">" where !inQuote: angle = max(0, angle - 1); current.append(char)
            case "(" where !inQuote: paren += 1; current.append(char)
            case ")" where !inQuote: paren = max(0, paren - 1); current.append(char)
            case ",", ";":
                if !inQuote && angle == 0 && paren == 0 { items.append(current); current = "" } else { current.append(char) }
            default: current.append(char)
            }
        }
        items.append(current)
        return items.compactMap(parseSingle)
    }

    private static func parseSingle(_ raw: String) -> EmailAddress? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Group syntax "Team: a@b, c@d;" — drop the group name.
        if let colon = text.firstIndex(of: ":"), !text[..<colon].contains("<"), !text[..<colon].contains("\""), !text[..<colon].contains("@") {
            text = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty else { return nil }
        if let open = text.lastIndex(of: "<"), let close = text.lastIndex(of: ">"), open < close {
            let address = String(text[text.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            var name = String(text[..<open]).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 {
                name = String(name.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
            }
            guard address.contains("@") else { return nil }
            return EmailAddress(address, name: RFC2047.decode(name))
        }
        // "a@b (Name)"
        var comment: String?
        if let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"), open < close {
            comment = String(text[text.index(after: open)..<close])
            text = String(text[..<open]).trimmingCharacters(in: .whitespaces)
        }
        guard text.contains("@"), !text.contains(" ") else { return nil }
        return EmailAddress(text, name: comment.map(RFC2047.decode))
    }

    /// Header value for a list, folded so no line exceeds ~78 characters.
    public static func headerList(_ addresses: [EmailAddress]) -> String {
        var lines: [String] = []
        var line = ""
        for (index, address) in addresses.enumerated() {
            let piece = address.header + (index < addresses.count - 1 ? "," : "")
            if !line.isEmpty, line.count + 1 + piece.count > 72 {
                lines.append(line)
                line = piece
            } else {
                line = line.isEmpty ? piece : line + " " + piece
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines.joined(separator: "\r\n ")
    }
}
