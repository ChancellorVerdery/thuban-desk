import Foundation

public enum TextSize: String, Codable, CaseIterable, Sendable {
    case compact, regular, large, extraLarge
    public var label: String {
        switch self {
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .large: return "Large"
        case .extraLarge: return "Extra large"
        }
    }
    /// Multiplier applied to body sizes.
    public var scale: Double {
        switch self {
        case .compact: return 0.92
        case .regular: return 1
        case .large: return 1.12
        case .extraLarge: return 1.25
        }
    }
}

/// The three top-level areas (title-bar pill tabs).
public enum DeskArea: String, Codable, CaseIterable, Sendable {
    case calendar, mail, today
    public var label: String {
        switch self {
        case .calendar: return "Calendar"
        case .mail: return "Mail"
        case .today: return "Today"
        }
    }
}

public enum CalendarViewMode: String, Codable, CaseIterable, Sendable {
    case day, week, month
    public var label: String { rawValue.capitalized }
}

/// A calendar across accounts: "account|calendarId".
public struct CalendarKey: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public var account: String
    public var calendarID: String

    public init(account: String, calendarID: String) {
        self.account = account.lowercased()
        self.calendarID = calendarID
    }

    public var description: String { "\(account)|\(calendarID)" }
    public static func < (a: CalendarKey, b: CalendarKey) -> Bool { a.description < b.description }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let bar = raw.firstIndex(of: "|") else { throw ThubanError.decoding("Bad calendar key \(raw)") }
        self.init(account: String(raw[..<bar]), calendarID: String(raw[raw.index(after: bar)...]))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

/// A thread across accounts.
public struct ThreadKey: Codable, Hashable, Sendable, CustomStringConvertible {
    public var account: String
    public var threadID: String

    public init(account: String, threadID: String) {
        self.account = account.lowercased()
        self.threadID = threadID
    }

    public var description: String { "\(account)|\(threadID)" }
}

/// Everything persisted in `settings.json` (local preferences; nothing here is sent to Google).
/// Decoding tolerates missing keys (each has a default).
public struct AppSettings: Codable, Equatable, Sendable {
    public var theme: ThemeSelection = .default
    public var textSize: TextSize = .regular
    public var reduceMotion: Bool = false
    public var dyslexiaFont: Bool = false
    /// Changes to Google (create/edit/delete events, mail actions, send) are allowed. Each irreversible one still confirms.
    public var writesEnabled: Bool = true
    public var lastArea: DeskArea = .calendar
    public var calendarViewMode: CalendarViewMode = .week
    /// Calendars the user unticked (local only; Google's own `selected` flag is untouched).
    public var hiddenCalendars: Set<CalendarKey> = []
    /// Per-calendar colour override (a `CalendarTint` raw value); otherwise derived from Google's colour.
    public var calendarTints: [String: CalendarTint] = [:]
    public var weekStartsOnMonday: Bool = false
    public var showDeclinedEvents: Bool = false
    /// Where new events go (nil = primary account's primary calendar).
    public var defaultCalendar: CalendarKey?
    /// Account new mail is sent from (nil = primary). Replies always use the account the thread arrived in.
    public var defaultSendAccount: String?
    /// Mail list width in points (the list | reader split).
    public var mailListWidth: Double = 420
    /// Pinned threads per account (local only).
    public var pins: [String: [String]] = [:]
    /// Remote images in mail load without asking (default off; trackers are blocked either way).
    public var loadRemoteImages: Bool = false
    /// The last mail folder (a `MailFolder.storageKey`).
    public var lastMailFolder: String?
    /// Minutes between background syncs.
    public var refreshMinutes: Int = 5

    public init() {}

    enum CodingKeys: String, CodingKey {
        case theme, textSize, reduceMotion, dyslexiaFont, writesEnabled, lastArea, calendarViewMode, hiddenCalendars, calendarTints,
             weekStartsOnMonday, showDeclinedEvents, defaultCalendar, defaultSendAccount, mailListWidth, pins, loadRemoteImages,
             lastMailFolder, refreshMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        theme = try c.decodeIfPresent(ThemeSelection.self, forKey: .theme) ?? d.theme
        textSize = (try? c.decodeIfPresent(TextSize.self, forKey: .textSize)) ?? d.textSize
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? d.reduceMotion
        dyslexiaFont = try c.decodeIfPresent(Bool.self, forKey: .dyslexiaFont) ?? d.dyslexiaFont
        writesEnabled = try c.decodeIfPresent(Bool.self, forKey: .writesEnabled) ?? d.writesEnabled
        lastArea = (try? c.decodeIfPresent(DeskArea.self, forKey: .lastArea)) ?? d.lastArea
        calendarViewMode = (try? c.decodeIfPresent(CalendarViewMode.self, forKey: .calendarViewMode)) ?? d.calendarViewMode
        hiddenCalendars = (try? c.decodeIfPresent(Set<CalendarKey>.self, forKey: .hiddenCalendars)) ?? d.hiddenCalendars
        calendarTints = (try? c.decodeIfPresent([String: CalendarTint].self, forKey: .calendarTints)) ?? d.calendarTints
        weekStartsOnMonday = try c.decodeIfPresent(Bool.self, forKey: .weekStartsOnMonday) ?? d.weekStartsOnMonday
        showDeclinedEvents = try c.decodeIfPresent(Bool.self, forKey: .showDeclinedEvents) ?? d.showDeclinedEvents
        defaultCalendar = try? c.decodeIfPresent(CalendarKey.self, forKey: .defaultCalendar)
        defaultSendAccount = try c.decodeIfPresent(String.self, forKey: .defaultSendAccount)
        mailListWidth = try c.decodeIfPresent(Double.self, forKey: .mailListWidth) ?? d.mailListWidth
        pins = try c.decodeIfPresent([String: [String]].self, forKey: .pins) ?? d.pins
        loadRemoteImages = try c.decodeIfPresent(Bool.self, forKey: .loadRemoteImages) ?? d.loadRemoteImages
        lastMailFolder = try c.decodeIfPresent(String.self, forKey: .lastMailFolder)
        refreshMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? d.refreshMinutes
    }

    public func isPinned(_ key: ThreadKey) -> Bool { pins[key.account]?.contains(key.threadID) ?? false }

    public mutating func setPinned(_ pinned: Bool, _ key: ThreadKey) {
        var list = pins[key.account] ?? []
        list.removeAll { $0 == key.threadID }
        if pinned { list.insert(key.threadID, at: 0) }
        pins[key.account] = list.isEmpty ? nil : list
    }

    public func isHidden(_ calendar: CalendarKey) -> Bool { hiddenCalendars.contains(calendar) }
}

public enum SettingsStore {
    public static func load() -> AppSettings {
        (try? JSONFile.read(AppSettings.self, from: AppPaths.settingsFile)) ?? AppSettings()
    }

    public static func save(_ settings: AppSettings) throws {
        try AppPaths.ensureDirectories()
        try JSONFile.write(settings, to: AppPaths.settingsFile)
    }
}
