import Foundation

/// The editor's Alert row (iOS): the calendar's default reminders, no reminder, or one pop-up N minutes before.
/// Maps to and from Google's `reminders` ({useDefault, overrides}).
public enum EventAlert: Hashable, Sendable {
    case calendarDefault
    case none
    case minutes(Int)

    /// The choices the Alert menu offers.
    public static let presets: [EventAlert] = [.calendarDefault, .none, .minutes(0), .minutes(5), .minutes(10), .minutes(15),
                                               .minutes(30), .minutes(60), .minutes(120), .minutes(1440)]

    /// Reads an event's reminders: default → `.calendarDefault`; no overrides → `.none`; else the earliest pop-up.
    public init(_ reminders: EventReminders?) {
        guard let reminders, !reminders.useDefault else { self = .calendarDefault; return }
        let popups = (reminders.overrides ?? []).filter { $0.method == "popup" }
        let chosen = popups.isEmpty ? (reminders.overrides ?? []) : popups
        if let largest = chosen.map(\.minutes).max() { self = .minutes(largest) } else { self = .none }
    }

    public var reminders: EventReminders {
        switch self {
        case .calendarDefault: return EventReminders(useDefault: true)
        case .none: return EventReminders(useDefault: false, overrides: [])
        case .minutes(let n): return EventReminders(useDefault: false, overrides: [ReminderOverride(method: "popup", minutes: max(0, n))])
        }
    }

    /// "30 min before", "1 hour before", "2 hours before", "1 day before", "At start", "None", "Calendar default".
    public var label: String {
        switch self {
        case .calendarDefault: return "Calendar default"
        case .none: return "None"
        case .minutes(let n):
            if n <= 0 { return "At start" }
            if n % 1440 == 0 { return n == 1440 ? "1 day before" : "\(n / 1440) days before" }
            if n % 60 == 0 { return n == 60 ? "1 hour before" : "\(n / 60) hours before" }
            return "\(n) min before"
        }
    }
}
