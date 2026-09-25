import Foundation
import ThubanDeskCore

/// `ColorScheme` would collide with SwiftUI’s.
typealias ThubanScheme = ThubanDeskCore.ColorScheme

/// The title bar's destinations. Calendar / Mail / Today are the pill tabs; Settings is the right-hand link and
/// replaces the content area (design: Settings · Accounts keeps the title bar).
enum AppArea: String, CaseIterable, Identifiable {
    case calendar, mail, today, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: return "Calendar"
        case .mail: return "Mail"
        case .today: return "Today"
        case .settings: return "Settings"
        }
    }

    var icon: IconName {
        switch self {
        case .calendar: return .calendar
        case .mail: return .mail
        case .today: return .today
        case .settings: return .settings
        }
    }

    /// The three pill tabs, in order (⌘1 ⌘2 ⌘3).
    static let tabs: [AppArea] = [.calendar, .mail, .today]

    init(_ area: DeskArea) {
        switch area {
        case .calendar: self = .calendar
        case .mail: self = .mail
        case .today: self = .today
        }
    }

    var deskArea: DeskArea? {
        switch self {
        case .calendar: return .calendar
        case .mail: return .mail
        case .today: return .today
        case .settings: return nil
        }
    }
}

/// Settings navigation (design: Accounts, Calendar, Mail, Filters, Notifications, Appearance, About).
enum SettingsPane: String, CaseIterable, Identifiable {
    case accounts = "Accounts"
    case calendar = "Calendar"
    case mail = "Mail"
    case filters = "Filters"
    case notifications = "Notifications"
    case appearance = "Appearance"
    case about = "About"

    var id: String { rawValue }

    var icon: IconName {
        switch self {
        case .accounts: return .account
        case .calendar: return .calendar
        case .mail: return .mail
        case .filters: return .filter
        case .notifications: return .bell
        case .appearance: return .appearance
        case .about: return .info
        }
    }

    var caption: String {
        switch self {
        case .accounts: return "Each Google account signs in once for both Calendar and Mail. The earliest linked account is your primary."
        case .calendar: return "Which calendars show, their colors, and where new events go."
        case .mail: return "Sending account, images, and how mail is shown."
        case .filters: return "Gmail filters for each account."
        case .notifications: return "Reminders for events and new mail."
        case .appearance: return "Mode, color scheme and text size. Colors follow the scheme on every screen."
        case .about: return "Thuban Desk and how it treats your accounts."
        }
    }
}
