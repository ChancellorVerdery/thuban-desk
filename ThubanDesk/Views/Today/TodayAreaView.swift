import SwiftUI
import ThubanDeskCore

/// Today (design artboard "Today"): a 48 pt toolbar with the date, then two columns — the day's agenda (Done / Now /
/// free gaps / upcoming) and tomorrow on the left; "Needs a reply" threads, pending invitations with RSVP and the
/// rule footnote on the right. Re-renders every minute so Now and the countdowns stay current.
struct TodayAreaView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let model = TodayModel(app: app)
            VStack(spacing: 0) {
                TodayToolbar(model: model)
                ScrollView {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 16) {
                            AgendaCard(model: model)
                            TomorrowCard(model: model)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        VStack(alignment: .leading, spacing: 16) {
                            NeedsReplyCard(model: model)
                            InvitationsCard(model: model)
                            footnote
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                }
                .scrollIndicators(.automatic)
            }
        }
        .task {
            let today = CivilDate(app.now(), in: app.zone)
            await app.calendar.ensureEvents(from: today.startDate(in: app.zone), to: today.adding(days: 2).startDate(in: app.zone))
        }
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 6) {
            Icon(.info, size: 13).padding(.top, 2)
            Text("A thread needs a reply when a person wrote to you directly, asked something, and you haven’t answered in 7 days. Newsletters and notifications never appear here.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(ThubanFont.body(12.5))
        .foregroundStyle(theme.inkFaintColor)
        .lineSpacing(2)
    }
}

// MARK: - Model

/// Everything the Today cards show, computed once per render from the stores (pure functions in the core).
@MainActor
struct TodayModel {
    let now: Date
    let zone: TimeZone
    let today: CivilDate
    let entries: [TodayAgenda.Entry]
    let tomorrow: [AgendaEvent]
    let invitations: [AgendaEvent]
    let replies: [ReplyItem]
    /// Event id → the thread asking about it (the agenda row's "Maya: …" chip).
    let questionsByEvent: [String: ReplyItem]
    /// All loaded events today and tomorrow (conflict checks).
    let nearby: [AgendaEvent]

    struct ReplyItem: Identifiable {
        var summary: ThreadSummary
        var verdict: NeedsReply.Verdict
        var link: TodayLinks.Link?
        /// The asking sentence (+ the next one) from the full thread.
        var quote: String?
        var id: String { summary.key.description }
    }

    init(app: AppModel) {
        let now = app.now()
        let zone = app.zone
        let today = CivilDate(now, in: zone)
        let start = today.startDate(in: zone)
        let mid = today.adding(days: 1).startDate(in: zone)
        let end = today.adding(days: 2).startDate(in: zone)
        let tomorrowDay = today.adding(days: 1)
        let invitations = app.calendar.pendingInvitations
        let own = app.ownAddresses
        let linkPool = app.calendar.events(from: start, to: today.adding(days: 4).startDate(in: zone))
        let items = app.mail.needsReplyThreads.map { pair in
            ReplyItem(summary: pair.summary, verdict: pair.verdict,
                      link: pair.summary.from.flatMap { TodayLinks.link(sender: $0.normalized, events: linkPool, invitations: invitations, own: own, now: now, zone: zone) },
                      quote: app.mail.details[pair.summary.key].flatMap { TodayLinks.excerpt(of: $0, verdict: pair.verdict) } ?? pair.verdict.question)
        }
        var byEvent: [String: ReplyItem] = [:]
        for item in items {
            if let link = item.link, link.kind == .event, byEvent[link.event.id] == nil { byEvent[link.event.id] = item }
        }
        self.now = now
        self.zone = zone
        self.today = today
        entries = TodayAgenda.build(events: app.calendar.events(from: start, to: mid), day: today, now: now, zone: zone)
        tomorrow = app.calendar.events(from: mid, to: end)
            .filter { item in
                guard !item.event.isCancelled, item.event.selfResponse != .declined else { return false }
                if item.event.isAllDay {
                    return (item.event.start.date ?? tomorrowDay) <= tomorrowDay && (item.event.end.date ?? tomorrowDay.adding(days: 1)) > tomorrowDay
                }
                return item.start(in: zone) >= mid
            }
            .sorted { ($0.event.isAllDay ? 0 : 1, $0.start(in: zone), $0.event.title) < ($1.event.isAllDay ? 0 : 1, $1.start(in: zone), $1.event.title) }
        self.invitations = invitations
        nearby = app.calendar.events(from: start, to: end, includeHidden: true)
        replies = items
        questionsByEvent = byEvent
    }

    var eventCount: Int {
        entries.reduce(0) { count, entry in
            switch entry {
            case .allDay, .event: return count + 1
            case .free, .nowMarker: return count
            }
        }
    }

    var remainingCount: Int {
        entries.reduce(0) { count, entry in
            if case .event(_, let status) = entry, status != .done { return count + 1 }
            return count
        }
    }
}

// MARK: - Toolbar

private struct TodayToolbar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var model: TodayModel

    var body: some View {
        HStack(spacing: 12) {
            Text(Self.longDate(model.today))
                .font(ThubanFont.display(19))
                .foregroundStyle(theme.inkColor)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(ThubanFont.body(13.5))
                .foregroundStyle(theme.inkDimColor)
                .lineLimit(1)
            Spacer(minLength: 12)
            Button { app.requestNewEvent() } label: {
                HStack(spacing: 7) { Icon(.plus, size: 15); Text("New event") }
            }
            .buttonStyle(SecondaryButtonStyle(height: 32))
            .help("New event (opens Calendar)")
            Button { app.requestCompose() } label: {
                HStack(spacing: 7) { Icon(.mail, size: 15); Text("Compose") }
            }
            .buttonStyle(SecondaryButtonStyle(height: 32))
            .help("New message (opens Mail)")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(theme.bgColor)
        .thubanHairline(.bottom, color: theme.lineColor)
    }

    private var subtitle: String {
        var parts: [String] = []
        let left = model.remainingCount
        parts.append(left == 0 ? "Nothing else scheduled" : "\(left) event\(left == 1 ? "" : "s") ahead")
        if !model.replies.isEmpty { parts.append("\(model.replies.count) to answer") }
        if !model.invitations.isEmpty { parts.append("\(model.invitations.count) invitation\(model.invitations.count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    /// "Thursday, September 24".
    static func longDate(_ day: CivilDate) -> String {
        let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        return "\(day.weekday.name), \(months[day.month - 1]) \(day.day)"
    }
}

// MARK: - Shared bits

/// A Today card: panel, 1 px line border, radius 10.
struct TodayCard<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }
}

/// "Open week" / "Open Mail": 13 pt semibold brass text link.
struct TodayLinkButton: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.brassInkColor)
                .opacity(hovering ? 0.8 : 1)
                .underline(hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension AppModel {
    /// Account colour: the primary is accent, the next signal, and so on (as in Settings → Accounts and Mail).
    func accountTint(_ account: String) -> CalendarTint {
        mail.accountTint(account)
    }
}

enum PersonTint {
    /// A stable colour per person (the same address always gets the same one).
    static func tint(for address: String) -> CalendarTint {
        let palette: [CalendarTint] = [.signal, .neg, .pos, .accent]
        let sum = address.lowercased().unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }
}
