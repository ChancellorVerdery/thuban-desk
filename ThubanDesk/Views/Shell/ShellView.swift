import SwiftUI
import ThubanDeskCore

/// The main window: the design's 52 pt title bar, then the selected area. Irreversible actions confirm in a sheet
/// (`app.pendingConfirmation`).
struct ShellView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        let theme = app.theme
        VStack(spacing: 0) {
            TitleBar()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgColor)
        .environment(\.thubanTheme, theme)
        .environment(\.thubanTextScale, app.settings.textSize.scale)
        .ignoresSafeArea()
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .sheet(item: $app.pendingConfirmation) { request in
            ConfirmWriteSheet(request: request) { app.pendingConfirmation = nil }
                .environment(\.thubanTheme, theme)
                .preferredColorScheme(theme.isDark ? .dark : .light)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !app.isLoaded {
            Color.clear
        } else if app.area == .settings {
            SettingsAreaView()
        } else if !app.hasAccounts {
            ConnectPrompt()
        } else {
            switch app.area {
            case .calendar: CalendarAreaView()
            case .mail: MailAreaView()
            case .today: TodayAreaView()
            case .settings: SettingsAreaView()
            }
        }
    }
}

/// Shown in Calendar / Mail / Today until an account is linked: the first-run welcome and setup guide
/// (`Views/Settings/SetupGuide.swift`, Today + Settings engineer).
struct ConnectPrompt: View {
    var body: some View {
        OnboardingView()
    }
}

// MARK: - Title bar

/// Design: [traffic lights] mark + serif "Thuban Desk" | Calendar · Mail (unread badge) · Today pills | search
/// (⌘K) · sync pill · Settings.
struct TitleBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 12) {
            Spacer().frame(width: ThubanMetrics.trafficLightInset - 16)
            HStack(spacing: 9) {
                AppArtView(size: 20, theme: theme)
                Text("Thuban Desk")
                    .font(ThubanFont.display(17))
                    .kerning(-0.17)
                    .foregroundStyle(theme.inkColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Thuban Desk")

            HStack(spacing: 4) {
                ForEach(AppArea.tabs) { area in
                    AreaPill(area: area, isSelected: app.area == area, badge: area == .mail ? app.mail.unreadCount : 0) { app.select(area) }
                }
            }
            .padding(.leading, 22)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sections")

            Spacer(minLength: 8)

            TitleSearchField(text: $app.searchText, focusRequest: app.searchFocusRequest)
                .frame(width: 260)
            SyncPill()
            AreaPill(area: .settings, isSelected: app.area == .settings, badge: 0, horizontalPadding: 12) { app.openSettings(app.settingsPane) }
                .help("Settings (⌘,)")
        }
        .padding(.horizontal, 16)
        .frame(height: ThubanMetrics.titleBarHeight)
        .frame(maxWidth: .infinity)
        .background(theme.panelColor)
        .thubanHairline(.bottom, color: theme.lineColor)
        .gesture(WindowDragGesture())
    }
}

/// A title-bar tab: 34 pt, radius 8, icon 16 + 14 pt semibold label; selected = panel2 fill + line2 border.
struct AreaPill: View {
    @Environment(\.thubanTheme) private var theme
    var area: AppArea
    var isSelected: Bool
    var badge: Int
    var horizontalPadding: CGFloat = 14
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Icon(area.icon, size: 16)
                Text(area.title).font(.system(size: 14, weight: .semibold))
                if badge > 0 {
                    Text(String(badge))
                        .font(ThubanFont.mono(11.5, weight: .semibold))
                        .foregroundStyle(theme.brassInkColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(theme.accentTintColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .accessibilityLabel("\(badge) unread")
                }
            }
            .foregroundStyle(isSelected ? theme.inkColor : theme.inkDimColor)
            .padding(.horizontal, horizontalPadding)
            .frame(height: 34)
            .background(isSelected ? theme.panel2Color : (hovering ? theme.panel2Color.opacity(0.6) : .clear),
                        in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                .strokeBorder(isSelected ? theme.line2Color : .clear, lineWidth: ThubanMetrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(area.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// "Search mail and events  ⌘K" (260 × 30, line2 border).
struct TitleSearchField: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var text: String
    var focusRequest: Int
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Icon(.search, size: 14).foregroundStyle(theme.inkFaintColor)
            TextField("Search mail and events", text: $text)
                .textFieldStyle(.plain)
                .font(ThubanFont.body(13.5))
                .foregroundStyle(theme.inkColor)
                .focused($focused)
                .onChange(of: focusRequest) { _, _ in focused = true }
            if text.isEmpty {
                Text("⌘K").font(ThubanFont.mono(12)).foregroundStyle(theme.inkFaintColor)
            } else {
                Button { text = "" } label: { Icon(.close, size: 12).foregroundStyle(theme.inkDimColor) }
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

/// "● 2 accounts synced" (panel2 pill, signal dot; neg dot when an account needs attention). Click refreshes.
struct SyncPill: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let summary = app.syncSummary
        Button {
            if summary.tone == .problem, app.accounts.contains(where: \.disconnected) { app.openSettings(.accounts) } else { Task { await app.refreshAll() } }
        } label: {
            HStack(spacing: 7) {
                Circle().fill(dotColor(summary.tone)).frame(width: 7, height: 7)
                Text(summary.text).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(theme.inkDimColor)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(app.lastSync.map { "Last synced \(DeskFormat.time($0, zone: app.zone)) — click to refresh (⌘R)" } ?? "Refresh (⌘R)")
        .accessibilityLabel(summary.text)
    }

    private func dotColor(_ tone: AppModel.SyncTone) -> Color {
        switch tone {
        case .ok: return theme.signalColor
        case .busy: return theme.accentColor
        case .problem: return theme.negColor
        case .idle: return theme.inkFaintColor
        }
    }
}
