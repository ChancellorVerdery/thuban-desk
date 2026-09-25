import SwiftUI
import ThubanDeskCore

/// PLACEHOLDER — owned by the Calendar engineer (see ARCHITECTURE.md). Replace with the design's Week / Month / Day
/// views, sidebar (mini month, calendars by account, invitations), event popover, editor and recurring-scope sheet.
/// It currently lists this week's events so the data path is visible in smoke.
struct CalendarAreaView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let week = weekRange
        let events = app.calendar.events(from: week.start, to: week.end)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageTitle(title: "Calendar", subtitle: "\(events.count) events this week across \(app.calendar.visibleCalendars.count) calendars · Week, Month and Day views land here.")
                HStack(spacing: 14) {
                    ForEach(app.calendar.calendars) { ref in
                        HStack(spacing: 6) {
                            TintDot(tint: ref.tint)
                            Text(ref.name).font(ThubanFont.body(13)).foregroundStyle(ref.isHidden ? theme.inkFaintColor : theme.inkColor)
                        }
                    }
                }
                ForEach(events) { item in
                    HStack(spacing: 10) {
                        TintDot(tint: item.tint)
                        Text(item.event.isAllDay ? "all-day" : DeskFormat.time(item.event.startDate(in: app.zone), zone: app.zone))
                            .font(ThubanFont.mono(12)).foregroundStyle(theme.inkDimColor).frame(width: 70, alignment: .leading)
                        Text(item.event.title).font(ThubanFont.body(14)).foregroundStyle(theme.inkColor)
                        Spacer()
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: week.start) {
            app.calendar.visibleRange = week
            await app.calendar.ensureEvents(from: week.start, to: week.end)
        }
    }

    private var weekRange: DateInterval {
        let today = CivilDate(app.now(), in: app.zone)
        let sunday = today.adding(days: -(today.weekday.calendarWeekday - 1))
        return DateInterval(start: sunday.startDate(in: app.zone), end: sunday.adding(days: 7).startDate(in: app.zone))
    }
}
