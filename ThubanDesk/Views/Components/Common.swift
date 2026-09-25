import SwiftUI
import ThubanDeskCore

extension ResolvedTheme {
    /// The fill for a calendar / label colour role (the design maps every Google colour onto these five).
    func color(for tint: CalendarTint) -> Color {
        switch tint {
        case .accent: return accentColor
        case .signal: return signalColor
        case .pos: return posColor
        case .neg: return negColor
        case .grey: return inkFaintColor
        }
    }

    /// Text / icon colour for a tint (contrast-safe on panel).
    func textColor(for tint: CalendarTint) -> Color {
        switch tint {
        case .accent: return brassInkColor
        case .signal: return signalTextColor
        case .pos: return posTextColor
        case .neg: return negTextColor
        case .grey: return inkDimColor
        }
    }

    /// A soft ground for event blocks and label chips.
    func softColor(for tint: CalendarTint) -> Color {
        switch tint {
        case .accent: return accentTintColor
        case .signal: return signalSoftColor
        case .pos: return posSoftColor
        case .neg: return negSoftColor
        case .grey: return panel2Color
        }
    }
}

/// A small filled circle in a tint (calendar legend, account tag).
struct TintDot: View {
    @Environment(\.thubanTheme) private var theme
    var tint: CalendarTint
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(theme.color(for: tint)).frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// "CALENDARS · 4" eyebrow with an optional trailing accessory.
struct SectionHeader<Accessory: View>: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var count: Int?
    @ViewBuilder var accessory: () -> Accessory

    init(_ title: String, count: Int? = nil, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.title = title
        self.count = count
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(count.map { "\(title.uppercased()) · \($0)" } ?? title.uppercased())
                .font(ThubanFont.micro)
                .kerning(0.96)
                .foregroundStyle(theme.inkDimColor)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            accessory()
        }
    }
}

/// Page title in the display serif, with an optional subtitle line.
struct PageTitle: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var subtitle: String?
    var size: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(ThubanFont.display(size)).foregroundStyle(theme.inkColor).accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(ThubanFont.body(15)).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Initials in a tinted circle (people in mail, guests, accounts).
struct AvatarView: View {
    @Environment(\.thubanTheme) private var theme
    var name: String
    var tint: CalendarTint = .accent
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(theme.color(for: tint))
            Text(Self.initials(name))
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(theme.isDark ? theme.bgColor : theme.inkColor)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func initials(_ name: String) -> String {
        EmailAddress("x@x", name: name).initials
    }
}

/// A row card with a hover highlight.
struct ListRowCard<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var action: (() -> Void)?
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    init(action: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.action = action
        self.content = content
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { row }.buttonStyle(.plain)
            } else {
                row
            }
        }
        .onHover { hovering = $0 }
    }

    private var row: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering && action != nil ? theme.panel2Color : theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
    }
}

/// A search field in the Thuban style.
struct SearchField: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var text: String
    var placeholder: String = "Search"
    var focusRequest: Int = 0
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Icon(.search, size: 14).foregroundStyle(theme.inkFaintColor)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(ThubanFont.body(13.5))
                .foregroundStyle(theme.inkColor)
                .focused($focused)
                .onSubmit(onSubmit)
                .onChange(of: focusRequest) { _, _ in focused = true }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Icon(.close, size: 12).foregroundStyle(theme.inkDimColor).frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
    }
}

/// Relative and clock formatting shared by every area.
enum DeskFormat {
    static func time(_ date: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = zone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// "2:38 PM" today, "Yesterday", "Tue", "Sep 12", "Sep 12, 2025" — the mail list's date column.
    static func listDate(_ date: Date, now: Date, zone: TimeZone) -> String {
        let calendar = Calendar.gregorian(zone)
        let today = CivilDate(now, in: zone), day = CivilDate(date, in: zone)
        let diff = day.days(to: today)
        if diff == 0 { return time(date, zone: zone) }
        if diff == 1 { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = zone
        if diff > 1 && diff < 7 { formatter.dateFormat = "EEE" } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatter.dateFormat = "MMM d"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date)
    }

    /// "26 min ago", "2 days ago".
    static func ago(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h ago" }
        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }
}
