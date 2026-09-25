import SwiftUI
import ThubanDeskCore

/// Today (board "Today"): sync pill + New event / Compose / avatar (→ Settings), the day's agenda (Done / Now / free
/// gaps), pending invitations with Yes / Maybe / No, and "Needs a reply". Re-renders every minute.
struct TodayTab: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.todayPath) {
            TodayScreen()
                .navigationDestination(for: TodayRoute.self) { route in
                    switch route {
                    case .settings: SettingsScreen()
                    case .account(let id): AccountScreen(accountID: id)
                    }
                }
        }
    }
}

struct TodayScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    /// iPad shows Today in the split view's detail column (no avatar: Settings is in the sidebar).
    var showsAccountButton = true

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let model = TodayModel(app: app)
            PhoneScreen(title: "Today", subtitle: subtitle(model)) {
                SyncPill()
            } navTrailing: {
                NavIconButton(.calendarAdd, label: "New event") { app.requestNewEvent() }
                NavIconButton(.compose, label: "Compose") { app.requestCompose() }
                if showsAccountButton {
                    Button { router.todayPath.append(.settings) } label: {
                        PhoneAvatar(name: app.primaryAccount?.displayName ?? app.primaryAccount?.email ?? "Me", tint: .accent, size: 32, ringed: true)
                            .frame(width: PhoneMetrics.hit, height: PhoneMetrics.hit)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Accounts and settings")
                }
            } content: {
                if !app.hasAccounts {
                    ConnectCard()
                        .padding(.horizontal, PhoneMetrics.gutter)
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        AgendaSection(model: model)
                        ForEach(model.invitations.prefix(3)) { item in
                            InvitationCardView(item: item, model: model)
                        }
                        NeedsReplySection(model: model)
                    }
                    .padding(.horizontal, PhoneMetrics.gutter)
                    .padding(.bottom, 24)
                }
            }
            .refreshable { await app.refreshAll() }
        }
        .task {
            let today = CivilDate(app.now(), in: app.zone)
            await app.calendar.ensureEvents(from: today.startDate(in: app.zone), to: today.adding(days: 2).startDate(in: app.zone))
        }
    }

    private func subtitle(_ model: TodayModel) -> String {
        let date = "\(model.today.weekday.name), \(CalendarText.monthTitle(year: model.today.year, month: model.today.month).split(separator: " ").first ?? "") \(model.today.day)"
        let left = model.remainingCount
        let tail = left == 0 ? "nothing else today" : "\(left) event\(left == 1 ? "" : "s") ahead"
        return "\(date) · \(tail)"
    }
}

/// "2 accounts · synced 2:38" with a status dot.
struct SyncPill: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let tone = app.syncSummary.tone
        HStack(spacing: 7) {
            Circle().fill(dot(tone)).frame(width: 7, height: 7)
            Text(app.phoneSyncText).lineLimit(1)
        }
        .font(PhoneFont.footnoteSemibold)
        .foregroundStyle(theme.inkDimColor)
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.leading, 8)
        .accessibilityElement(children: .combine)
    }

    private func dot(_ tone: AppModel.SyncTone) -> Color {
        switch tone {
        case .ok: return theme.signalColor
        case .busy: return theme.accentColor
        case .problem: return theme.negColor
        case .idle: return theme.inkFaintColor
        }
    }
}

/// No account yet: one sentence and the way to Settings.
struct ConnectCard: View {
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        InsetCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connect a Google account").font(PhoneFont.display(.title3)).foregroundStyle(theme.inkColor)
                Text("Thuban Desk shows your Google Calendar and Gmail. Sign in once per account; nothing else leaves this phone.")
                    .font(PhoneFont.secondary).foregroundStyle(theme.inkDimColor)
                Button("Add Google account") { router.todayPath = [.settings] }
                    .buttonStyle(PhonePrimaryButtonStyle())
            }
            .padding(16)
        }
    }
}

// MARK: - Agenda

private struct AgendaSection: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    var model: TodayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Agenda · \(model.eventCount) event\(model.eventCount == 1 ? "" : "s")")
                Spacer()
                Button("Open day") {
                    app.calendar.ui.focus = nil
                    router.calendarMode = .day
                    router.tab = .calendar
                    router.padSection = .calendar
                }
                .font(PhoneFont.secondarySemibold)
                .foregroundStyle(theme.brassInkColor)
                .frame(minHeight: 32)
            }
            .padding(.horizontal, 4)
            InsetCard {
                if model.entries.allSatisfy({ if case .nowMarker = $0 { return true } else { return false } }) {
                    Text("Nothing scheduled today.")
                        .font(PhoneFont.secondary).foregroundStyle(theme.inkDimColor)
                        .padding(16)
                } else {
                    ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0, needsDivider(before: entry, previous: model.entries[index - 1]) { RowDivider() }
                        row(entry)
                    }
                }
            }
        }
    }

    private func needsDivider(before entry: TodayAgenda.Entry, previous: TodayAgenda.Entry) -> Bool {
        switch (entry, previous) {
        case (.free, _), (_, .free), (.nowMarker, _), (_, .nowMarker): return false
        case (.event(_, .now), _), (_, .event(_, .now)): return false
        default: return true
        }
    }

    @ViewBuilder private func row(_ entry: TodayAgenda.Entry) -> some View {
        switch entry {
        case .allDay(let item):
            AgendaRow(item: item, status: nil, zone: model.zone, allDay: true)
        case .event(let item, let status):
            AgendaRow(item: item, status: status, zone: model.zone, allDay: false)
        case .free(let interval):
            HStack(spacing: 10) {
                dashed
                Text("Free \(CalendarText.clock(interval.start, zone: model.zone, suffix: false)) – \(CalendarText.clock(interval.end, zone: model.zone, suffix: false)) · \(TodayAgenda.durationText(interval.duration))")
                    .font(PhoneFont.footnote).foregroundStyle(theme.inkFaintColor).lineLimit(1).minimumScaleFactor(0.8)
                    .fixedSize()
                    .layoutPriority(1)
                dashed
            }
            .padding(.leading, 72)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        case .nowMarker(let now):
            HStack(spacing: 8) {
                Text(CalendarText.clock(now, zone: model.zone, suffix: false)).font(PhoneFont.monoSmall).foregroundStyle(theme.brassInkColor)
                    .frame(width: 56, alignment: .leading)
                Circle().fill(theme.brassInkColor).frame(width: 7, height: 7)
                Rectangle().fill(theme.brassInkColor).frame(height: 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Now, \(CalendarText.clock(now, zone: model.zone))")
        }
    }

    private var dashed: some View {
        Line().stroke(theme.line2Color, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct AgendaRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: AgendaEvent
    var status: TodayAgenda.Status?
    var zone: TimeZone
    var allDay: Bool

    var body: some View {
        let isNow: Bool = { if case .now = status { return true } else { return false } }()
        let isDone = status == .done
        Button { app.calendar.ui.edit(item) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    if allDay {
                        Text("all-day").font(PhoneFont.mono).foregroundStyle(theme.inkDimColor)
                    } else {
                        Text(CalendarText.clock(item.start(in: zone), zone: zone, suffix: false)).font(PhoneFont.mono).foregroundStyle(theme.inkColor)
                        Text(CalendarText.clock(item.end(in: zone), zone: zone, suffix: false)).font(PhoneFont.mono)
                            .foregroundStyle(isNow ? theme.inkDimColor : theme.inkFaintColor)
                    }
                }
                .frame(width: 56, alignment: .leading)
                RoundedRectangle(cornerRadius: 2).fill(theme.color(for: item.tint)).frame(width: 3).frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.event.title).font(PhoneFont.bodySemibold).foregroundStyle(theme.inkColor).multilineTextAlignment(.leading)
                    if let detail { Text(detail).font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, isNow ? 10 : 8)
            .frame(minHeight: isNow ? 64 : 56)
            .background(isNow ? theme.accentTintColor : Color.clear)
            .overlay(alignment: .top) { if isNow { Rectangle().fill(theme.lineColor).frame(height: 1) } }
            .overlay(alignment: .bottom) { if isNow { Rectangle().fill(theme.lineColor).frame(height: 1) } }
            .opacity(isDone ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the event")
    }

    private var detail: String? {
        var parts: [String] = []
        if let location = item.event.location, !location.isEmpty { parts.append(location) }
        let guests = (item.event.attendees ?? []).filter { $0.isSelf != true && $0.resource != true }.compactMap { $0.displayName?.split(separator: " ").first.map(String.init) }
        if !guests.isEmpty { parts.append(guests.prefix(3).joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private var trailing: some View {
        switch status {
        case .done:
            Text("Done").font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor)
        case .now(let remaining):
            Text("Now · \(TodayAgenda.durationText(remaining))")
                .font(PhoneFont.footnoteSemibold)
                .foregroundStyle(theme.brassInkColor)
                .padding(.horizontal, 8)
                .frame(minHeight: 24)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.accentColor, lineWidth: 1))
                .fixedSize()
        case .upcoming, nil:
            EmptyView()
        }
    }
}

// MARK: - Invitation

/// An unanswered invitation: date tile, "INVITATION · gmail.com", title, when · where · conflicts, and Yes / Maybe / No.
struct InvitationCardView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: AgendaEvent
    var model: TodayModel?
    /// Inside a message (Thread): recessed card.
    var embedded = false
    @State private var busy = false
    @State private var answered: ResponseStatus?
    @State private var error: String?

    var body: some View {
        let zone = app.zone
        let start = item.start(in: zone)
        let day = CivilDate(start, in: zone)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(day.weekday.shortName.uppercased()).font(.system(size: 11, weight: .bold)).kerning(0.6).foregroundStyle(theme.negTextColor)
                    Text("\(day.day)").font(PhoneFont.display(.title3)).foregroundStyle(theme.inkColor)
                }
                .frame(width: 44, height: 48)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Eyebrow("Invitation · \(item.calendar.account.split(separator: "@").last.map(String.init) ?? "")")
                        .font(.system(size: 11, weight: .semibold))
                    Text(item.event.title).font(PhoneFont.bodySemibold).foregroundStyle(theme.inkColor)
                    Text(detail).font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor)
                }
            }
            if let answered {
                Text(answeredText(answered)).font(PhoneFont.secondarySemibold).foregroundStyle(theme.brassInkColor)
            } else {
                HStack(spacing: 8) {
                    answer("Yes", .accepted, primary: true)
                    answer("Maybe", .tentative, primary: false)
                    answer("No", .declined, primary: false)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Respond")
            }
            if let error { Text(error).font(PhoneFont.footnote).foregroundStyle(theme.negTextColor) }
        }
        .padding(.horizontal, embedded ? 12 : 16)
        .padding(.vertical, embedded ? 12 : 14)
        .background(embedded ? theme.bgColor : theme.panelColor, in: RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
    }

    private var detail: String {
        let zone = app.zone
        var parts: [String] = []
        if item.event.isAllDay {
            parts.append("All day")
        } else {
            parts.append(TodayLinks.range(item.start(in: zone), item.end(in: zone), zone: zone))
        }
        if let location = item.event.location, !location.isEmpty { parts.append(location) }
        if !item.event.isAllDay {
            let now = app.now()
            let day = CivilDate(item.start(in: zone), in: zone)
            let nearby = model?.nearby ?? app.calendar.events(from: day.startDate(in: zone), to: day.adding(days: 1).startDate(in: zone), includeHidden: true)
            let conflicts = TodayLinks.conflicts(of: item, among: nearby, zone: zone)
            _ = now
            parts.append(conflicts.isEmpty ? "no conflicts" : "overlaps \(TodayLinks.shortTitle(conflicts[0].event.title))")
        }
        return parts.joined(separator: " · ")
    }

    private func answeredText(_ status: ResponseStatus) -> String {
        switch status {
        case .accepted: return "Going · Google tells the organizer"
        case .tentative: return "Maybe · Google tells the organizer"
        case .declined: return "Not going · Google tells the organizer"
        default: return "Answered"
        }
    }

    private func answer(_ title: String, _ status: ResponseStatus, primary: Bool) -> some View {
        Button {
            Task {
                busy = true
                error = nil
                do {
                    try await app.calendar.rsvp(status, to: item.event, in: item.calendar)
                    answered = status
                } catch {
                    self.error = error.localizedDescription
                }
                busy = false
            }
        } label: {
            Text(title)
                .font(PhoneFont.secondarySemibold)
                .foregroundStyle(primary ? theme.onAccentInk : theme.inkColor)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(primary ? theme.accentColor : theme.panelColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(primary ? Color.clear : theme.line2Color, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("\(title), \(item.event.title)")
    }
}

// MARK: - Needs a reply

private struct NeedsReplySection: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    var model: TodayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Needs a reply · \(model.replies.count)")
                Spacer()
                Button("Open Mail") {
                    router.showMailbox(MailScope())
                    router.padSection = .mail(MailScope())
                }
                .font(PhoneFont.secondarySemibold)
                .foregroundStyle(theme.brassInkColor)
                .frame(minHeight: 32)
            }
            .padding(.horizontal, 4)
            InsetCard {
                if model.replies.isEmpty {
                    Text("You’re all caught up.").font(PhoneFont.secondary).foregroundStyle(theme.inkDimColor).padding(16)
                } else {
                    ForEach(Array(model.replies.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RowDivider(inset: 64) }
                        ReplyRow(item: item, now: model.now)
                    }
                }
            }
        }
    }
}

private struct ReplyRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: TodayModel.ReplyItem
    var now: Date

    var body: some View {
        let sender = item.summary.from
        Button { app.openThread(item.summary.key) } label: {
            HStack(alignment: .top, spacing: 12) {
                PhoneAvatar(name: sender?.displayName ?? "?", tint: AvatarTint.tint(for: sender, own: app.ownAddresses), size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(sender?.displayName ?? "Unknown").font(PhoneFont.bodySemibold).foregroundStyle(theme.inkColor).lineLimit(1)
                        Circle().fill(theme.color(for: app.accountTint(item.summary.account))).frame(width: 6, height: 6)
                        Spacer(minLength: 4)
                        Text(ago).font(PhoneFont.footnote).foregroundStyle(theme.inkFaintColor)
                    }
                    Text(item.summary.subject).font(PhoneFont.secondary).foregroundStyle(theme.inkColor).lineLimit(1)
                    if let quote = item.quote {
                        Text("“\(quote)”").font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor).lineLimit(2).multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reply") { app.requestReply(to: item.summary.key) }
            Button("Open thread") { app.openThread(item.summary.key) }
            Button("Done — no reply needed") { app.mail.dismissNeedsReply(item.summary.key) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Reply") { app.requestReply(to: item.summary.key) }
        .accessibilityAction(named: "Done") { app.mail.dismissNeedsReply(item.summary.key) }
    }

    private var ago: String {
        let minutes = Int(now.timeIntervalSince(item.summary.date) / 60)
        if minutes < 60 { return "\(max(1, minutes)) min" }
        if minutes < 24 * 60 { return "\(minutes / 60) h" }
        return "\(minutes / 1440) d"
    }
}
