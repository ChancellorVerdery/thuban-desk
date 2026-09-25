import Foundation
import Observation
import ThubanDeskCore

/// The four tabs (design: Today, Calendar, Mail, Search; Settings opens from the avatar on Today).
enum PhoneTab: String, CaseIterable, Identifiable {
    case today, calendar, mail, search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .calendar: return "Calendar"
        case .mail: return "Mail"
        case .search: return "Search"
        }
    }

    var icon: IconName {
        switch self {
        case .today: return .today
        case .calendar: return .calendar
        case .mail: return .mail
        case .search: return .search
        }
    }
}

/// Calendar tab views (design: Day / 3 Days / Month).
enum PhoneCalendarMode: String, CaseIterable, Identifiable {
    case day, threeDays, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .threeDays: return "3 Days"
        case .month: return "Month"
        }
    }

    var dayCount: Int {
        switch self {
        case .day: return 1
        case .threeDays: return 3
        case .month: return 1
        }
    }
}

enum TodayRoute: Hashable {
    case settings
    case account(String)
}

enum MailRoute: Hashable {
    case mailbox(MailScope)
    case thread(ThreadKey)
}

/// iOS navigation state: selected tab, each tab's stack, sheets, and Mail's select mode. Kept outside the views so
/// smoke scenes (and cross-tab links) can put the app in any state.
@MainActor
@Observable
final class PhoneRouter {
    static let shared = PhoneRouter()

    var tab: PhoneTab = .today
    var todayPath: [TodayRoute] = []
    /// Mail opens on All inboxes with Mailboxes one level up (like Mail on iPhone).
    var mailPath: [MailRoute] = [.mailbox(MailScope())]
    var searchText = ""

    var calendarMode: PhoneCalendarMode = PhoneRouter.storedMode() {
        didSet { UserDefaults.standard.set(calendarMode.rawValue, forKey: Self.modeKey) }
    }

    /// Mail list multi-select (bottom action bar replaces the tab bar).
    var mailSelecting = false
    /// Reply / compose sheet.
    var compose: PhoneComposeModel?
    /// Calendars sheet (visibility toggles).
    var showCalendars = false
    /// Label picker sheet for these threads.
    var labelTargets: [ThreadKey]?
    /// Banner message (reversible action failed, sign-in problem …).
    var toast: String?

    // MARK: iPad

    /// iPad sidebar selection.
    var padSection: PadSection = .mail(MailScope())
    var padThread: ThreadKey?

    enum PadSection: Hashable {
        case today, calendar, mail(MailScope), search, settings
    }

    /// The thread open on top of the Mail stack (iPhone).
    var openThread: ThreadKey? {
        if case .thread(let key) = mailPath.last { return key }
        return nil
    }

    /// The tab bar hides while a thread (its own bottom toolbar) or Mail's select mode is showing.
    var hidesTabBar: Bool {
        tab == .mail && (mailSelecting || openThread != nil)
    }

    // MARK: Actions

    func showThread(_ key: ThreadKey) {
        tab = .mail
        mailSelecting = false
        if case .thread = mailPath.last { mailPath.removeLast() }
        if mailPath.isEmpty { mailPath = [.mailbox(MailScope())] }
        mailPath.append(.thread(key))
        padSection = .mail(currentMailScope)
        padThread = key
    }

    var currentMailScope: MailScope {
        for route in mailPath.reversed() { if case .mailbox(let scope) = route { return scope } }
        return MailScope()
    }

    func showMailbox(_ scope: MailScope) {
        tab = .mail
        mailSelecting = false
        mailPath = [.mailbox(scope)]
    }

    private static let modeKey = "phone.calendarMode"
    private static func storedMode() -> PhoneCalendarMode {
        UserDefaults.standard.string(forKey: modeKey).flatMap(PhoneCalendarMode.init(rawValue:)) ?? .day
    }
}
