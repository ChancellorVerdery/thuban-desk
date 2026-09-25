import SwiftUI
import ThubanDeskCore

/// iPad (board "iPad · Mail split view"): a sidebar with the app mark, Today, Calendar, the mailboxes, accounts and
/// labels, and Settings + sync status at the bottom; Mail shows the thread list beside the open thread. Narrower
/// windows (portrait, Split View) slide the sidebar in over the content.
struct PadRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    @State private var sidebarOpen = false

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 1000
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    if wide {
                        PadSidebar { }
                            .frame(width: 260)
                        Rectangle().fill(theme.lineColor).frame(width: 1).ignoresSafeArea()
                    }
                    detail(wide: wide, width: geo.size.width)
                }
                if !wide, sidebarOpen {
                    theme.scrimColor.ignoresSafeArea().onTapGesture { sidebarOpen = false }
                    PadSidebar { sidebarOpen = false }
                        .frame(width: 280)
                        .background(theme.panel2Color.ignoresSafeArea())
                        .transition(.move(edge: .leading))
                }
            }
            .animation(.easeOut(duration: 0.2), value: sidebarOpen)
            .overlay(alignment: .topLeading) {
                if !wide, !sidebarOpen {
                    NavIconButton(.listDots, label: "Show sidebar") { sidebarOpen = true }
                        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.leading, 8)
                        .padding(.top, 2)
                }
            }
        }
        .background(theme.bgColor.ignoresSafeArea())
        .overlay(alignment: .top) { ToastOverlay() }
    }

    @ViewBuilder private func detail(wide: Bool, width: CGFloat) -> some View {
        switch router.padSection {
        case .today:
            NavigationStack { TodayScreen(showsAccountButton: false) }
                .padding(.leading, wide ? 0 : 52)
        case .calendar:
            NavigationStack { CalendarScreen() }
                .padding(.leading, wide ? 0 : 52)
        case .search:
            NavigationStack { SearchScreen() }
                .padding(.leading, wide ? 0 : 52)
        case .settings:
            @Bindable var router = router
            NavigationStack(path: $router.todayPath) {
                SettingsScreen(showsBack: false)
                    .navigationDestination(for: TodayRoute.self) { route in
                        switch route {
                        case .settings: SettingsScreen(showsBack: false)
                        case .account(let id): AccountScreen(accountID: id)
                        }
                    }
            }
            .padding(.leading, wide ? 0 : 52)
        case .mail(let scope):
            HStack(spacing: 0) {
                NavigationStack {
                    InboxScreen(scope: scope, onOpen: { key in
                        router.padThread = key
                        Task { await app.mail.open(key) }
                    }, showsBack: false)
                    .padding(.leading, wide ? 0 : 44)
                }
                .frame(width: wide ? 380 : min(360, width * 0.45))
                .background(theme.panelColor)
                Rectangle().fill(theme.lineColor).frame(width: 1).ignoresSafeArea()
                Group {
                    if let key = router.padThread {
                        ThreadScreen(key: key, embedded: true).id(key)
                    } else {
                        PhoneEmptyState(icon: .mail, text: "Choose a conversation.")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .onChange(of: router.mailSelecting) { _, selecting in if selecting { router.padThread = nil } }
        }
    }
}

struct PadSidebar: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    var didSelect: () -> Void

    var body: some View {
        let mail = app.mail
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppArtView(size: 26, theme: app.theme, ground: theme.panel2Color)
                Text("Thuban Desk").font(PhoneFont.display(.title3)).foregroundStyle(theme.inkColor)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 14)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    item(.today, "Today", section: .today)
                    item(.calendar, "Calendar", section: .calendar)
                    item(.search, "Search", section: .search)
                    header("Mail")
                    let folders: [MailFolder] = [.inbox, .pinned, .starred, .drafts, .sent]
                    ForEach(folders, id: \.self) { folder in
                        let scope = MailScope(folder: folder)
                        item(icon(folder), scope.title, section: .mail(scope), count: mail.folderCount(folder))
                    }
                    if !app.accounts.isEmpty {
                        header("Accounts")
                        ForEach(app.accounts) { account in
                            let scope = MailScope(folder: .inbox, account: account.id)
                            row(selected: router.padSection == .mail(scope), count: mail.unreadInbox(account: account.id)) {
                                Circle().fill(theme.color(for: mail.accountTint(account.id))).frame(width: 8, height: 8).frame(width: 20)
                                Text(account.domain)
                            } action: { select(.mail(scope)) }
                        }
                    }
                    if !mail.mergedLabels.isEmpty {
                        header("Labels")
                        ForEach(mail.mergedLabels) { label in
                            let scope = MailScope(folder: .label(label.name))
                            item(.label, label.name, section: .mail(scope), count: label.unread > 0 ? label.unread : nil)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button { select(.settings) } label: {
                    HStack(spacing: 10) {
                        Icon(.settings, size: 20)
                        Text("Settings").font(PhoneFont.body)
                    }
                    .foregroundStyle(router.padSection == .settings ? theme.brassInkColor : theme.inkDimColor)
                    .frame(minHeight: PhoneMetrics.hit)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(app.syncErrors.isEmpty ? theme.signalColor : theme.negColor).frame(width: 6, height: 6)
                    Text(app.lastSync.map { "Synced \(CalendarText.clock($0, zone: app.zone, suffix: false))" } ?? app.syncSummary.text)
                        .font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 12)
        }
        .background(theme.panel2Color.ignoresSafeArea())
    }

    private func select(_ section: PhoneRouter.PadSection) {
        router.padSection = section
        router.mailSelecting = false
        switch section {
        case .today: router.tab = .today
        case .calendar: router.tab = .calendar
        case .search: router.tab = .search
        case .settings: router.todayPath = []
        case .mail(let scope):
            router.tab = .mail
            router.mailPath = [.mailbox(scope)]
            if router.padThread.map({ key in app.mail.threads.contains { $0.key == key } }) != true { router.padThread = nil }
        }
        didSelect()
    }

    private func header(_ title: String) -> some View {
        Eyebrow(title).padding(.horizontal, 10).padding(.top, 18).padding(.bottom, 6)
    }

    private func item(_ icon: IconName, _ title: String, section: PhoneRouter.PadSection, count: Int? = nil) -> some View {
        row(selected: router.padSection == section, count: count) {
            Icon(icon, size: 20).foregroundStyle(theme.brassInkColor).frame(width: 20)
            Text(title)
        } action: { select(section) }
    }

    private func row<Label: View>(selected: Bool, count: Int?, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                label()
                    .font(selected ? PhoneFont.bodySemibold : PhoneFont.body)
                    .foregroundStyle(theme.inkColor)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)").font(selected ? PhoneFont.footnoteSemibold : PhoneFont.footnote)
                        .foregroundStyle(selected ? theme.brassInkColor : theme.inkDimColor)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 42)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.panelColor)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func icon(_ folder: MailFolder) -> IconName {
        switch folder {
        case .inbox: return .inbox
        case .pinned: return .pin
        case .starred: return .star
        case .drafts: return .drafts
        case .sent: return .sent
        case .archive: return .archive
        case .spam: return .spam
        case .trash: return .trash
        case .label: return .label
        }
    }
}
