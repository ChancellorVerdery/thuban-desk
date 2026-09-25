import Foundation
import Observation
import ThubanDeskCore
@preconcurrency import UserNotifications

/// Local notifications only — no push, no widgets, no Live Activities. While the app runs it schedules a reminder
/// 10 minutes before each timed event of the next 24 hours, and posts one for each new pending invitation and new
/// "needs a reply" thread (items seen at launch never notify). Off in fixture mode: smoke and development never ask
/// for permission.
@MainActor
@Observable
final class LocalNotifications {
    static let shared = LocalNotifications()

    var eventReminders: Bool { didSet { persist(); update() } }
    var invitations: Bool { didSet { persist() } }
    var replies: Bool { didSet { persist() } }
    private(set) var denied = false

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var seenInvitations: Set<String>?
    @ObservationIgnored private var seenReplies: Set<String>?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var scheduledEvents: [String] = []

    private init() {
        eventReminders = defaults.object(forKey: "notify.events") as? Bool ?? true
        invitations = defaults.object(forKey: "notify.invitations") as? Bool ?? true
        replies = defaults.object(forKey: "notify.replies") as? Bool ?? true
    }

    /// "Replies, invites" (Settings row).
    var summary: String {
        var parts: [String] = []
        if eventReminders { parts.append("Events") }
        if replies { parts.append("Replies") }
        if invitations { parts.append("invites") }
        guard !parts.isEmpty else { return "Off" }
        let text = parts.joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    func start(app: AppModel) {
        guard !app.isFixtureMode, self.app == nil else { return }
        self.app = app
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            denied = !granted
            observe()
        }
    }

    private func persist() {
        defaults.set(eventReminders, forKey: "notify.events")
        defaults.set(invitations, forKey: "notify.invitations")
        defaults.set(replies, forKey: "notify.replies")
    }

    private func observe() {
        guard let app else { return }
        withObservationTracking {
            _ = app.calendar.revision
            _ = app.mail.needsReplyThreads.count
        } onChange: {
            Task { @MainActor [weak self] in
                self?.update()
                self?.observe()
            }
        }
        update()
    }

    private func update() {
        guard let app, !denied else { return }
        let center = UNUserNotificationCenter.current()
        let now = app.now()
        let zone = app.zone

        // Event reminders (replaced wholesale each time the calendar changes).
        center.removePendingNotificationRequests(withIdentifiers: scheduledEvents)
        scheduledEvents = []
        if eventReminders {
            for item in app.calendar.events(from: now, to: now.addingTimeInterval(86_400)) where !item.event.isAllDay {
                let fire = item.start(in: zone).addingTimeInterval(-600)
                guard fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = item.event.title
                content.body = "\(CalendarText.timeRange(item.start(in: zone), item.end(in: zone), zone: zone))\(item.event.location.map { " · \($0)" } ?? "")"
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSince(now), repeats: false)
                center.add(UNNotificationRequest(identifier: "event|\(item.id)", content: content, trigger: trigger))
                scheduledEvents.append("event|\(item.id)")
            }
        }

        // New invitations.
        let pending = app.calendar.pendingInvitations
        let invitationIDs = Set(pending.map(\.id))
        if let seen = seenInvitations, invitations {
            for item in pending where !seen.contains(item.id) {
                post(id: "invite|\(item.id)", title: "Invitation: \(item.event.title)", body: CalendarText.when(item.event, zone: zone))
            }
        }
        seenInvitations = (seenInvitations ?? []).union(invitationIDs)

        // New "needs a reply" threads.
        let waiting = app.mail.needsReplyThreads
        let replyIDs = Set(waiting.map { $0.summary.key.description })
        if let seen = seenReplies, replies {
            for pair in waiting where !seen.contains(pair.summary.key.description) {
                post(id: "reply|\(pair.summary.key)", title: "\(pair.summary.from?.displayName ?? "Someone") is waiting on you",
                     body: pair.verdict.question ?? pair.summary.subject)
            }
        }
        seenReplies = (seenReplies ?? []).union(replyIDs)
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
