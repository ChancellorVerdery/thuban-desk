import Foundation

/// "Now" for the app. `THUBAN_DESK_NOW=2026-09-24T14:40:00-04:00` pins it (smoke screenshots match the design);
/// otherwise the real time.
public enum DeskClock {
    public static let variable = "THUBAN_DESK_NOW"

    /// Set by tests.
    nonisolated(unsafe) public static var override: Date?

    public static var pinned: Date? {
        if let override { return override }
        guard let raw = ProcessInfo.processInfo.environment[variable], !raw.isEmpty else { return nil }
        return RFC3339.date(from: raw)
    }

    public static func now() -> Date {
        guard let pinned else { return Date() }
        return pinned
    }
}

/// Fixture mode (`THUBAN_DESK_FIXTURES=1`): the app talks to the in-process fake Google (`FixtureGoogle`) seeded
/// with `SampleData`, never to the network, and sending is disabled.
public enum FixtureMode {
    public static let variable = "THUBAN_DESK_FIXTURES"
    public static var isEnabled: Bool { ProcessInfo.processInfo.environment[variable] == "1" }
}
