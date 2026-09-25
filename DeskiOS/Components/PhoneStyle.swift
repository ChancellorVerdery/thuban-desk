import SwiftUI
import ThubanDeskCore

/// iOS type scale (design IOS_BRIEF): body 17, secondary 15, footnote 13, micro 12 uppercase, large serif title 34.
/// Every size is a Dynamic Type text style, so the whole app follows the system text size.
enum PhoneFont {
    static let body = Font.body
    static let bodySemibold = Font.body.weight(.semibold)
    static let secondary = Font.subheadline
    static let secondarySemibold = Font.subheadline.weight(.semibold)
    static let footnote = Font.footnote
    static let footnoteSemibold = Font.footnote.weight(.semibold)
    /// 12 pt semibold, uppercase with tracking (apply `.textCase(.uppercase)` + `.kerning(0.9)` — see `Eyebrow`).
    static let micro = Font.caption.weight(.semibold)
    static let tabLabel = Font.caption2.weight(.semibold)
    static let largeTitle = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let inlineTitle = Font.headline
    static func display(_ style: Font.TextStyle) -> Font { Font.system(style, design: .serif).weight(.semibold) }
    static let mono = Font.system(.footnote, design: .monospaced)
    static let monoSmall = Font.system(.caption2, design: .monospaced).weight(.bold)
}

enum PhoneMetrics {
    static let gutter: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let rowHeight: CGFloat = 52
    static let navHeight: CGFloat = 44
    static let hit: CGFloat = 44
    static let primaryHeight: CGFloat = 50
}

extension ResolvedTheme {
    /// The recessed fill of segmented tracks, search fields and date pills: panel2 pushed toward the hairline.
    var fillColor: Color { panel2Color.mix(with: lineColor, by: 0.6) }
    /// Text on an accent fill (primary buttons, today's date).
    var onAccentInk: Color { Color(hex: onAccent) }
    /// Dimmed parent behind a sheet / action sheet.
    var scrimColor: Color { Color.black.opacity(isDark ? 0.55 : 0.32) }
    /// Separator chevrons.
    var chevronColor: Color { inkFaintColor.opacity(0.7) }
}

/// "AGENDA · 4 EVENTS" eyebrow.
struct Eyebrow: View {
    @Environment(\.thubanTheme) private var theme
    var text: String
    var color: Color?

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(PhoneFont.micro)
            .textCase(.uppercase)
            .kerning(0.9)
            .foregroundStyle(color ?? theme.inkDimColor)
            .accessibilityAddTraits(.isHeader)
    }
}

/// An inset grouped card: panel fill, 1 px hairline, radius 12 (or bg fill inside sheets).
struct InsetCard<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var fill: Color?
    @ViewBuilder var content: () -> Content

    init(fill: Color? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.fill = fill
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill ?? theme.panelColor)
            .clipShape(RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
    }
}

/// 1 px separator inset from the leading edge.
struct RowDivider: View {
    @Environment(\.thubanTheme) private var theme
    var inset: CGFloat = 16

    var body: some View {
        Rectangle().fill(theme.lineColor).frame(height: 1).padding(.leading, inset)
    }
}

/// A grouped-list row: leading content, trailing value and an optional chevron; ≥ 52 pt tall.
struct PhoneRow<Leading: View, Trailing: View>: View {
    @Environment(\.thubanTheme) private var theme
    var chevron: Bool = false
    var highlighted: Bool = false
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading()
            Spacer(minLength: 8)
            trailing()
            if chevron { Icon(.chevronRight, size: 16, lineWidth: 2).foregroundStyle(theme.chevronColor) }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(minHeight: PhoneMetrics.rowHeight)
        .background(highlighted ? theme.accentTintColor : Color.clear)
        .contentShape(Rectangle())
    }
}

extension PhoneRow where Trailing == EmptyView {
    init(chevron: Bool = false, highlighted: Bool = false, @ViewBuilder leading: @escaping () -> Leading) {
        self.init(chevron: chevron, highlighted: highlighted, leading: leading, trailing: { EmptyView() })
    }
}

/// The segmented control of the boards: recessed track, selected segment = panel + hairline.
struct PhoneSegmented<Value: Hashable>: View {
    @Environment(\.thubanTheme) private var theme
    var options: [(value: Value, label: String)]
    @Binding var selection: Value
    var accessibilityName: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? theme.inkColor : theme.inkDimColor)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.panelColor)
                                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .frame(minHeight: 34)
        .background(theme.fillColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }
}

/// Recessed search field ("Search mail").
struct PhoneSearchField: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void = {}
    var focus: FocusState<Bool>.Binding?

    var body: some View {
        HStack(spacing: 6) {
            Icon(.search, size: 17).foregroundStyle(theme.inkFaintColor)
            field
            if !text.isEmpty {
                Button { text = ""; onSubmit() } label: {
                    Icon(.close, size: 14, lineWidth: 2).foregroundStyle(theme.inkDimColor).frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 36)
        .background(theme.fillColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder private var field: some View {
        let base = TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(theme.inkFaintColor))
            .font(PhoneFont.body)
            .foregroundStyle(theme.inkColor)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(onSubmit)
        if let focus { base.focused(focus) } else { base }
    }
}

/// Brass text button in a nav row ("Select", "Done", "Cancel").
struct NavTextButton: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var bold = false
    var action: () -> Void

    init(_ title: String, bold: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.bold = bold
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(bold ? PhoneFont.bodySemibold : PhoneFont.body)
                .foregroundStyle(theme.brassInkColor)
                .padding(.horizontal, 8)
                .frame(minHeight: PhoneMetrics.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 44 × 44 brass icon button with a VoiceOver label.
struct NavIconButton: View {
    @Environment(\.thubanTheme) private var theme
    var icon: IconName
    var label: String
    var size: CGFloat = 22
    var action: () -> Void

    init(_ icon: IconName, label: String, size: CGFloat = 22, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Icon(icon, size: size)
                .foregroundStyle(theme.brassInkColor)
                .frame(width: PhoneMetrics.hit, height: PhoneMetrics.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// "< Mailboxes" back button.
struct BackButton: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Icon(.chevronLeft, size: 24, lineWidth: 2)
                Text(title).font(PhoneFont.body).lineLimit(1)
            }
            .foregroundStyle(theme.brassInkColor)
            .padding(.trailing, 8)
            .frame(minHeight: PhoneMetrics.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(title)")
    }
}

/// Full-width primary action: accent fill, dark ink, radius 12, ≥ 50 pt.
struct PhonePrimaryButtonStyle: ButtonStyle {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    var destructive = false
    var height: CGFloat = PhoneMetrics.primaryHeight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PhoneFont.bodySemibold)
            .foregroundStyle(destructive ? (theme.isDark ? theme.bgColor : theme.panelColor) : theme.onAccentInk)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(destructive ? theme.negTextColor : theme.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.45))
    }
}

/// Secondary: panel fill + line2 hairline.
struct PhoneSecondaryButtonStyle: ButtonStyle {
    @Environment(\.thubanTheme) private var theme
    var height: CGFloat = 40
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PhoneFont.secondarySemibold)
            .foregroundStyle(tint ?? theme.inkColor)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// A label / account chip: soft fill, 6 pt radius, 12 pt semibold.
struct PhoneChip: View {
    @Environment(\.thubanTheme) private var theme
    var text: String
    var tint: CalendarTint?
    var dot: CalendarTint?

    var body: some View {
        HStack(spacing: 5) {
            if let dot { Circle().fill(theme.color(for: dot)).frame(width: 6, height: 6) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint.map { theme.textColor(for: $0) } ?? theme.inkDimColor)
        .padding(.horizontal, 7)
        .frame(minHeight: 22)
        .background(tint.map { theme.softColor(for: $0) } ?? theme.fillColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Initials in a circle: the user's own avatar (accent tint + ring) or a sender's.
struct PhoneAvatar: View {
    @Environment(\.thubanTheme) private var theme
    var name: String
    var tint: CalendarTint = .accent
    var size: CGFloat = 36
    /// "You" / own account: soft fill + accent ring (design Today / Thread).
    var ringed = false

    var body: some View {
        ZStack {
            if ringed {
                Circle().fill(theme.softColor(for: tint))
                Circle().strokeBorder(theme.color(for: tint), lineWidth: 1)
            } else {
                Circle().fill(theme.color(for: tint))
            }
            Text(AvatarView.initials(name))
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(ringed ? theme.textColor(for: tint) : (theme.isDark ? theme.bgColor : theme.inkColor))
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Error / info banner under a header.
struct PhoneBanner: View {
    @Environment(\.thubanTheme) private var theme
    var text: String
    var isError = true
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Icon(isError ? .spam : .info, size: 16).padding(.top, 1)
            Text(text).font(PhoneFont.footnote).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let dismiss {
                Button(action: dismiss) { Icon(.close, size: 14, lineWidth: 2).frame(width: 32, height: 32) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
            }
        }
        .foregroundStyle(isError ? theme.negTextColor : theme.inkDimColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isError ? theme.negSoftColor : theme.panel2Color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Icon + one sentence (+ optional action), centered.
struct PhoneEmptyState: View {
    @Environment(\.thubanTheme) private var theme
    var icon: IconName
    var text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Icon(icon, size: 30).foregroundStyle(theme.inkFaintColor)
            Text(text).font(PhoneFont.secondary).foregroundStyle(theme.inkDimColor).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(PhoneSecondaryButtonStyle(height: 44)).frame(maxWidth: 240)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// A design icon's outline filled (the starred star).
struct IconFill: View {
    var name: IconName
    var size: CGFloat

    init(_ name: IconName, size: CGFloat = 18) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 24
            context.fill(Path(name.path).applying(CGAffineTransform(scaleX: scale, y: scale)), with: .foreground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
