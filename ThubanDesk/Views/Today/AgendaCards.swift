import SwiftUI
import ThubanDeskCore

// MARK: - Today's agenda

/// "TODAY · 4 EVENTS  Open week", then rows: 74 pt time column (start / end, mono), a 3 pt calendar bar, title +
/// place (+ guests, + the asking thread's chip), and the status (Done / Now · 65 min left / in 4 h 20 m). Free gaps
/// are a dashed rule; the Now row sits on the accent tint with a progress bar.
struct AgendaCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var model: TodayModel

    var body: some View {
        TodayCard {
            HStack {
                SectionHeader(model.eventCount == 0 ? "Today" : "Today · \(model.eventCount) event\(model.eventCount == 1 ? "" : "s")") {
                    TodayLinkButton(title: "Open week") {
                        app.settings.calendarViewMode = .week
                        app.select(.calendar)
                    }
                }
                .accessibilityLabel("Today, \(model.eventCount) events")
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if model.eventCount == 0 {
                emptyDay
            } else {
                VStack(spacing: 0) {
                    ForEach(model.entries) { entry in
                        row(entry)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: TodayAgenda.Entry) -> some View {
        switch entry {
        case .allDay(let item):
            AgendaRow(item: item, status: nil, question: model.questionsByEvent[item.id], model: model)
        case .event(let item, let status):
            AgendaRow(item: item, status: status, question: model.questionsByEvent[item.id], model: model)
        case .free(let gap):
            FreeGapRow(gap: gap, zone: model.zone)
        case .nowMarker(let date):
            NowMarkerRow(date: date, zone: model.zone)
        }
    }

    private var emptyDay: some View {
        HStack(spacing: 10) {
            Icon(.today, size: 18).foregroundStyle(theme.brassInkColor)
            Text("Nothing on your calendar today.").font(ThubanFont.body(14)).foregroundStyle(theme.inkDimColor)
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 20)
    }
}

private struct AgendaRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: AgendaEvent
    /// nil for all-day events.
    var status: TodayAgenda.Status?
    var question: TodayModel.ReplyItem?
    var model: TodayModel

    private var isDone: Bool { status == .done }
    private var isNow: Bool { if case .now = status { return true } else { return false } }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            timeColumn.frame(width: 74, alignment: .leading)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(theme.color(for: item.tint))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(2)
                if let detail {
                    Text(detail).font(ThubanFont.body(13)).foregroundStyle(theme.inkDimColor).lineLimit(1)
                }
                if let question { questionChip(question) }
                if case .now = status {
                    ProgressTrack(value: TodayLinks.progress(of: item, now: model.now, zone: model.zone))
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            statusView
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(isNow ? theme.accentTintColor : .clear, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        .opacity(isDone ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture { app.openEvent(item) }
        .help("Open in Calendar")
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Open in Calendar") { app.openEvent(item) }
    }

    @ViewBuilder
    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            if item.event.isAllDay {
                Text("all-day").foregroundStyle(theme.inkColor)
            } else {
                Text(TodayLinks.shortClock(item.start(in: model.zone), zone: model.zone)).foregroundStyle(theme.inkColor)
                Text(TodayLinks.clock(item.end(in: model.zone), zone: model.zone)).foregroundStyle(theme.inkFaintColor)
            }
        }
        .font(ThubanFont.mono(13))
    }

    private var detail: String? {
        let parts = [item.event.location.flatMap { $0.isEmpty ? nil : $0 }, TodayLinks.guestLine(of: item.event)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .done:
            HStack(spacing: 5) {
                Icon(.check, size: 12, lineWidth: 2.2)
                Text("Done")
            }
            .font(ThubanFont.body(12.5))
            .foregroundStyle(theme.inkFaintColor)
        case .now(let remaining):
            Chip("Now · \(TodayAgenda.durationText(remaining)) left", kind: .signal)
        case .upcoming(let wait):
            Text("in \(TodayAgenda.durationText(wait))")
                .font(ThubanFont.body(12.5))
                .foregroundStyle(theme.inkDimColor)
        case nil:
            EmptyView()
        }
    }

    private func questionChip(_ reply: TodayModel.ReplyItem) -> some View {
        let name = reply.summary.from?.displayName ?? ""
        let first = name.split(separator: " ").first.map(String.init) ?? name
        let question = reply.verdict.question ?? reply.summary.subject
        return Button { app.openThread(reply.summary.key) } label: {
            HStack(spacing: 6) {
                Icon(.mail, size: 13)
                Text("\(first): “\(question)”").lineLimit(1)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.brassInkColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .help("Open the thread in Mail")
        .accessibilityLabel("\(first) asks: \(question). Open thread")
    }
}

/// 4 pt line track with an accent fill.
private struct ProgressTrack: View {
    @Environment(\.thubanTheme) private var theme
    var value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.lineColor)
                Capsule().fill(theme.accentColor).frame(width: max(4, proxy.size.width * value))
            }
        }
        .frame(height: 4)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// "- - - Free 3:45 – 7:00 PM · 3 h 15 m - - -" aligned under the title column.
private struct FreeGapRow: View {
    @Environment(\.thubanTheme) private var theme
    var gap: DateInterval
    var zone: TimeZone

    var body: some View {
        HStack(spacing: 10) {
            DashedRule()
            Text("Free \(TodayLinks.range(gap.start, gap.end, zone: zone)) · \(TodayAgenda.durationText(gap.duration))")
                .font(ThubanFont.body(13))
                .foregroundStyle(theme.inkFaintColor)
                .fixedSize()
            DashedRule()
        }
        .padding(.leading, 102)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct DashedRule: View {
    @Environment(\.thubanTheme) private var theme
    var body: some View {
        Line()
            .stroke(theme.line2Color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// When nothing is happening: "● Now 2:40 PM ———" in accent, where now falls between entries.
private struct NowMarkerRow: View {
    @Environment(\.thubanTheme) private var theme
    var date: Date
    var zone: TimeZone

    var body: some View {
        HStack(spacing: 8) {
            Text("Now").font(ThubanFont.mono(13, weight: .semibold)).foregroundStyle(theme.brassInkColor)
                .frame(width: 74, alignment: .leading)
            Circle().fill(theme.accentColor).frame(width: 7, height: 7)
            Rectangle().fill(theme.accentColor).frame(height: 1.5)
            Text(TodayLinks.clock(date, zone: zone)).font(ThubanFont.mono(12)).foregroundStyle(theme.brassInkColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now, \(TodayLinks.clock(date, zone: zone))")
    }
}

// MARK: - Tomorrow

/// "TOMORROW · FRI, SEP 25": 34 pt rows — time (mono) · calendar dot · title · "Not answered" for invitations.
struct TomorrowCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var model: TodayModel
    private let limit = 7

    var body: some View {
        TodayCard {
            SectionHeader("Tomorrow · \(Self.header(model.today.adding(days: 1)))")
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 6)
            VStack(spacing: 0) {
                if model.tomorrow.isEmpty {
                    Text("Nothing scheduled yet.")
                        .font(ThubanFont.body(14))
                        .foregroundStyle(theme.inkDimColor)
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        .padding(.horizontal, 18)
                }
                ForEach(model.tomorrow.prefix(limit)) { item in
                    row(item)
                }
                if model.tomorrow.count > limit {
                    TodayLinkButton(title: "\(model.tomorrow.count - limit) more in Calendar") {
                        app.settings.calendarViewMode = .day
                        app.select(.calendar)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .padding(.horizontal, 18)
                }
            }
            .padding(.bottom, 10)
        }
    }

    private func row(_ item: AgendaEvent) -> some View {
        HStack(spacing: 10) {
            Text(item.event.isAllDay ? "all-day" : TodayLinks.shortClock(item.start(in: model.zone), zone: model.zone))
                .font(ThubanFont.mono(12.5))
                .foregroundStyle(theme.inkDimColor)
                .frame(width: 64, alignment: .leading)
            TintDot(tint: item.tint)
            Text(item.event.title)
                .font(ThubanFont.body(14, weight: .medium))
                .foregroundStyle(theme.inkColor)
                .lineLimit(1)
            Spacer(minLength: 8)
            if item.event.needsResponse {
                Chip("Not answered", kind: .neg)
            } else if let due = TodayLinks.dueTime(of: item.event) {
                // A deadline's due time (from its description, as Canvas feeds write it); none otherwise.
                Text(due)
                    .font(ThubanFont.body(12.5))
                    .foregroundStyle(theme.inkDimColor)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 34)
        .contentShape(Rectangle())
        .onTapGesture { app.openEvent(item) }
        .help("Open in Calendar")
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Open in Calendar") { app.openEvent(item) }
    }

    /// "Fri, Sep 25".
    static func header(_ day: CivilDate) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(day.weekday.shortName), \(months[day.month - 1]) \(day.day)"
    }
}
