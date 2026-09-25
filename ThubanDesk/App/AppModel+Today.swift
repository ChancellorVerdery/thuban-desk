import Foundation
import Observation
import ThubanDeskCore

/// Cross-area requests Today and Settings make of the other areas (owned by the Today + Settings engineer).
/// - Mail/Compose: when Mail appears (or while shown), `DeskIntents.shared.takeReply()` → open the reply composer
///   for that thread (from the account it arrived in). The thread is already open in the reader.
/// - "Compose" and "New event" switch area and then bump `app.newItemRequest` — exactly ⌘N in that area.
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
        Task { @MainActor in await mail.open(key) }
    }

    /// Today → Open thread: Mail with the thread in the reader.
    func openThread(_ key: ThreadKey) {
        select(.mail)
        Task { @MainActor in await mail.open(key) }
    }

    /// Today → Compose (⌘N in Mail).
    func requestCompose() {
        select(.mail)
        bumpNewItemRequestSoon()
    }

    /// Today → New event (⌘N in Calendar).
    func requestNewEvent() {
        select(.calendar)
        bumpNewItemRequestSoon()
    }

    /// Settings → Accounts / onboarding: the step-by-step Google Cloud setup.
    func showSetupGuide() {
        DeskIntents.shared.showSetupGuide = true
    }

    /// After the area switch has rendered, so an `onChange(of: newItemRequest)` in the new area sees it.
    private func bumpNewItemRequestSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            newItemRequest += 1
        }
    }
}
