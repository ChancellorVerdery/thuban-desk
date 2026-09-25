import SwiftUI
import ThubanDeskCore

/// Settings fills the content area under the title bar (design: 272 pt nav with a serif "Settings" title, the pane
/// on the right with a 34 pt serif heading and caption). Panes live in their own files.
struct SettingsAreaView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            SettingsNav()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageTitle(title: app.settingsPane.rawValue, subtitle: app.settingsPane.caption)
                    pane
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 30)
                .frame(maxWidth: 1060, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var pane: some View {
        switch app.settingsPane {
        case .accounts: AccountsSettings()
        case .appearance: AppearanceSettings()
        case .calendar: PlaceholderPane(icon: .calendar, text: "Calendar colors, visibility and the default calendar land here.")
        case .mail: PlaceholderPane(icon: .mail, text: "Sending account, signatures and image loading land here.")
        case .filters: PlaceholderPane(icon: .filter, text: "\(app.mail.activeFilterCount) filters active. Filter management lands here.")
        case .notifications: PlaceholderPane(icon: .bell, text: "Event reminders and new-mail alerts land here.")
        case .about: AboutSettings()
        }
    }
}

private struct SettingsNav: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(ThubanFont.display(26))
                .foregroundStyle(theme.inkColor)
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
                .accessibilityAddTraits(.isHeader)
            ForEach(SettingsPane.allCases) { pane in
                SettingsNavRow(pane: pane, isSelected: app.settingsPane == pane) { app.settingsPane = pane }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 26)
        .frame(width: 272)
        .frame(maxHeight: .infinity)
        .background(theme.panelColor)
        .thubanHairline(.trailing, color: theme.lineColor)
    }
}

private struct SettingsNavRow: View {
    @Environment(\.thubanTheme) private var theme
    var pane: SettingsPane
    var isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(pane.icon, size: 17)
                Text(pane.rawValue).font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.inkColor)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(isSelected ? theme.panel2Color : (hovering ? theme.panel2Color.opacity(0.6) : .clear),
                        in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                .strokeBorder(isSelected ? theme.line2Color : .clear, lineWidth: ThubanMetrics.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Stand-in for panes not built yet.
struct PlaceholderPane: View {
    var icon: IconName
    var text: String

    var body: some View {
        EmptyState(icon: icon, title: "Coming soon", message: text)
            .frame(maxWidth: .infinity, minHeight: 260)
            .thubanPanel()
    }
}

struct AboutSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                AppArtView(size: 44, theme: theme)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thuban Desk").font(ThubanFont.display(22)).foregroundStyle(theme.inkColor)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1")")
                        .font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
                }
            }
            SettingsNote(text: "Your Google tokens stay in a private file on this Mac (credentials.json, readable only by you). Mail and events are cached locally so the app opens instantly. Nothing is sent anywhere except Google.")
            if app.isFixtureMode {
                SettingsNote(text: "Fixture mode: sample data from an in-process fake Google. Nothing reaches the network and sending is disabled.", tone: .negative)
            }
        }
        .thubanPanel(padding: 20)
    }
}
