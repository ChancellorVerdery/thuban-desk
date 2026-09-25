import SwiftUI
import ThubanDeskCore

/// A titled group of settings (serif title, optional caption).
struct SettingsGroup<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var caption: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String, caption: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(ThubanFont.display(18)).foregroundStyle(theme.inkColor)
                if let caption {
                    Text(caption).font(ThubanFont.small).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Label on the left, control on the right, inside a panel row.
struct SettingsRow<Control: View>: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    var detail: String?
    @ViewBuilder var control: () -> Control

    init(_ label: String, detail: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.detail = detail
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(ThubanFont.body(14.5, weight: .medium)).foregroundStyle(theme.inkColor)
                if let detail {
                    Text(detail).font(ThubanFont.body(12.5)).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
    }
}

/// A panel card with an eyebrow header and hairline-separated rows (design: "GOOGLE ACCOUNTS · 2", "DEFAULTS").
struct SettingsCard<Header: View, Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder header: @escaping () -> Header = { EmptyView() }, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.header = header
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title) { header() }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            content()
        }
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }
}

/// A 1 px separator inside cards.
struct Hairline: View {
    @Environment(\.thubanTheme) private var theme
    var body: some View { Rectangle().fill(theme.lineColor).frame(height: 1) }
}

struct SettingsNote: View {
    @Environment(\.thubanTheme) private var theme
    enum Tone { case neutral, positive, negative }
    var text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(ThubanFont.small)
            .foregroundStyle(tone == .neutral ? theme.inkDimColor : tone == .positive ? theme.posTextColor : theme.negTextColor)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A switch drawn in the Thuban style (accent when on).
struct ThubanToggle: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(theme.accentColor)
            .accessibilityLabel(label)
    }
}

struct ThubanFieldStyle: ViewModifier {
    @Environment(\.thubanTheme) private var theme
    var invalid: Bool = false
    var mono: Bool = false
    var height: CGFloat = ThubanMetrics.buttonHeight

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(mono ? ThubanFont.mono(13) : ThubanFont.body(14))
            .foregroundStyle(theme.inkColor)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                .strokeBorder(invalid ? theme.negColor : theme.line2Color, lineWidth: invalid ? 1.5 : ThubanMetrics.hairline))
    }
}

extension View {
    func thubanField(invalid: Bool = false, mono: Bool = false, height: CGFloat = ThubanMetrics.buttonHeight) -> some View {
        modifier(ThubanFieldStyle(invalid: invalid, mono: mono, height: height))
    }
}

/// A labelled field (label above).
struct LabeledField<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    @ViewBuilder var content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(ThubanFont.body(13, weight: .semibold)).foregroundStyle(theme.inkDimColor)
            content()
        }
    }
}
