import SwiftUI
import ThubanDeskCore

// MARK: - Needs a reply

/// "NEEDS A REPLY · 3  Open Mail", then one row per thread: avatar, sender + account tag + age, subject, the asking
/// sentence on an accent rule, the calendar link line, and Reply (primary on the first) · Open thread · Done.
struct NeedsReplyCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var model: TodayModel

    var body: some View {
        TodayCard {
            SectionHeader("Needs a reply", count: model.replies.count) {
                TodayLinkButton(title: "Open Mail") {
                    app.mail.filter = .needsReply
                    app.select(.mail)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if model.replies.isEmpty {
                Hairline()
                HStack(spacing: 10) {
                    Icon(.check, size: 16).foregroundStyle(theme.posTextColor)
                    Text(app.isSyncing ? "Checking your inboxes…" : "You’re caught up. Nobody is waiting on you.")
                        .font(ThubanFont.body(14))
                        .foregroundStyle(theme.inkDimColor)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            } else {
                ForEach(Array(model.replies.enumerated()), id: \.element.id) { index, item in
                    Hairline()
                    NeedsReplyRow(item: item, isFirst: index == 0, model: model)
                }
            }
        }
    }
}

private struct NeedsReplyRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: TodayModel.ReplyItem
    var isFirst: Bool
    var model: TodayModel

    private var sender: EmailAddress? { item.summary.from }
    private var name: String { sender?.displayName ?? "Unknown sender" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(name: name, tint: PersonTint.tint(for: sender?.email ?? name), size: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(name).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(theme.inkColor).lineLimit(1)
                    HStack(spacing: 4) {
                        TintDot(tint: app.accountTint(item.summary.account), size: 6)
                        Text(item.summary.accountDomain)
                    }
                    .font(ThubanFont.body(12))
                    .foregroundStyle(theme.inkFaintColor)
                    .help("Arrived in \(item.summary.account)")
                    Spacer(minLength: 8)
                    Text(TodayLinks.age(item.summary.date, now: model.now, zone: model.zone))
                        .font(ThubanFont.body(12.5))
                        .foregroundStyle(theme.inkDimColor)
                }
                Text(item.summary.subject.isEmpty ? "(No subject)" : item.summary.subject)
                    .font(ThubanFont.body(14, weight: .medium))
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(1)
                if let question = item.quote {
                    Text(question)
                        .font(ThubanFont.body(13.5))
                        .foregroundStyle(theme.inkColor)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(theme.accentColor).frame(width: 2)
                        }
                }
                if let link = item.link {
                    HStack(spacing: 6) {
                        Icon(.calendar, size: 12)
                        Text(TodayLinks.phrase(for: link, now: model.now, zone: model.zone)).lineLimit(1)
                    }
                    .font(ThubanFont.body(12.5))
                    .foregroundStyle(theme.inkDimColor)
                }
                actions.padding(.top, 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button { app.requestReply(to: item.summary.key) } label: {
                HStack(spacing: 7) { Icon(.reply, size: 15); Text("Reply") }
            }
            .modifier(ReplyButtonStyle(primary: isFirst))
            .help("Reply from \(item.summary.account)")
            Button("Open thread") { app.openThread(item.summary.key) }
                .buttonStyle(GhostButtonStyle(height: 30))
            Spacer(minLength: 0)
            Button {
                let key = item.summary.key
                app.mail.dismissNeedsReply(key)
                Task { await app.mail.perform(.archive, on: [key]) }
            } label: {
                HStack(spacing: 7) { Icon(.check, size: 15); Text("Done") }
            }
            .buttonStyle(GhostButtonStyle(height: 30))
            .help("Mark handled and archive")
            .accessibilityLabel("Mark handled and archive")
        }
    }
}

private struct ReplyButtonStyle: ViewModifier {
    var primary: Bool

    func body(content: Content) -> some View {
        if primary {
            content.buttonStyle(PrimaryButtonStyle(height: 30))
        } else {
            content.buttonStyle(SecondaryButtonStyle(height: 30))
        }
    }
}

// MARK: - Invitations

/// Pending invitations: a date tile (weekday in the loss colour, serif day), "INVITATION", the title, "3:00 – 3:45 PM ·
/// Zoom · from Priya Shah · no conflicts", and a Yes / Maybe / No control. Answered ones stay until the next launch
/// showing the answer, so the click has visible effect.
struct InvitationsCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var model: TodayModel
    @State private var answered: [String: (item: AgendaEvent, status: ResponseStatus)] = [:]
    @State private var busy: String?
    @State private var error: String?

    private var rows: [(item: AgendaEvent, status: ResponseStatus?)] {
        var list: [(AgendaEvent, ResponseStatus?)] = model.invitations.map { ($0, answered[$0.id]?.status) }
        let pending = Set(model.invitations.map(\.id))
        list += answered.values.filter { !pending.contains($0.item.id) }.map { ($0.item, $0.status) }
        return list.sorted { $0.0.start(in: model.zone) < $1.0.start(in: model.zone) }.map { (item: $0.0, status: $0.1) }
    }

    var body: some View {
        let rows = self.rows
        if !rows.isEmpty {
            TodayCard {
                ForEach(Array(rows.enumerated()), id: \.element.item.id) { index, row in
                    if index > 0 { Hairline() }
                    invitationRow(row.item, status: row.status, isFirst: index == 0, count: rows.count)
                }
                if let error {
                    Hairline()
                    SettingsNote(text: error, tone: .negative).padding(.horizontal, 18).padding(.vertical, 10)
                }
            }
        }
    }

    private func invitationRow(_ item: AgendaEvent, status: ResponseStatus?, isFirst: Bool, count: Int) -> some View {
        let start = item.start(in: model.zone)
        let day = CivilDate(start, in: model.zone)
        return HStack(spacing: 14) {
            VStack(spacing: 1) {
                Text(day.weekday.shortName.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.84)
                    .foregroundStyle(theme.negTextColor)
                Text(String(day.day))
                    .font(ThubanFont.display(20))
                    .foregroundStyle(theme.inkColor)
            }
            .frame(width: 46, height: 50)
            .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(isFirst && count > 1 ? "Invitations · \(count)" : "Invitation")
                Text(item.event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(1)
                Text(detail(item))
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RSVPControl(selection: status, isBusy: busy == item.id) { choice in
                Task { await answer(item, choice) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .accessibilityElement(children: .contain)
    }

    private func detail(_ item: AgendaEvent) -> String {
        var parts: [String] = []
        let start = item.start(in: model.zone)
        if item.event.isAllDay {
            parts.append("All day")
        } else {
            let sameDay = CivilDate(start, in: model.zone) == model.today.adding(days: 1) || CivilDate(start, in: model.zone) == model.today
            let range = TodayLinks.range(start, item.end(in: model.zone), zone: model.zone)
            parts.append(sameDay ? range : "\(TodayToolbarDate.medium(CivilDate(start, in: model.zone))) · \(range)")
        }
        if let location = item.event.location, !location.isEmpty { parts.append(location) }
        if let inviter = TodayLinks.inviter(of: item.event) { parts.append("from \(inviter)") }
        let conflicts = TodayLinks.conflicts(of: item, among: model.nearby, zone: model.zone)
        if !item.event.isAllDay {
            parts.append(conflicts.isEmpty ? "no conflicts" : "overlaps \(TodayLinks.shortTitle(conflicts[0].event.title))\(conflicts.count > 1 ? " +\(conflicts.count - 1)" : "")")
        }
        return parts.joined(separator: " · ")
    }

    private func answer(_ item: AgendaEvent, _ status: ResponseStatus) async {
        busy = item.id
        error = nil
        defer { busy = nil }
        do {
            try await app.calendar.rsvp(status, to: item.event, in: item.calendar)
            answered[item.id] = (item, status)
        } catch {
            self.error = "Couldn’t answer “\(item.event.title)”: \(error.localizedDescription)"
        }
    }
}

enum TodayToolbarDate {
    /// "Mon, Sep 28".
    static func medium(_ day: CivilDate) -> String { TomorrowCard.header(day) }
}

/// Yes / Maybe / No on a panel2 track (radius 9, padding 3); the chosen answer is a panel segment.
struct RSVPControl: View {
    @Environment(\.thubanTheme) private var theme
    var selection: ResponseStatus?
    var isBusy: Bool
    var choose: (ResponseStatus) -> Void

    private let options: [(ResponseStatus, String)] = [(.accepted, "Yes"), (.tentative, "Maybe"), (.declined, "No")]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { status, label in
                let active = selection == status
                Button { choose(status) } label: {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(active ? (status == .declined ? theme.negTextColor : theme.inkColor) : theme.inkColor)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(active ? theme.panelColor : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(active ? theme.line2Color : .clear, lineWidth: ThubanMetrics.hairline))
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityLabel("RSVP \(label)")
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .opacity(isBusy ? 0.6 : 1)
        .overlay { if isBusy { ProgressView().controlSize(.small) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("RSVP")
        .fixedSize()
    }
}
