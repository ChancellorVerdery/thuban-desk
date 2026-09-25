import Foundation

/// "Needs a reply" (Today and the Mail list filter): a real person wrote directly to you, asked something, and
/// you have not answered — within the last 7 days. Newsletters, notifications, mailing lists, automated senders,
/// Promotions/Social/Updates/Forums, spam and trash never qualify.
public enum NeedsReply {
    public struct Verdict: Hashable, Sendable {
        public var needsReply: Bool
        /// Why not (or "asks a question") — for tests and debugging.
        public var reason: String
        /// The sentence that asks (for the Today card: "Can you grab whiteboard markers?").
        public var question: String?
        /// The message waiting for an answer.
        public var messageID: String?
    }

    public static let window: TimeInterval = 7 * 86_400

    static let automatedLocalParts = ["noreply", "no-reply", "no_reply", "donotreply", "do-not-reply", "notifications", "notification",
                                      "notify", "mailer-daemon", "postmaster", "bounce", "bounces", "news", "newsletter", "newsletters",
                                      "marketing", "updates", "alerts", "alert", "digest", "automated", "auto", "system", "info", "hello",
                                      "support", "team", "careers", "billing", "receipts", "statements", "admin", "announcements"]
    static let excludedLabels: Set<String> = [GmailSystemLabel.spam, GmailSystemLabel.trash, GmailSystemLabel.categoryPromotions,
                                               GmailSystemLabel.categorySocial, GmailSystemLabel.categoryUpdates, GmailSystemLabel.categoryForums]
    static let requestPhrases = ["could you", "can you", "would you", "will you", "are you", "do you", "please let me know", "let me know",
                                 "please confirm", "please reply", "please send", "can we", "could we", "what time", "when can", "are we"]

    /// `ownAddresses`: every address of the user (all linked accounts and aliases), lower-cased.
    public static func classify(_ thread: MailThread, ownAddresses: Set<String>, now: Date = Date()) -> Verdict {
        let own = Set(ownAddresses.map { $0.lowercased() }).union([thread.account])
        let messages = thread.messages.filter { !$0.isDraft }
        guard let last = messages.last else { return Verdict(needsReply: false, reason: "empty") }
        if !thread.labelIDs.isDisjoint(with: excludedLabels) { return Verdict(needsReply: false, reason: "category, spam or trash") }
        guard let sender = last.from else { return Verdict(needsReply: false, reason: "no sender") }
        if own.contains(sender.normalized) || last.isSent { return Verdict(needsReply: false, reason: "you wrote last") }
        if now.timeIntervalSince(last.date) > window { return Verdict(needsReply: false, reason: "older than 7 days") }
        if isAutomated(last) { return Verdict(needsReply: false, reason: "automated or bulk sender") }
        let recipients = last.to + last.cc
        guard recipients.contains(where: { own.contains($0.normalized) }) else { return Verdict(needsReply: false, reason: "not addressed to you") }
        if recipients.count > 8 { return Verdict(needsReply: false, reason: "sent to a crowd") }
        guard let question = question(in: newText(of: last)) else { return Verdict(needsReply: false, reason: "does not ask anything") }
        return Verdict(needsReply: true, reason: "asks a question", question: question, messageID: last.id)
    }

    /// Bulk / list / automated heuristics on headers and the sender's address.
    public static func isAutomated(_ message: MailMessage) -> Bool {
        let headers = message.extraHeaders
        if headers["list-id"] != nil || headers["list-unsubscribe"] != nil { return true }
        if let precedence = headers["precedence"]?.lowercased(), ["bulk", "list", "junk", "auto_reply"].contains(precedence) { return true }
        if let auto = headers["auto-submitted"]?.lowercased(), auto != "no" { return true }
        guard let from = message.from else { return true }
        let local = String(from.normalized.split(separator: "@").first ?? "")
        let tokens = local.split(whereSeparator: { $0 == "." || $0 == "+" || $0 == "_" || $0 == "-" }).map(String.init)
        if automatedLocalParts.contains(local) || tokens.contains(where: { ["noreply", "donotreply", "notifications", "newsletter", "mailer"].contains($0) }) {
            return true
        }
        return false
    }

    /// The message text without quoted history ("> …" lines, "On … wrote:" and everything after, signatures after "-- ").
    public static func newText(of message: MailMessage) -> String {
        var lines: [String] = []
        for line in message.plainBody.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") { continue }
            if trimmed == "--" || trimmed == "-- " { break }
            if trimmed.range(of: #"^On .+ wrote:$"#, options: .regularExpression) != nil { break }
            if trimmed.hasPrefix("---------- Forwarded message") || trimmed.hasPrefix("-----Original Message-----") { break }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// The first sentence that asks something: ends in "?" or starts with a request phrase.
    public static func question(in text: String) -> String? {
        let sentences = splitSentences(text)
        if let asked = sentences.first(where: { $0.hasSuffix("?") }) { return asked }
        return sentences.first { sentence in
            let lower = sentence.lowercased()
            return requestPhrases.contains { lower.hasPrefix($0) || lower.contains(" \($0) ") }
        }
    }

    static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for char in text.replacingOccurrences(of: "\n", with: " ") {
            current.append(char)
            if char == "?" || char == "." || char == "!" {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { sentences.append(rest) }
        return sentences.map { $0.split(separator: " ").joined(separator: " ") }
    }
}
