import Foundation

/// The colour role a calendar (or a mail label) is drawn in. The design maps every Google colour onto the theme's
/// five roles so each scheme stays coherent: `accent` (brass), `signal` (teal), `pos` (green), `neg` (rose), `grey`.
/// Views turn a tint into a colour with `theme.color(for:)`; never draw Google's hex directly.
public enum CalendarTint: String, Codable, CaseIterable, Sendable, Hashable {
    case accent, signal, pos, neg, grey

    public var label: String {
        switch self {
        case .accent: return "Accent"
        case .signal: return "Signal"
        case .pos: return "Green"
        case .neg: return "Rose"
        case .grey: return "Grey"
        }
    }

    /// Nearest role to a Google colour (`#9fe1e7`, …) by hue; low-saturation colours are grey. `nil` → accent.
    public static func from(googleHex: String?) -> CalendarTint {
        guard let googleHex, let (h, s, _) = hsl(googleHex) else { return .accent }
        if s < 0.18 { return .grey }
        switch h {
        case ..<20, 330...: return .neg
        case 20..<70: return .accent
        case 70..<165: return .pos
        case 165..<265: return .signal
        default: return .grey // purples
        }
    }

    /// Hue in degrees, saturation and lightness in 0…1.
    static func hsl(_ hex: String) -> (Double, Double, Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255, g = Double((value >> 8) & 0xFF) / 255, b = Double(value & 0xFF) / 255
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        let l = (maxC + minC) / 2
        guard delta > 0.0001 else { return (0, 0, l) }
        let s = delta / (1 - abs(2 * l - 1))
        var h: Double
        if maxC == r { h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if maxC == g { h = 60 * ((b - r) / delta + 2) }
        else { h = 60 * ((r - g) / delta + 4) }
        if h < 0 { h += 360 }
        return (h, s, l)
    }
}
