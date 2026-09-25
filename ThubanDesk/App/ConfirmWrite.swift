import Foundation
import ThubanDeskCore

/// Proof that the user pressed the action button in a `ConfirmWriteSheet`. The `fileprivate init` is reachable
/// only through `ConfirmRequest.run()`, which only the sheet calls — so APIs that must never run unconfirmed
/// (sending mail, deleting events, deleting mail forever, emptying Trash, signing out) take a `Confirmed`.
/// Never call `run()` from anywhere else (tests and smoke included).
struct Confirmed: Sendable {
    fileprivate init() {}
}

/// A pending confirmation shown by the shell as a sheet (`app.confirm(_:)`).
struct ConfirmRequest: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var actionLabel: String
    /// Draws the action in the loss colour (delete forever, empty trash, delete event).
    var destructive: Bool = false
    /// Label while `perform` runs ("Sending…").
    var workingLabel: String = "Working…"
    /// Runs after the user confirms. Throwing keeps the sheet open with the error.
    var perform: @MainActor (Confirmed) async throws -> Void
}

extension ConfirmRequest {
    /// Called only by `ConfirmWriteSheet` when the user presses the action button.
    @MainActor
    func run() async throws {
        try await perform(Confirmed())
    }
}
