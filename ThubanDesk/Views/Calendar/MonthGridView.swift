import SwiftUI
import ThubanDeskCore

/// Month (design: Month.dc.html): weekday header, 5–6 week rows; each day lists all-day chips then timed events
/// (dot · "10:10am" · title), "+N more" opens the day. Click a date to open its day.
struct MonthGridView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var weeks: [[CivilDate]]
    var month: YearMonth

    var body: some View {
        // Re-evaluated every minute so "today" moves at midnight.
        TimelineView(.everyMinute) { _ in grid }
    }

    private var grid: some View {
        let ui = app.calendar.ui
        let zone = app.zone
        let first = weeks.first?.first ?? month.firstDay
        let last = weeks.last?.last ?? month.firstDay
        let items = ui.events(from: first.startDate(in: zone), to: last.adding(days: 1).startDate(in: zone))
        let byDay = group(items)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Weekday.ordered(from: ui.firstWeekday), id: \.self) { day in
                    Text(day.shortName.uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .kerning(0.96)
                        .foregroundStyle(theme.inkDimColor)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .thubanHairline(.trailing, color: theme.lineColor)
                }
            }
            .frame(height: 34)
            .background(theme.panelColor)
            .thubanHairline(.bottom, color: theme.line2Color)
            GeometryReader { geo in
                let rowH = geo.size.height / CGFloat(max(1, weeks.count))
                VStack(spacing: 0) {
                    ForEach(weeks, id: \.self) { week in
                        HStack(spacing: 0) {
                            ForEach(week, id: \.self) { day in
                                MonthDayCell(day: day, month: month, items: byDay[day] ?? [], height: rowH)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: rowH)
                    }
                }
            }
        }
        .background(theme.panelColor)
    }

    /// Items per day: all-day ones on every day they cover (first), then timed ones by start.
    private func group(_ items: [AgendaEvent]) -> [CivilDate: [AgendaEvent]] {
        let zone = app.zone
        var result: [CivilDate: [AgendaEvent]] = [:]
        for item in items {
            let event = item.event
            let startDay = event.start.civilDate(in: zone)
            let lastDay: CivilDate
            if event.isAllDay {
                lastDay = max(startDay, event.end.civilDate(in: zone).adding(days: -1))
            } else {
                lastDay = max(startDay, CivilDate(event.endDate(in: zone).addingTimeInterval(-1), in: zone))
            }
            var day = startDay
            var guardCount = 0
            while day <= lastDay, guardCount < 62 {
                result[day, default: []].append(item)
                day = day.adding(days: 1)
                guardCount += 1
            }
        }
        for key in result.keys {
            result[key]?.sort { a, b in
                let aBar = a.event.isAllDay, bBar = b.event.isAllDay
                if aBar != bBar { return aBar }
                return a.event.startDate(in: zone) < b.event.startDate(in: zone)
            }
        }
        return result
    }
}

private struct MonthDayCell: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var day: CivilDate
    var month: YearMonth
    var items: [AgendaEvent]
    var height: CGFloat

    var body: some View {
        let ui = app.calendar.ui
        let isToday = day == ui.today
        let inMonth = day.month == month.month && day.year == month.year
        let weekend = day.weekday == .saturday || day.weekday == .sunday
        let capacity = max(1, Int((height - 50) / 22))
        let shown = items.count <= capacity ? items : Array(items.prefix(capacity - 1))
        let more = items.count - shown.count
        VStack(alignment: .leading, spacing: 2) {
            Button {
                ui.show(day, mode: .day)
            } label: {
                Group {
                    if isToday {
                        Text("\(day.day)")
                            .font(ThubanFont.display(15, weight: .bold))
                            .foregroundStyle(theme.onAccentColor)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(theme.accentColor))
                    } else {
                        Text(day.day == 1 ? CalendarText.shortDate(day) : "\(day.day)")
                            .font(ThubanFont.display(15))
                            .foregroundStyle(inMonth ? theme.inkColor : theme.inkFaintColor)
                            .padding(.horizontal, 2)
                            .frame(minWidth: 26, alignment: .leading)
                    }
                }
                // Same height with or without today's circle, so every cell's list starts at the same y.
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(CalendarText.longDay(day) + (items.isEmpty ? "" : ", \(items.count) events"))
            .help("Show this day")
            ForEach(shown) { item in
                MonthItemRow(item: item, day: day)
            }
            if more > 0 {
                Button("+\(more) more") { ui.show(day, mode: .day) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.brassInkColor)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .accessibilityLabel("\(more) more events on \(CalendarText.longDay(day))")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(inMonth ? 1 : 0.6)
        .calendarDayGround(isToday: isToday, isWeekend: weekend, theme: theme, base: theme.panelColor)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { ui.newEvent(on: day) }
        .onTapGesture { ui.closePopover() }
        .thubanHairline(.trailing, color: theme.lineColor)
        .thubanHairline(.bottom, color: theme.lineColor)
        .clipped()
    }
}

/// One line in a month cell: an all-day chip, or dot · time · title (dashed when unanswered).
private struct MonthItemRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: AgendaEvent
    var day: CivilDate

    var body: some View {
        let ui = app.calendar.ui
        let zone = app.zone
        let event = item.event
        if event.isAllDay {
            AllDayChip(item: item, isPast: false, height: 20, radius: 5)
                .frame(height: 20)
        } else {
            let tentative = event.needsResponse
            Button {
                ui.select(item)
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(theme.color(for: item.tint)).frame(width: 7, height: 7)
                    Text(event.start.civilDate(in: zone) == day ? CalendarText.compactTime(event.startDate(in: zone), zone: zone) : "cont.")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(theme.inkDimColor)
                    Text(event.title)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5)
                .frame(height: 20)
                .background {
                    if ui.selectedID == item.id {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(theme.softColor(for: item.tint))
                    }
                }
                .overlay {
                    if tentative {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(theme.color(for: item.tint), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .anchorPreference(key: SelectedEventAnchorKey.self, value: .bounds) { ui.selectedID == item.id ? $0 : nil }
            .accessibilityLabel("\(event.title), \(CalendarText.clock(event.startDate(in: zone), zone: zone))")
            .help(event.title)
        }
    }
}
