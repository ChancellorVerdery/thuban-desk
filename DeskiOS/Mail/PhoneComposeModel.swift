import Foundation
import Observation
import ThubanDeskCore
import UIKit

/// The reply / compose sheet's state: the core `ComposeDraft` (recipients, subject, account, what it answers), the
/// body as attributed text (bold / italic / bullets → `RichRuns` HTML), Gmail draft autosave, and the send path —
/// which only runs from the confirm sheet (`ConfirmRequest` → `MailStore.send(…, confirmed:)`). Replies and forwards
/// always go from the account the thread arrived in.
@MainActor
@Observable
final class PhoneComposeModel: Identifiable {
    let id = UUID()
    @ObservationIgnored weak var app: AppModel?
    var draft: ComposeDraft
    /// The typed body (set by the text view).
    @ObservationIgnored var body = NSAttributedString()
    var bodyRevision = 0
    /// Initial body the text view starts with (and a replacement after e.g. a draft was reopened).
    @ObservationIgnored var initialBody: NSAttributedString
    var toText = ""
    var ccText = ""
    var bccText = ""
    var showCcBcc = false
    var showQuote = false
    var savedAt: Date?
    var isSaving = false
    var error: String?
    /// The thread a reply belongs to (for the "Show quoted text" chip).
    let threadKey: ThreadKey?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(app: AppModel, draft: ComposeDraft, body: NSAttributedString = NSAttributedString(), threadKey: ThreadKey? = nil) {
        self.app = app
        self.draft = draft
        self.initialBody = body
        self.body = body
        self.threadKey = threadKey
        showCcBcc = !draft.cc.isEmpty || !draft.bcc.isEmpty
    }

    // MARK: Starting points

    static func new(app: AppModel) -> PhoneComposeModel {
        let account = app.mail.defaultSendAccount ?? app.primaryAccount?.id ?? ""
        return PhoneComposeModel(app: app, draft: ComposeDraft(account: account))
    }

    static func reply(to message: MailMessage, in key: ThreadKey, all: Bool, app: AppModel) -> PhoneComposeModel {
        let from = app.mail.fromAddress(for: key.account)
        let draft = ComposeDraft.reply(to: message, account: from, replyAll: all, ownAddresses: app.ownAddresses)
        return PhoneComposeModel(app: app, draft: draft, threadKey: key)
    }

    static func forward(_ message: MailMessage, in key: ThreadKey, app: AppModel) -> PhoneComposeModel {
        let from = app.mail.fromAddress(for: key.account)
        return PhoneComposeModel(app: app, draft: ComposeDraft.forward(message, account: from), threadKey: key)
    }

    // MARK: Derived

    var title: String {
        switch draft.kind {
        case .new: return "New message"
        case .reply(_, let all): return all ? "Reply all" : "Reply"
        case .forward: return "Forward"
        }
    }

    var fromAddress: EmailAddress? { app?.mail.fromAddress(for: draft.account) }

    /// "Show quoted text · Priya Shah, 2:14 PM".
    var quoteChip: String? {
        guard let original = draft.original, let app else { return nil }
        return "Show quoted text · \(original.from?.displayName ?? "original"), \(CalendarText.clock(original.date, zone: app.zone))"
    }

    var quoteText: String? {
        guard let original = draft.original, let app else { return nil }
        return ComposeDraft.quoteAttribution(original, zone: app.zone) + "\n" + original.plainBody
    }

    /// Recipients typed but not yet turned into chips count as well.
    func commitTyped() {
        for (text, keyPath) in [(toText, \ComposeDraft.to), (ccText, \ComposeDraft.cc), (bccText, \ComposeDraft.bcc)] {
            let parsed = ComposeDraft.parseRecipients(text)
            if !parsed.addresses.isEmpty { draft[keyPath: keyPath] = ComposeDraft.adding(parsed.addresses, to: draft[keyPath: keyPath]) }
        }
        toText = ComposeDraft.parseRecipients(toText).rest
        ccText = ComposeDraft.parseRecipients(ccText).rest
        bccText = ComposeDraft.parseRecipients(bccText).rest
    }

    var sendProblem: String? {
        if !toText.trimmingCharacters(in: .whitespaces).isEmpty || !ccText.trimmingCharacters(in: .whitespaces).isEmpty {
            let parsed = ComposeDraft.parseRecipients(toText + "," + ccText)
            if !parsed.rest.isEmpty { return "“\(parsed.rest)” is not an email address." }
        }
        var probe = draft
        probe.to = ComposeDraft.adding(ComposeDraft.parseRecipients(toText).addresses, to: probe.to)
        return probe.sendProblem
    }

    // MARK: Body

    func bodyChanged(_ text: NSAttributedString) {
        body = text
        bodyRevision += 1
        scheduleSave()
    }

    /// The body as runs → HTML + plain text on the draft.
    func syncBody() {
        let paragraphs = RichRuns.paragraphs(fromLines: Self.lines(of: body))
        draft.html = RichRuns.html(paragraphs)
        draft.text = RichRuns.plainText(paragraphs)
    }

    static func lines(of text: NSAttributedString) -> [[RichRuns.Run]] {
        var lines: [[RichRuns.Run]] = [[]]
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            let font = attributes[.font] as? UIFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let chunk = (text.string as NSString).substring(with: range)
            let pieces = chunk.components(separatedBy: "\n")
            for (index, piece) in pieces.enumerated() {
                if index > 0 { lines.append([]) }
                if !piece.isEmpty {
                    lines[lines.count - 1].append(RichRuns.Run(piece, bold: traits.contains(.traitBold), italic: traits.contains(.traitItalic)))
                }
            }
        }
        return lines
    }

    // MARK: Drafts

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.saveDraft()
        }
    }

    /// Saves (creates / updates) the Gmail draft. Nothing is saved for an empty message.
    func saveDraft() async {
        guard let app, let from = fromAddress else { return }
        commitTyped()
        syncBody()
        guard !draft.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await app.mail.saveDraft(draft.outgoing(from: from, ownAddresses: app.ownAddresses, zone: app.zone), account: draft.account)
            draft.draftID = saved.draftID
            savedAt = app.now()
            error = nil
        } catch {
            self.error = "Draft not saved: \(error.localizedDescription)"
        }
    }

    /// Cancel: keeps the saved draft (Gmail Drafts) — nothing is sent.
    func close() {
        saveTask?.cancel()
    }

    func discard() async {
        saveTask?.cancel()
        guard let app, let id = draft.draftID else { return }
        try? await app.mail.discardDraft(id, account: draft.account)
    }

    /// Asks before sending (the confirm sheet); only its button sends. Fixture mode refuses the send.
    func requestSend(onSent: @escaping @MainActor () -> Void) {
        guard let app, let from = fromAddress else { return }
        saveTask?.cancel()
        commitTyped()
        syncBody()
        if let problem = draft.sendProblem { error = problem; return }
        let message = draft.outgoing(from: from, ownAddresses: app.ownAddresses, zone: app.zone)
        let account = draft.account
        let recipients = (draft.to + draft.cc + draft.bcc).map(\.displayName)
        let mail = app.mail
        app.confirm(ConfirmRequest(
            title: "Send this message?",
            message: "From \(from.email) to \(CalendarText.list(recipients)). Sent mail can’t be taken back.",
            actionLabel: "Send", workingLabel: "Sending…"
        ) { confirmed in
            try await mail.send(message, account: account, confirmed: confirmed)
            onSent()
        })
    }
}
