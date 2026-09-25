import Foundation
import Observation
import ThubanDeskCore

/// Cross-area requests Today and Settings make of the other areas (owned by the Today + Settings engineer).
/// - Reply: `requestReply(to:)` opens the thread and then the reply composer (from the account it arrived in).
/// - "Compose" and "New event" switch area and open the composer / event editor directly (what ⌘N does there).
@MainActor
@Observable
final class DeskIntents {
    static let shared = DeskIntents()

    /// Reply to this thread (Today → "Reply").
    var pendingReply: ThreadKey?
    /// The setup guide sheet (Settings → Accounts → "Setup guide", onboarding, smoke).
    var showSetupGuide = false
    /// Smoke only: Settings shows the first-run onboarding page (normally seen only with no linked account).
    var previewOnboarding = false

    func takeReply() -> ThreadKey? {
        defer { pendingReply = nil }
        return pendingReply
    }
}

extension AppModel {
    /// Today → Reply: switch to Mail with the thread open and ask Compose for a reply.
    func requestReply(to key: ThreadKey) {
        DeskIntents.shared.pendingReply = key
        select(.mail)
        Task { @MainActor in
            await mail.open(key)
            // Integration: open the reply composer (from the account the thread arrived in) once the thread is loaded.
            guard DeskIntents.shared.takeReply() == key, mail.compose == nil,
                  let thread = try? await mail.thread(key), let last = thread.messages.last(where: { !$0.isDraft }) ?? thread.messages.last
            else { return }
            ComposeModel.openReply(to: last, in: key, all: false, app: self)
        }
    }

    /// Today → Open thread: Mail with the thread in the reader.
    func openThread(_ key: ThreadKey) {
        select(.mail)
        Task { @MainActor in await mail.open(key) }
    }

    /// Today → Compose (⌘N in Mail).
    func requestCompose() {
        select(.mail)
        if mail.compose == nil { ComposeModel.openNew(app: self) }
    }

    /// Today → New event (⌘N in Calendar).
    func requestNewEvent() {
        select(.calendar)
        calendar.ui.newEvent(on: calendar.ui.today)
    }

    /// Settings → Accounts / onboarding: the step-by-step Google Cloud setup.
    func showSetupGuide() {
        DeskIntents.shared.showSetupGuide = true
    }
}
