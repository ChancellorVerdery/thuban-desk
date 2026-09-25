import AppKit
import Foundation
import Observation
import ThubanDeskCore
import UniformTypeIdentifiers

/// One Compose window: the `ComposeDraft` (recipients, subject, body, attachments), the rich-text body, draft
/// autosave (Gmail drafts API, only while Changes are on) and the send path — which always goes through the
/// ConfirmWriteSheet (`app.confirm`) and never runs on its own.
@MainActor
@Observable
final class ComposeModel: Identifiable {
    enum SaveState: Equatable {
        case idle
        case saving
        case saved(Date)
        /// Changes are off: nothing is written to Gmail; the draft lives in this window only.
        case writesOff
        case failed(String)
    }

    let id = UUID()
    var draft: ComposeDraft
    var showCc: Bool
    var showBcc: Bool
    var quoteExpanded = false
    private(set) var saveState: SaveState = .idle
    /// The body the editor starts with (signature, a restored draft, or smoke text).
    let initialBody: NSAttributedString
    /// Bumped when the body should be replaced from outside (not used while typing).
    private(set) var bodyRevision = 0
    private(set) var replacementBody: NSAttributedString?
    let editor = RichTextController()

    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    /// The drafts.create / drafts.update request in flight. Cancelling `autosaveTask` does not stop it, so a send
    /// or another save waits for it (and picks up the draft id it created) instead of racing it.
    @ObservationIgnored private var inflightSave: Task<Void, Never>?
    @ObservationIgnored private var editCount = 0
    @ObservationIgnored private var savedEditCount = 0

    init(app: AppModel, draft: ComposeDraft, body: NSAttributedString) {
        self.app = app
        self.draft = draft
        self.initialBody = body
        showCc = !draft.cc.isEmpty
        showBcc = !draft.bcc.isEmpty
        if !app.settings.writesEnabled { saveState = .writesOff }
    }

    // MARK: Opening

    static func openNew(app: AppModel, to: [EmailAddress] = []) {
        guard let account = app.mail.defaultSendAccount else { return }
        let draft = ComposeDraft(account: account, to: to)
        present(ComposeModel(app: app, draft: draft, body: RichTextFormat.startingBody(signature: app.mail.signature(for: account), theme: app.theme)), app: app)
    }

    /// Reply / reply all — ALWAYS from the account the thread arrived in.
    static func openReply(to message: MailMessage, in key: ThreadKey, all: Bool, app: AppModel) {
        let from = app.mail.fromAddress(for: key.account)
        let draft = ComposeDraft.reply(to: message, account: from, replyAll: all, ownAddresses: app.ownAddresses)
        present(ComposeModel(app: app, draft: draft, body: RichTextFormat.startingBody(signature: app.mail.signature(for: key.account), theme: app.theme)), app: app)
    }

    static func openForward(_ message: MailMessage, in key: ThreadKey, app: AppModel) {
        let from = app.mail.fromAddress(for: key.account)
        let draft = ComposeDraft.forward(message, account: from)
        present(ComposeModel(app: app, draft: draft, body: RichTextFormat.startingBody(signature: app.mail.signature(for: key.account), theme: app.theme)), app: app)
    }

    /// Continues a saved Gmail draft found in a thread.
    static func openDraft(_ message: MailMessage, in thread: MailThread, app: AppModel) {
        let answered = thread.messages.last { !$0.isDraft && $0.date <= message.date && ($0.messageIDHeader.map { message.references.contains($0) } ?? true) }
            ?? thread.messages.last { !$0.isDraft }
        let from = app.mail.fromAddress(for: thread.account)
        var draft: ComposeDraft
        if let answered {
            draft = ComposeDraft.reply(to: answered, account: from, replyAll: false, ownAddresses: app.ownAddresses)
        } else {
            draft = ComposeDraft(account: thread.account)
        }
        draft.to = message.to
        draft.cc = message.cc
        draft.bcc = message.bcc
        draft.subject = message.subject
        let body = RichTextFormat.body(fromDraftText: stripQuote(message.plainBody), theme: app.theme)
        let model = ComposeModel(app: app, draft: draft, body: body)
        present(model, app: app)
        Task { @MainActor in
            model.draft.draftID = await app.mail.draftID(forMessage: message.id, account: thread.account)
        }
    }

    private static func present(_ model: ComposeModel, app: AppModel) {
        if let open = app.mail.compose { open.closeKeepingDraft() }
        app.mail.compose = model
    }

    /// Drops the quoted part of a saved reply ("On … wrote:" and below).
    static func stripQuote(_ text: String) -> String {
        if let range = text.range(of: #"\n\s*On .{4,80} wrote:\s*\n"#, options: .regularExpression) { return String(text[..<range.lowerBound]) }
        return text
    }

    // MARK: Editing

    var fromAddress: EmailAddress? { app?.mail.fromAddress(for: draft.account) }

    /// Called by the editor on every change.
    func bodyChanged(html: String, text: String) {
        guard html != draft.html || text != draft.text else { return }
        draft.html = html
        draft.text = text
        edited()
    }

    /// Recipients / subject / attachments changed.
    func edited() {
        editCount += 1
        scheduleAutosave()
    }

    func setAccount(_ account: String) {
        guard draft.canChangeAccount, account != draft.account else { return }
        // A draft lives in one account's Gmail: move it by discarding the old one.
        if let old = draft.draftID, let app {
            let previous = draft.account
            Task { try? await app.mail.discardDraft(old, account: previous) }
        }
        draft.draftID = nil
        draft.account = account
        edited()
    }

    func addAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Attach"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            draft.attachments.append(OutgoingAttachment(filename: url.lastPathComponent, mimeType: type, data: data))
        }
        edited()
    }

    func removeAttachment(at index: Int) {
        guard draft.attachments.indices.contains(index) else { return }
        draft.attachments.remove(at: index)
        edited()
    }

    var attachmentsTooLarge: Bool { draft.attachments.reduce(0) { $0 + $1.data.count } > ByteSize.gmailLimit }

    // MARK: Drafts

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard let app else { return }
        guard app.settings.writesEnabled else { saveState = .writesOff; return }
        autosaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.saveDraft()
        }
    }

    /// Saves (creates or updates) the Gmail draft. Only while Changes are on; nothing for an empty message.
    func saveDraft() async {
        await waitForPendingSave()
        guard let app else { return }
        guard app.settings.writesEnabled else { saveState = .writesOff; return }
        guard !draft.isEmpty || draft.draftID != nil, let from = fromAddress else { return }
        let count = editCount
        saveState = .saving
        let outgoing = draft.outgoing(from: from, ownAddresses: app.ownAddresses, zone: app.zone)
        let account = draft.account
        let task = Task { @MainActor in
            do {
                let saved = try await app.mail.saveDraft(outgoing, account: account)
                self.draft.draftID = saved.draftID
                self.savedEditCount = count
                self.saveState = .saved(app.now())
            } catch {
                self.saveState = .failed(error.localizedDescription)
            }
        }
        inflightSave = task
        await task.value
        if inflightSave == task { inflightSave = nil }
    }

    /// Waits until no draft save is in flight (so `draft.draftID` is the one Gmail knows).
    func waitForPendingSave() async {
        while let running = inflightSave {
            await running.value
            if inflightSave == running { inflightSave = nil }
        }
    }

    var hasUnsavedChanges: Bool { editCount != savedEditCount }

    // MARK: Closing

    /// Close: keeps the Gmail draft (saving the latest edits first when Changes are on).
    func closeKeepingDraft() {
        autosaveTask?.cancel()
        guard let app else { return }
        if hasUnsavedChanges, app.settings.writesEnabled, !draft.isEmpty {
            let snapshot = self
            Task { await snapshot.saveDraft() }
        }
        if app.mail.compose?.id == id { app.mail.compose = nil }
    }

    /// Discard: deletes the Gmail draft (asks first when something was written).
    func discard() {
        guard let app else { return }
        autosaveTask?.cancel()
        let remove: @MainActor () async throws -> Void = { [draft] in
            if let id = draft.draftID { try await app.mail.discardDraft(id, account: draft.account) }
            if app.mail.compose?.id == self.id { app.mail.compose = nil }
            await app.mail.loadLabels()
        }
        if draft.isEmpty && draft.draftID == nil {
            app.mail.compose = nil
            return
        }
        app.confirm(ConfirmRequest(title: "Discard this draft?", message: draft.draftID == nil ? "What you wrote will be lost." : "The draft will be deleted from Gmail. This cannot be undone.",
                                   actionLabel: "Discard", destructive: true, workingLabel: "Discarding…") { _ in try await remove() })
    }

    // MARK: Send

    /// Asks in the ConfirmWriteSheet; sends only when the user presses Send there. Never called by smoke/tests
    /// beyond opening the sheet.
    func requestSend() {
        guard let app, let from = fromAddress else { return }
        if let problem = draft.sendProblem {
            saveState = .failed(problem)
            return
        }
        if attachmentsTooLarge {
            saveState = .failed("Attachments are over Gmail’s 25 MB limit.")
            return
        }
        autosaveTask?.cancel()
        let message = draft.outgoing(from: from, ownAddresses: app.ownAddresses, zone: app.zone)
        let account = draft.account
        let recipients = message.allRecipients.map { $0.name ?? $0.email }
        let list = recipients.count > 3 ? recipients.prefix(3).joined(separator: ", ") + " and \(recipients.count - 3) more" : recipients.joined(separator: ", ")
        let subject = message.subject.isEmpty ? "(no subject)" : message.subject
        var text = "“\(subject)” to \(list), from \(from.email). Sent mail can’t be called back."
        if app.isFixtureMode { text += " (Sample data: sending is switched off, so this will be refused.)" }
        let modelID = id
        app.confirm(ConfirmRequest(title: "Send this message?", message: text, actionLabel: "Send", workingLabel: "Sending…") { [self] confirmed in
            // An autosave already in flight may create the draft: wait for it and send through that draft, so no
            // copy of the sent mail is left behind in Drafts.
            await self.waitForPendingSave()
            var message = message
            message.draftID = self.draft.draftID
            try await app.mail.send(message, account: account, confirmed: confirmed)
            if app.mail.compose?.id == modelID { app.mail.compose = nil }
        })
    }

    // MARK: Status line

    var statusText: String? {
        switch saveState {
        case .idle: return nil
        case .saving: return "Saving draft…"
        case .saved(let date): return "Draft saved to Gmail · \(DeskFormat.time(date, zone: app?.zone ?? .current))"
        case .writesOff: return "Changes are off · draft not saved to Gmail"
        case .failed(let message): return message
        }
    }

    /// Smoke / previews: put text in the body.
    func replaceBody(_ body: NSAttributedString) {
        replacementBody = body
        bodyRevision += 1
    }
}

extension MailStore {
    /// The account's Gmail signature as plain lines ("Alex Morgan\nUNC Charlotte · …").
    func signature(for account: String) -> String? {
        guard let html = sendAs[account.lowercased()]?.signature, !html.isEmpty else { return nil }
        let text = HTMLSanitizer.plainText(html).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
