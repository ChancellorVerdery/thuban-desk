import Foundation

/// JSON coding for Google's REST payloads (camelCase keys as-is, RFC 3339 dates with or without fractional seconds).
public enum GoogleJSON {
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = RFC3339.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an RFC 3339 date: \(text)")
            }
            return date
        }
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(RFC3339.string(from: date))
        }
        return encoder
    }()

    /// Encoder for the on-disk cache (same format, so `decoder` reads it back).
    public static var cacheEncoder: JSONEncoder { encoder }
}

/// RFC 3339 timestamps (`2026-09-21T10:10:00-04:00`, `2026-09-21T14:10:00.000Z`).
public enum RFC3339 {
    public static func date(from text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    /// UTC `Z` form.
    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// With the zone's offset at that instant (`2026-09-21T10:10:00-04:00`).
    public static func string(from date: Date, in timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

/// Google's error envelope: `{"error": {"code": 403, "message": "…", "errors": [{"reason": "…"}], "status": "…"}}`
/// and the OAuth form `{"error": "invalid_grant", "error_description": "…"}`.
struct GoogleErrorEnvelope: Decodable {
    struct Body: Decodable {
        struct Item: Decodable { var reason: String?; var message: String? }
        var code: Int?
        var message: String?
        var status: String?
        var errors: [Item]?
    }

    var body: Body?
    var oauthError: String?
    var oauthDescription: String?

    enum CodingKeys: String, CodingKey { case error, errorDescription = "error_description" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let body = try? c.decode(Body.self, forKey: .error) {
            self.body = body
        } else {
            oauthError = try? c.decode(String.self, forKey: .error)
            oauthDescription = try? c.decode(String.self, forKey: .errorDescription)
        }
    }

    static func parse(_ data: Data) -> GoogleErrorEnvelope? { try? JSONDecoder().decode(GoogleErrorEnvelope.self, from: data) }

    var reason: String? { body?.errors?.first?.reason ?? oauthError }
    var message: String? { body?.message ?? oauthDescription ?? oauthError }
}
