import Foundation

public struct MIMEHeader: Codable, Hashable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// `text/plain; charset="utf-8"; format=flowed` → value + lower-cased parameter names. Handles RFC 2231
/// (`filename*=UTF-8''%E2%82%AC.pdf`, `filename*0*=…; filename*1*=…`).
public struct HeaderParameters: Hashable, Sendable {
    public var value: String
    public var parameters: [String: String]

    public init(_ header: String?) {
        guard let header else { value = ""; parameters = [:]; return }
        var pieces: [String] = []
        var current = ""
        var inQuote = false
        for char in header {
            if char == "\"" { inQuote.toggle() }
            if char == ";" && !inQuote { pieces.append(current); current = "" } else { current.append(char) }
        }
        pieces.append(current)
        value = pieces.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        var raw: [String: String] = [:]
        for piece in pieces.dropFirst() {
            guard let eq = piece.firstIndex(of: "=") else { continue }
            let key = piece[..<eq].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var val = piece[piece.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if val.hasPrefix("\""), val.hasSuffix("\""), val.count >= 2 { val = String(val.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"") }
            raw[key] = val
        }
        // RFC 2231: name*N / name*N* continuations and name* extended values.
        var merged: [String: String] = [:]
        var continuations: [String: [(Int, String, Bool)]] = [:]
        for (key, val) in raw {
            if let star = key.firstIndex(of: "*") {
                let base = String(key[..<star])
                let rest = key[key.index(after: star)...]
                if rest.isEmpty {
                    merged[base] = Self.decodeExtended(val, first: true)
                } else {
                    let extended = rest.hasSuffix("*")
                    let index = Int(rest.replacingOccurrences(of: "*", with: "")) ?? 0
                    continuations[base, default: []].append((index, val, extended))
                }
            } else if merged[key] == nil {
                merged[key] = RFC2047.decode(val)
            }
        }
        for (base, parts) in continuations {
            let joined = parts.sorted { $0.0 < $1.0 }.enumerated().map { offset, part in
                part.2 ? Self.decodeExtended(part.1, first: offset == 0) : part.1
            }.joined()
            merged[base] = joined
        }
        parameters = merged
    }

    public subscript(_ key: String) -> String? { parameters[key.lowercased()] }

    /// `UTF-8''%E2%82%AC.pdf` → "€.pdf" (charset prefix only on the first segment).
    static func decodeExtended(_ value: String, first: Bool) -> String {
        var text = value
        var charset = "utf-8"
        if first {
            let parts = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3 { charset = String(parts[0]).isEmpty ? "utf-8" : String(parts[0]); text = String(parts[2]) }
        }
        var bytes: [UInt8] = []
        var iterator = Array(text.utf8)[...]
        while let byte = iterator.popFirst() {
            if byte == UInt8(ascii: "%"), iterator.count >= 2, let v = UInt8(String(decoding: iterator.prefix(2), as: UTF8.self), radix: 16) {
                bytes.append(v)
                iterator = iterator.dropFirst(2)
            } else {
                bytes.append(byte)
            }
        }
        return MIMECharset.decode(Data(bytes), charset: charset) ?? text
    }
}

/// One MIME entity: headers plus either a decoded body (leaf) or child parts (multipart). Built from Gmail's JSON
/// payload (`GmailMessagePart.mime`) or from raw RFC 2822 text (`MIMEParser`).
public struct MIMEPart: Hashable, Sendable {
    public var headers: [MIMEHeader]
    /// Leaf content with the transfer encoding removed (still in its charset).
    public var body: Data
    public var parts: [MIMEPart]
    /// Gmail's part id ("0.1") when the part came from the API.
    public var partID: String?
    /// Gmail's attachment id when the body was not inlined (fetch with `GmailEndpoints.attachment`).
    public var attachmentID: String?
    /// Body size in bytes as reported by Gmail (or the decoded size).
    public var size: Int

    public init(headers: [MIMEHeader], body: Data = Data(), parts: [MIMEPart] = [], partID: String? = nil, attachmentID: String? = nil, size: Int? = nil) {
        self.headers = headers
        self.body = body
        self.parts = parts
        self.partID = partID
        self.attachmentID = attachmentID
        self.size = size ?? body.count
    }

    /// First header named `name` (case-insensitive), raw.
    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// First header, RFC 2047-decoded and unfolded.
    public func decodedHeader(_ name: String) -> String? {
        header(name).map { RFC2047.decode($0.replacingOccurrences(of: "\r\n", with: "").replacingOccurrences(of: "\n", with: "")) }
    }

    public var contentType: HeaderParameters { HeaderParameters(header("Content-Type") ?? "text/plain; charset=us-ascii") }
    public var mimeType: String { contentType.value.isEmpty ? "text/plain" : contentType.value }
    public var charset: String? { contentType["charset"] }
    public var isMultipart: Bool { mimeType.hasPrefix("multipart/") }
    public var disposition: HeaderParameters { HeaderParameters(header("Content-Disposition")) }
    public var contentID: String? {
        header("Content-ID").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t")) }
    }
    public var filename: String? {
        let name = disposition["filename"] ?? contentType["name"]
        return (name?.isEmpty ?? true) ? nil : name
    }
    /// The body decoded as text in its charset.
    public var text: String? { MIMECharset.decode(body, charset: charset) }

    /// Every leaf, depth first.
    public var leaves: [MIMEPart] { isMultipart ? parts.flatMap(\.leaves) : [self] }
}

/// A file carried by a message.
public struct MailAttachment: Codable, Hashable, Sendable, Identifiable {
    public var partID: String?
    public var attachmentID: String?
    public var filename: String
    public var mimeType: String
    public var size: Int
    /// `Content-ID` without angle brackets (inline images referenced as `cid:`).
    public var contentID: String?
    public var isInline: Bool
    /// Present when the body was inlined in the payload (small parts); otherwise fetch by `attachmentID`.
    public var data: Data?

    public var id: String { attachmentID ?? partID ?? filename }

    public init(partID: String? = nil, attachmentID: String? = nil, filename: String, mimeType: String, size: Int, contentID: String? = nil,
                isInline: Bool = false, data: Data? = nil) {
        self.partID = partID
        self.attachmentID = attachmentID
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.contentID = contentID
        self.isInline = isInline
        self.data = data
    }
}

/// The readable content of a message: best HTML and plain-text bodies plus attachments.
public struct MIMEContent: Hashable, Sendable {
    public var html: String?
    public var text: String?
    public var attachments: [MailAttachment]

    public init(html: String? = nil, text: String? = nil, attachments: [MailAttachment] = []) {
        self.html = html
        self.text = text
        self.attachments = attachments
    }

    /// Walks the tree: in multipart/alternative the richest version wins (last HTML, last plain text); in
    /// multipart/mixed / related the first text parts are the body and the rest are attachments; parts with a
    /// filename or `Content-Disposition: attachment` are attachments; inline images with a Content-ID are kept as
    /// inline attachments for `cid:` references.
    public static func extract(_ root: MIMEPart) -> MIMEContent {
        var content = MIMEContent()
        visit(root, into: &content)
        return content
    }

    private static func visit(_ part: MIMEPart, into content: inout MIMEContent) {
        if part.isMultipart {
            if part.mimeType == "multipart/alternative" {
                // Richest last: take the last html / text leaf of each alternative branch.
                var html: String?, text: String?
                var other = MIMEContent()
                for child in part.parts {
                    var branch = MIMEContent()
                    visit(child, into: &branch)
                    if let h = branch.html { html = h }
                    if let t = branch.text { text = t }
                    other.attachments += branch.attachments
                }
                if content.html == nil { content.html = html }
                if content.text == nil { content.text = text }
                content.attachments += other.attachments
            } else {
                for child in part.parts { visit(child, into: &content) }
            }
            return
        }
        let type = part.mimeType
        let isAttachment = part.disposition.value == "attachment" || part.filename != nil
        if !isAttachment, type == "text/html", content.html == nil {
            content.html = part.text
        } else if !isAttachment, type == "text/plain", content.text == nil {
            content.text = part.text
        } else if isAttachment || part.contentID != nil || !type.hasPrefix("text/") {
            let name = part.filename ?? (part.contentID.map { "\($0)" } ?? "attachment")
            content.attachments.append(MailAttachment(
                partID: part.partID, attachmentID: part.attachmentID, filename: name, mimeType: type, size: part.size,
                contentID: part.contentID, isInline: part.disposition.value == "inline" || (part.disposition.value.isEmpty && part.contentID != nil),
                data: part.body.isEmpty ? nil : part.body))
        }
    }
}

// MARK: - Raw RFC 2822 parsing

public enum MIMEParser {
    /// Parses a whole message or entity. Byte-safe: the text is handled as Latin-1 so 8-bit bodies survive.
    public static func parse(_ data: Data) -> MIMEPart {
        parse(latin1: String(data: data, encoding: .isoLatin1) ?? "")
    }

    public static func parse(_ text: String) -> MIMEPart {
        // A Swift String given directly is treated as UTF-8 bytes.
        parse(Data(text.utf8))
    }

    static func parse(latin1 text: String, partID: String = "") -> MIMEPart {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let headerText: Substring
        let bodyText: Substring
        if let range = normalized.range(of: "\n\n") {
            headerText = normalized[..<range.lowerBound]
            bodyText = normalized[range.upperBound...]
        } else if normalized.hasPrefix("\n") {
            headerText = ""
            bodyText = normalized.dropFirst()
        } else {
            headerText = Substring(normalized)
            bodyText = ""
        }
        let headers = parseHeaders(String(headerText))
        var part = MIMEPart(headers: headers.map { MIMEHeader(name: $0.name, value: latin1ToUTF8($0.value)) }, partID: partID)
        if part.isMultipart, let boundary = part.contentType["boundary"] {
            let children = split(String(bodyText), boundary: boundary)
            part.parts = children.enumerated().map { index, child in
                parse(latin1: child, partID: partID.isEmpty ? String(index) : "\(partID).\(index)")
            }
            part.size = 0
        } else {
            let bytes = Data(bodyText.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) })
            part.body = decodeTransfer(bytes, encoding: part.header("Content-Transfer-Encoding"))
            part.size = part.body.count
        }
        return part
    }

    /// Unfolds continuation lines.
    static func parseHeaders(_ text: String) -> [MIMEHeader] {
        var headers: [MIMEHeader] = []
        for line in text.components(separatedBy: "\n") {
            if let first = line.first, first == " " || first == "\t", !headers.isEmpty {
                headers[headers.count - 1].value += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                headers.append(MIMEHeader(name: String(line[..<colon]).trimmingCharacters(in: .whitespaces),
                                          value: String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)))
            }
        }
        return headers
    }

    static func split(_ body: String, boundary: String) -> [String] {
        let delimiter = "--" + boundary
        var parts: [String] = []
        var current: [Substring]? = nil
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == delimiter + "--" {
                if let current { parts.append(current.joined(separator: "\n")) }
                current = nil
                break
            }
            if trimmed == delimiter {
                if let current { parts.append(current.joined(separator: "\n")) }
                current = []
            } else if current != nil {
                current!.append(line)
            }
        }
        if let current { parts.append(current.joined(separator: "\n")) }
        return parts
    }

    static func decodeTransfer(_ data: Data, encoding: String?) -> Data {
        switch encoding?.lowercased().trimmingCharacters(in: .whitespaces) {
        case "base64":
            let text = String(decoding: data, as: UTF8.self).components(separatedBy: .whitespacesAndNewlines).joined()
            return Base64URL.decode(text) ?? data
        case "quoted-printable":
            return QuotedPrintable.decode(String(data: data, encoding: .isoLatin1) ?? "")
        default:
            var text = data
            // Drop the line break that precedes a boundary.
            if text.last == 0x0A { text.removeLast() }
            return text
        }
    }

    /// Header bytes arrive as Latin-1 code points; 8-bit UTF-8 headers are re-read as UTF-8.
    static func latin1ToUTF8(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.value > 0x7F }) else { return text }
        let bytes = Data(text.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) })
        return String(data: bytes, encoding: .utf8) ?? text
    }
}

// MARK: - Quoted-printable

public enum QuotedPrintable {
    /// Encodes with CRLF line breaks and soft breaks so no line exceeds 76 characters.
    public static func encode(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        return lines.map(encodeLine).joined(separator: "\r\n")
    }

    static func encodeLine(_ line: String) -> String {
        let bytes = Array(line.utf8)
        var tokens: [String] = []
        for (index, byte) in bytes.enumerated() {
            let isLast = index == bytes.count - 1
            if (byte == 0x20 || byte == 0x09) && isLast {
                tokens.append(String(format: "=%02X", byte))
            } else if byte == UInt8(ascii: "=") || byte < 0x20 && byte != 0x09 || byte > 0x7E {
                tokens.append(String(format: "=%02X", byte))
            } else {
                tokens.append(String(UnicodeScalar(byte)))
            }
        }
        var out = ""
        var width = 0
        for token in tokens {
            if width + token.count > 75 {
                out += "=\r\n"
                width = 0
            }
            out += token
            width += token.count
        }
        return out
    }

    public static func decode(_ text: String) -> Data {
        var bytes: [UInt8] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (index, rawLine) in lines.enumerated() {
            var line = Substring(rawLine)
            while let last = line.last, last == " " || last == "\t" { line = line.dropLast() }
            var soft = false
            if line.hasSuffix("=") { soft = true; line = line.dropLast() }
            var scalars = Array(line.unicodeScalars)[...]
            while let scalar = scalars.popFirst() {
                if scalar == "=", scalars.count >= 2,
                   let value = UInt8(String(String.UnicodeScalarView(scalars.prefix(2))), radix: 16) {
                    bytes.append(value)
                    scalars = scalars.dropFirst(2)
                } else {
                    bytes.append(UInt8(truncatingIfNeeded: scalar.value))
                }
            }
            if !soft && index < lines.count - 1 { bytes.append(0x0A) }
        }
        return Data(bytes)
    }
}
