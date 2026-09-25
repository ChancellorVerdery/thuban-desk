import Foundation

/// RFC 2047 encoded-words in headers (`=?UTF-8?B?…?=`, `=?iso-8859-1?Q?…?=`).
public enum RFC2047 {
    /// Decodes every encoded-word; whitespace between two adjacent encoded-words is dropped (RFC 2047 §6.2).
    public static func decode(_ header: String) -> String {
        guard header.contains("=?") else { return header }
        let pattern = try! NSRegularExpression(pattern: #"=\?([^?\s]+)\?([BbQq])\?([^?]*)\?="#)
        let ns = header as NSString
        var output = ""
        var cursor = 0
        var lastWasEncoded = false
        for match in pattern.matches(in: header, range: NSRange(location: 0, length: ns.length)) {
            let between = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            if !(lastWasEncoded && between.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { output += between }
            let charset = ns.substring(with: match.range(at: 1))
            let mode = ns.substring(with: match.range(at: 2)).uppercased()
            let text = ns.substring(with: match.range(at: 3))
            let bytes: Data? = mode == "B" ? Data(base64Encoded: padded(text)) : qDecode(text)
            if let bytes, let decoded = MIMECharset.decode(bytes, charset: charset) {
                output += decoded
                lastWasEncoded = true
            } else {
                output += ns.substring(with: match.range)
                lastWasEncoded = false
            }
            cursor = match.range.location + match.range.length
        }
        output += ns.substring(from: cursor)
        return output
    }

    /// Encodes a header value when it has non-ASCII characters (UTF-8, base64 words of at most 75 characters,
    /// split on character boundaries). ASCII text is returned unchanged.
    public static func encode(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { !$0.isASCII }) else { return text }
        var words: [String] = []
        var chunk = ""
        for character in text {
            let candidate = chunk + String(character)
            // 45 UTF-8 bytes → 60 base64 characters, + 12 for the wrapper = 72 ≤ 75.
            if candidate.utf8.count > 45, !chunk.isEmpty {
                words.append(word(chunk))
                chunk = String(character)
            } else {
                chunk = candidate
            }
        }
        if !chunk.isEmpty { words.append(word(chunk)) }
        return words.joined(separator: "\r\n ")
    }

    private static func word(_ text: String) -> String {
        "=?UTF-8?B?\(Data(text.utf8).base64EncodedString())?="
    }

    private static func padded(_ text: String) -> String {
        let remainder = text.count % 4
        return remainder == 0 ? text : text + String(repeating: "=", count: 4 - remainder)
    }

    /// "Q" encoding: `_` is a space, `=XX` a byte.
    static func qDecode(_ text: String) -> Data? {
        var bytes: [UInt8] = []
        var iterator = Array(text.utf8)[...]
        while let byte = iterator.popFirst() {
            if byte == UInt8(ascii: "_") {
                bytes.append(0x20)
            } else if byte == UInt8(ascii: "="), iterator.count >= 2,
                      let value = UInt8(String(decoding: iterator.prefix(2), as: UTF8.self), radix: 16) {
                bytes.append(value)
                iterator = iterator.dropFirst(2)
            } else {
                bytes.append(byte)
            }
        }
        return Data(bytes)
    }
}

/// Charset names from MIME headers → String decoding.
public enum MIMECharset {
    public static func encoding(for charset: String?) -> String.Encoding {
        switch (charset ?? "utf-8").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) {
        case "utf-8", "utf8": return .utf8
        case "us-ascii", "ascii": return .ascii
        case "iso-8859-1", "latin1", "iso8859-1": return .isoLatin1
        case "iso-8859-2", "latin2": return .isoLatin2
        case "windows-1252", "cp1252": return .windowsCP1252
        case "windows-1251", "cp1251": return .windowsCP1251
        case "windows-1250", "cp1250": return .windowsCP1250
        case "utf-16": return .utf16
        case "utf-16le": return .utf16LittleEndian
        case "utf-16be": return .utf16BigEndian
        case "shift_jis", "shift-jis", "sjis": return .shiftJIS
        case "euc-jp": return .japaneseEUC
        case "iso-2022-jp": return .iso2022JP
        case "macintosh", "mac": return .macOSRoman
        default:
            let cf = CFStringConvertIANACharSetNameToEncoding(charset! as CFString)
            if cf != kCFStringEncodingInvalidId {
                return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
            }
            return .utf8
        }
    }

    /// Decodes bytes; falls back to UTF-8 (lossy) and Latin-1 so a body is never lost.
    public static func decode(_ data: Data, charset: String?) -> String? {
        if let text = String(data: data, encoding: encoding(for: charset)) { return text }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1)
    }
}
