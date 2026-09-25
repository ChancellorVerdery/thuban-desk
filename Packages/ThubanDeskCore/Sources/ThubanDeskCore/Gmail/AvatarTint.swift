import Foundation

/// The colour role of a person's avatar, shared by Mail, Compose and Today so one sender always looks the same.
/// Your own addresses are `accent`; everyone else gets a stable seeded FNV-1a hash of the address over the five
/// roles. The seed was chosen so the sample senders get the colours the design artboards gave them (Priya and Maya
/// teal, Mom rose, Dr. Park brass, Jordan and UREC green, automated senders grey); any other address still gets a
/// stable, arbitrary role.
public enum AvatarTint {
    public static let roles: [CalendarTint] = [.signal, .pos, .neg, .grey, .accent]
    static let seed: UInt64 = 743_548

    public static func tint(for address: EmailAddress?, own: Set<String> = []) -> CalendarTint {
        guard let address else { return .grey }
        if own.contains(address.normalized) { return .accent }
        return tint(forEmail: address.normalized)
    }

    public static func tint(forEmail email: String) -> CalendarTint {
        var hash: UInt64 = 14_695_981_039_346_656_037 ^ seed
        for byte in email.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return roles[Int(hash % UInt64(roles.count))]
    }
}
