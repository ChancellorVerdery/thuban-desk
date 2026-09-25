import SwiftUI
import ThubanDeskCore

/// PLACEHOLDER — owned by the Today + Settings engineer (see ARCHITECTURE.md). Replace with the design's agenda
/// (Done / Now / Free gaps / upcoming), tomorrow strip, "Needs a reply" cards and the invitation card.
struct TodayAreaView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let now = app.now()
        let today = CivilDate(now, in: app.zone)
        let entries = TodayAgenda.build(events: app.calendar.events(from: today.startDate(in: app.zone), to: today.adding(days: 1).startDate(in: app.zone)),
                                        day: today, now: now, zone: app.zone)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(title: "Today", subtitle: "\(entries.count) agenda entries · \(app.mail.needsReplyThreads.count) threads need a reply · \(app.calendar.pendingInvitations.count) invitations")
                ForEach(entries) { entry in
                    Text(describe(entry)).font(ThubanFont.body(14)).foregroundStyle(theme.inkColor)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            let day = today.startDate(in: app.zone)
            await app.calendar.ensureEvents(from: day, to: today.adding(days: 2).startDate(in: app.zone))
        }
    }

    private func describe(_ entry: TodayAgenda.Entry) -> String {
        switch entry {
        case .allDay(let item): return "all-day · \(item.event.title)"
        case .event(let item, let status):
            switch status {
            case .done: return "\(DeskFormat.time(item.event.startDate(in: app.zone), zone: app.zone)) · \(item.event.title) · Done"
            case .now(let left): return "\(DeskFormat.time(item.event.startDate(in: app.zone), zone: app.zone)) · \(item.event.title) · Now · \(TodayAgenda.durationText(left)) left"
            case .upcoming(let wait): return "\(DeskFormat.time(item.event.startDate(in: app.zone), zone: app.zone)) · \(item.event.title) · in \(TodayAgenda.durationText(wait))"
            }
        case .free(let gap): return "Free \(DeskFormat.time(gap.start, zone: app.zone)) – \(DeskFormat.time(gap.end, zone: app.zone)) · \(TodayAgenda.durationText(gap.duration))"
        case .nowMarker(let date): return "Now · \(DeskFormat.time(date, zone: app.zone))"
        }
    }
}
