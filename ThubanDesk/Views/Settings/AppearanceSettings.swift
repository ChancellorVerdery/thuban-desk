import SwiftUI
import ThubanDeskCore

/// Appearance pane: Mode (Auto / Light / Dark), the 3×3 scheme grid, and a live preview of the resolved theme.
struct AppearanceSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var isEditingCustom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup("Mode", caption: modeCaption) {
                SegmentedPicker(
                    selection: Binding(get: { app.themeSelection.mode }, set: { app.setAppearanceMode($0) }),
                    options: AppearanceMode.allCases.map { SegmentOption($0, $0.label) }
                )
            }

            SettingsGroup("Text size", caption: "Scales body text on every screen and inside mail and event notes.") {
                SegmentedPicker(
                    selection: Binding(get: { app.settings.textSize }, set: { app.settings.textSize = $0 }),
                    options: TextSize.allCases.map { SegmentOption($0, $0.label) }
                )
            }

            SettingsGroup("Accessibility", caption: "Applied to every Thuban Desk screen.") {
                SettingsRow("Reduce motion", detail: "Turns off spinning and sliding animations.") {
                    ThubanToggle(isOn: Binding(get: { app.settings.reduceMotion }, set: { app.settings.reduceMotion = $0 }), label: "Reduce motion")
                }
                SettingsRow("Dyslexia-friendly font", detail: "Uses a wider, more distinct typeface in mail and event notes.") {
                    ThubanToggle(isOn: Binding(get: { app.settings.dyslexiaFont }, set: { app.settings.dyslexiaFont = $0 }), label: "Dyslexia-friendly font")
                }
            }

            SettingsGroup("Scheme", caption: "Colors only. Every card uses the same Thuban layout; the ninth is yours.") {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SchemeCardModel.cards(for: app.themeSelection)) { card in
                        SchemeCard(card: card, isSelected: card.id == app.themeSelection.schemeId) {
                            if card.id == ThubanScheme.customId {
                                isEditingCustom = true
                            } else {
                                app.selectScheme(id: card.id)
                            }
                        }
                    }
                }
            }

            SettingsGroup("Preview", caption: "How the selected scheme reads in \(theme.isDark ? "dark" : "light") mode.") {
                ThemePreviewCard()
            }
        }
        .sheet(isPresented: $isEditingCustom) {
            CustomSchemeSheet(initial: app.themeSelection.custom ?? SchemePresets.default.asCustom()) { scheme in
                app.setCustomScheme(scheme)
            }
            .environment(\.thubanTheme, app.theme)
        }
    }

    private var modeCaption: String {
        switch app.themeSelection.mode {
        case .auto: return "Follows macOS — currently \(app.systemIsDark ? "dark" : "light")."
        case .light: return "Always light, whatever macOS is set to."
        case .dark: return "Always dark, whatever macOS is set to."
        }
    }
}

// MARK: - Scheme card

/// Label + four color dots + a split light|dark ground swatch (each half with a small panel rectangle inside).
/// Selected: accent ring and tint. The default scheme carries a "Default" tag.
struct SchemeCard: View {
    @Environment(\.thubanTheme) private var theme
    var card: SchemeCardModel
    var isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    private var isCustom: Bool { card.id == ThubanScheme.customId }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(card.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? theme.brassInkColor : theme.inkColor)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if card.isDefault {
                        Chip("Default", kind: isSelected ? .accent : .neutral)
                    } else if isCustom && isSelected {
                        Chip("In use", kind: .accent)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(Array(card.dots.enumerated()), id: \.offset) { _, hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
                    }
                    Spacer(minLength: 0)
                    if isCustom {
                        Text("Edit")
                            .font(ThubanFont.small)
                            .foregroundStyle(theme.brassInkColor)
                    }
                }
                SplitGroundSwatch(lightBg: card.lightBg, lightPanel: card.lightPanel, darkBg: card.darkBg, darkPanel: card.darkPanel)
                    .frame(height: 36)
            }
            .padding(12)
            .background(
                isSelected ? theme.accentTintColor : (hovering ? theme.panel2Color : theme.panelColor),
                in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? theme.accentColor : theme.lineColor, lineWidth: isSelected ? 1.5 : ThubanMetrics.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(isCustom ? "Custom scheme, edit" : "\(card.label) scheme")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Light ground on the left, dark ground on the right, each with a small panel rectangle inside.
struct SplitGroundSwatch: View {
    @Environment(\.thubanTheme) private var theme
    var lightBg: String
    var lightPanel: String
    var darkBg: String
    var darkPanel: String

    var body: some View {
        HStack(spacing: 0) {
            half(bg: lightBg, panel: lightPanel)
            half(bg: darkBg, panel: darkPanel)
        }
        .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous)
                .strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline)
        )
        .accessibilityHidden(true)
    }

    private func half(bg: String, panel: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(hex: bg)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(hex: panel))
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Preview card

/// A miniature Desk: title bar with the area pills, three event blocks in the calendar roles, a mail row with the
/// unread dot, and the Today chips and buttons — everything drawn from the resolved theme.
struct ThemePreviewCard: View {
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AppArtView(size: 16, theme: theme)
                Text("Thuban Desk").font(ThubanFont.display(13)).foregroundStyle(theme.inkColor)
                    .padding(.trailing, 10)
                pill(.calendar, "Calendar", active: false)
                pill(.mail, "Mail", active: false, badge: "4")
                pill(.today, "Today", active: true)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Circle().fill(theme.signalColor).frame(width: 6, height: 6)
                    Text("2 accounts synced")
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(theme.inkDimColor)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(theme.panelColor)
            .thubanHairline(.bottom, color: theme.lineColor)

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 6) {
                    event("STAT 2122 · Statistics", "2:30 – 3:45 PM", .accent)
                    event("Gym · UREC", "7:00 – 8:00 AM", .pos)
                    event("Study group · MATH 2210", "7:00 – 8:30 PM", .signal)
                    event("Dinner with Mom", "5:00 – 7:00 PM", .neg)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle().fill(theme.accentColor).frame(width: 7, height: 7)
                        Text("Maya Chen").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.inkColor)
                        Spacer(minLength: 0)
                        Text("48 min ago").font(.system(size: 11.5)).foregroundStyle(theme.inkDimColor)
                    }
                    Text("Still on for 7 in Atkins 244?")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.inkColor)
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) { Rectangle().fill(theme.accentColor).frame(width: 2) }
                    HStack(spacing: 6) {
                        Chip("Now · 65 min left", kind: .signal)
                        Chip("Not answered", kind: .neg)
                    }
                    HStack(spacing: 8) {
                        Button("Reply") {}.buttonStyle(PrimaryButtonStyle(height: 28))
                        Button("Open thread") {}.buttonStyle(SecondaryButtonStyle(height: 28))
                    }
                    .allowsHitTesting(false)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
            }
            .padding(14)
        }
        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Theme preview")
    }

    private func pill(_ icon: IconName, _ name: String, active: Bool, badge: String? = nil) -> some View {
        HStack(spacing: 5) {
            Icon(icon, size: 12)
            Text(name)
            if let badge {
                Text(badge).font(ThubanFont.mono(10, weight: .semibold)).foregroundStyle(theme.brassInkColor)
                    .padding(.horizontal, 4)
                    .background(theme.accentTintColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(active ? theme.inkColor : theme.inkDimColor)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(active ? theme.panel2Color : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(active ? theme.line2Color : .clear, lineWidth: ThubanMetrics.hairline))
    }

    private func event(_ title: String, _ time: String, _ tint: CalendarTint) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(theme.color(for: tint)).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.inkColor).lineLimit(1)
                Text(time).font(.system(size: 11)).foregroundStyle(theme.textColor(for: tint))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(theme.softColor(for: tint), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }
}
