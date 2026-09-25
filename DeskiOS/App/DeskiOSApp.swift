import SwiftUI
import UIKit
import ThubanDeskCore

@main
struct DeskiOSApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task {
                    await app.load()
                    LocalNotifications.shared.start(app: app)
                }
        }
    }
}

/// Picks the iPhone tab layout or the iPad split view, applies the theme, and hosts the app-wide sheets.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var router = PhoneRouter.shared

    var body: some View {
        @Bindable var ui = app.calendar.ui
        Group {
            if sizeClass == .regular {
                PadRootView()
            } else {
                PhoneRootView()
            }
        }
        .environment(router)
        .environment(\.thubanTheme, app.theme)
        .tint(app.theme.brassInkColor)
        .preferredColorScheme(preferredScheme)
        .onAppear { reportSystemAppearance() }
        .onChange(of: colorScheme) { _, _ in reportSystemAppearance() }
        .onChange(of: app.area) { _, area in follow(area) }
        .onChange(of: router.tab) { _, tab in
            // Keep the shared model's area in step (DeskSearch skips its Gmail query while Mail is showing).
            if app.area != Self.area(for: tab) { app.area = Self.area(for: tab) }
        }
        .sheet(item: $ui.editor) { _ in
            EventEditorSheet()
                .environment(app)
                .environment(router)
                .environment(\.thubanTheme, app.theme)
                .preferredColorScheme(preferredScheme)
        }
        .sheet(item: $router.compose) { model in
            ComposeSheet(model: model)
                .environment(app)
                .environment(router)
                .environment(\.thubanTheme, app.theme)
                .preferredColorScheme(preferredScheme)
        }
        .sheet(isPresented: $router.showCalendars) {
            CalendarsSheet()
                .environment(app)
                .environment(\.thubanTheme, app.theme)
                .preferredColorScheme(preferredScheme)
        }
        .sheet(item: labelTargets) { targets in
            LabelPickerSheet(targets: targets.keys)
                .environment(app)
                .environment(router)
                .environment(\.thubanTheme, app.theme)
                .preferredColorScheme(preferredScheme)
        }
        .confirmHost(active: ui.editor == nil && router.compose == nil)
    }

    private var preferredScheme: SwiftUI.ColorScheme? {
        switch app.themeSelection.mode {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private func reportSystemAppearance() {
        guard app.themeSelection.mode == .auto else { return }
        app.setSystemIsDark(colorScheme == .dark)
    }

    static func area(for tab: PhoneTab) -> AppArea {
        switch tab {
        case .today, .search: return .today
        case .calendar: return .calendar
        case .mail: return .mail
        }
    }

    /// Shared helpers (e.g. `openInvitationEmail`) select an area; follow them with the tab.
    private func follow(_ area: AppArea) {
        guard Self.area(for: router.tab) != area else { return }
        switch area {
        case .calendar: router.tab = .calendar
        case .mail: router.tab = .mail
        case .today: router.tab = .today
        case .settings: router.tab = .today; router.todayPath = [.settings]
        }
    }

    private var labelTargets: Binding<LabelTargets?> {
        Binding(get: { router.labelTargets.map(LabelTargets.init) }, set: { router.labelTargets = $0?.keys })
    }
}

struct LabelTargets: Identifiable {
    var keys: [ThreadKey]
    var id: String { keys.map(\.description).joined(separator: ",") }
}

// MARK: - iPhone

/// Four tabs, each with its own navigation stack, over a custom tab bar in the Thuban look (panel, top hairline,
/// brass selection). The bar steps aside for a thread's toolbar and for Mail's select mode.
struct PhoneRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch router.tab {
                case .today: TodayTab()
                case .calendar: CalendarTab()
                case .mail: MailTab()
                case .search: SearchTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !router.hidesTabBar {
                PhoneTabBar()
            }
        }
        .background(theme.bgColor.ignoresSafeArea())
        .overlay(alignment: .top) { ToastOverlay() }
    }
}

struct PhoneTabBar: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PhoneTab.allCases) { tab in
                let selected = router.tab == tab
                Button {
                    if router.tab == tab { popToRoot(tab) } else { router.tab = tab }
                } label: {
                    VStack(spacing: 3) {
                        Icon(tab.icon, size: 24)
                            .overlay(alignment: .topTrailing) {
                                if tab == .mail, app.mail.unreadCount > 0 { badge(app.mail.unreadCount) }
                            }
                        Text(tab.title).font(PhoneFont.tabLabel)
                    }
                    .foregroundStyle(selected ? theme.brassInkColor : theme.inkFaintColor)
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab == .mail && app.mail.unreadCount > 0 ? "Mail, \(app.mail.unreadCount) unread" : tab.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 8)
        .background(theme.panelColor.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(theme.lineColor).frame(height: 1) }
    }

    private func badge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(theme.onAccentInk)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(theme.accentColor, in: Capsule())
            .offset(x: 12, y: -4)
    }

    private func popToRoot(_ tab: PhoneTab) {
        switch tab {
        case .today: router.todayPath = []
        case .mail: router.mailSelecting = false; router.mailPath = [.mailbox(router.currentMailScope)]
        case .calendar: app.calendar.ui.goToday()
        case .search: break
        }
    }
}

/// A short message at the top (a reversible action failed, …); taps dismiss it.
struct ToastOverlay: View {
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        if let toast = router.toast {
            PhoneBanner(text: toast, isError: true) { router.toast = nil }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if router.toast == toast { router.toast = nil }
                }
        }
    }
}
