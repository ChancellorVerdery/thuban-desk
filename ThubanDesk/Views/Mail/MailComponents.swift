import SwiftUI
import ThubanDeskCore

// Small pieces shared by the Mail area and Compose (owned by the Mail engineer).

/// Design checkbox: 18 pt, radius 5; on = accent fill with a dark check; off = 1.5 pt line2 border on the field.
struct MailCheckbox: View {
    @Environment(\.thubanTheme) private var theme
    var isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(theme.accentColor)
                Icon(.check, size: 13, lineWidth: 2.4).foregroundStyle(theme.onAccentColor)
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(theme.fieldColor)
                RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
    }
}

/// A filled design icon (the starred star).
struct FilledIcon: View {
    var name: IconName
    var size: CGFloat = 13

    init(_ name: IconName, size: CGFloat = 13) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 24
            let path = Path(name.path).applying(CGAffineTransform(scaleX: scale, y: scale))
            context.fill(path, with: .foreground)
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.5 * scale, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A label chip in a label's colour role (soft fill, role text).
struct LabelChip: View {
    @Environment(\.thubanTheme) private var theme
    var name: String
    var tint: CalendarTint
    var compact: Bool = false

    var body: some View {
        Text(name)
            .font(.system(size: compact ? 11.5 : 12.5, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(theme.textColor(for: tint))
            .padding(.horizontal, compact ? 6 : 8)
            .frame(height: compact ? 20 : 22)
            .background(theme.softColor(for: tint), in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
    }
}

/// A ghost toolbar button with icon + label (design: 32 pt, 13.5 pt semibold, inkDim).
struct MailToolButton: View {
    var title: String
    var icon: IconName?
    var fontSize: CGFloat = 13.5
    var height: CGFloat = 32
    var ink: Bool = false
    var help: String?
    var action: () -> Void
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Icon(icon, size: 15) }
                Text(title).font(.system(size: fontSize, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(ink ? theme.inkColor : theme.inkDimColor)
        }
        .buttonStyle(GhostButtonStyle(height: height, horizontalPadding: ink ? 8 : 12))
        .help(help ?? title)
        .accessibilityLabel(title)
    }
}

/// One row of a `MenuPopover` (a themed replacement for NSMenu so icons and colours follow the design).
struct MenuPopoverItem: Identifiable {
    let id = UUID()
    var title: String
    var icon: IconName?
    var checked: Bool? = nil
    var destructive: Bool = false
    var disabled: Bool = false
    var divider: Bool = false
    var action: () -> Void = {}

    static var separator: MenuPopoverItem { MenuPopoverItem(title: "", divider: true) }
}

/// A vertical list of menu rows in a popover.
struct MenuPopoverList: View {
    @Environment(\.thubanTheme) private var theme
    var items: [MenuPopoverItem]
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(items) { item in
                if item.divider {
                    Rectangle().fill(theme.lineColor).frame(height: 1).padding(.vertical, 4)
                } else {
                    MenuPopoverRow(item: item) {
                        dismiss()
                        item.action()
                    }
                }
            }
        }
        .padding(6)
        .frame(minWidth: 220, alignment: .leading)
        .background(theme.panelColor)
    }
}

private struct MenuPopoverRow: View {
    @Environment(\.thubanTheme) private var theme
    var item: MenuPopoverItem
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let checked = item.checked {
                    Icon(.check, size: 13, lineWidth: 2.2).foregroundStyle(theme.brassInkColor).opacity(checked ? 1 : 0)
                }
                if let icon = item.icon { Icon(icon, size: 15) }
                Text(item.title).font(ThubanFont.body(13.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 12)
            }
            .foregroundStyle(item.destructive ? theme.negTextColor : theme.inkColor)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(hovering && !item.disabled ? theme.panel2Color : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.disabled)
        .opacity(item.disabled ? 0.45 : 1)
        .onHover { hovering = $0 }
    }
}

/// An icon button that opens a `MenuPopoverList`.
struct MenuPopoverButton: View {
    var icon: IconName
    var label: String
    var size: CGFloat = 32
    var iconSize: CGFloat = 15
    var items: () -> [MenuPopoverItem]
    @State private var open = false
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        IconButton(icon, label: label, size: size, iconSize: iconSize) { open.toggle() }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                MenuPopoverList(items: items()) { open = false }
                    .environment(\.thubanTheme, theme)
            }
    }
}

/// Lays children out in rows, wrapping (recipient tokens).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = Self.measure(view, maxWidth: width)
            if x > 0, x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + lineHeight)
    }

    /// Ideal size, capped to the line width (text fields would otherwise claim the whole line).
    static func measure(_ view: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = view.sizeThatFits(.unspecified)
        guard ideal.width > maxWidth else { return ideal }
        return view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        var rows: [[(LayoutSubview, CGSize)]] = [[]]
        for view in subviews {
            let size = Self.measure(view, maxWidth: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                rows.append([])
                x = bounds.minX
            }
            rows[rows.count - 1].append((view, size))
            x += size.width + spacing
        }
        for row in rows {
            lineHeight = row.map(\.1.height).max() ?? 0
            x = bounds.minX
            for (view, size) in row {
                // The last item (the text field) takes the rest of its line.
                let isLast = view == subviews.last
                let width = isLast ? max(size.width, bounds.maxX - x) : size.width
                view.place(at: CGPoint(x: x, y: y + (lineHeight - size.height) / 2), proposal: ProposedViewSize(width: width, height: size.height))
                x += size.width + spacing
            }
            y += lineHeight + lineSpacing
        }
    }
}

extension ResolvedTheme {
    /// Input field ground (design `field`): panel on light, a shade under the panel on dark.
    var fieldColor: Color { isDark ? bgColor : panelColor }
    /// Dimmed ground behind the Compose window (design `scrim`).
    var scrimColor: Color { isDark ? bgColor.opacity(0.62) : inkColor.opacity(0.30) }
    /// Brass unread dot (brass ink on light, the accent on dark).
    var unreadDotColor: Color { brassInkColor }
}

/// Dates in the reader: "Today, 2:14 PM", "Yesterday, 9:12 AM", "Mon, Sep 21, 10:02 AM".
enum MailDateText {
    static func reader(_ date: Date, now: Date, zone: TimeZone) -> String {
        let day = CivilDate(date, in: zone), today = CivilDate(now, in: zone)
        let time = DeskFormat.time(date, zone: zone)
        let diff = day.days(to: today)
        if diff == 0 { return "Today, \(time)" }
        if diff == 1 { return "Yesterday, \(time)" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = zone
        formatter.dateFormat = Calendar.gregorian(zone).component(.year, from: date) == Calendar.gregorian(zone).component(.year, from: now) ? "EEE, MMM d" : "EEE, MMM d, yyyy"
        return "\(formatter.string(from: date)), \(time)"
    }
}

/// A deterministic avatar colour for a person (the user = accent).
enum MailAvatarTint {
    static func tint(for address: EmailAddress?, own: Set<String>) -> CalendarTint {
        guard let address else { return .grey }
        if own.contains(address.normalized) { return .accent }
        let roles: [CalendarTint] = [.signal, .pos, .neg, .grey, .accent]
        let sum = address.normalized.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        return roles[sum % roles.count]
    }
}
