import SwiftUI
import ThubanDeskCore

/// Month (board "Calendar · Month"): the month grid with up to three colour dots a day (today filled with the
/// accent), then the agenda from the chosen day on, one card per day. Swipe the grid for the previous / next month.
struct MonthView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let ui = app.calendar.ui
        let zone = app.zone
        let weeks = ui.monthWeeks(ui.focusMonth)
        let first = weeks.first?.first ?? ui.focusDay
        let last = weeks.last?.last ?? ui.focusDay
        let monthEvents = app.calendar.events(from: first.startDate(in: zone), to: last.adding(days: 1).startDate(in: zone))
        ScrollView {
            VStack(spacing: 0) {
                weekdayHeader
                VStack(spacing: 2) {
                    ForEach(weeks, id: \.self) { week in
                        HStack(spacing: 0) {
                            ForEach(week, id: \.self) { day in
                                dayCell(day, events: monthEvents)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
                .gesture(DragGesture(minimumDistance: 24).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 50 else { return }
                    ui.step(value.translation.width < 0 ? 1 : -1)
                })
                Rectangle().fill(theme.lineColor).frame(height: 1)
                MonthAgenda()
                    .padding(.horizontal, PhoneMetrics.gutter)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await app.calendar.refresh() }
    }

    private var weekdayHeader: some View {
        let ui = app.calendar.ui
        return HStack(spacing: 0) {
            ForEach(Weekday.ordered(from: ui.firstWeekday), id: \.self) { day in
                Text(String(day.shortName.prefix(1)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.inkFaintColor)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }

    private func dayCell(_ day: CivilDate, events: [AgendaEvent]) -> some View {
        let ui = app.calendar.ui
        let zone = app.zone
        let inMonth = day.month == ui.focusMonth.month
        let isToday = day == ui.today
        let isFocus = day == ui.focusDay && !isToday
        let tints = events.filter { item in
            let s = CivilDate(item.start(in: zone), in: zone), e = CivilDate(item.end(in: zone).addingTimeInterval(-1), in: zone)
            return s <= day && e >= day
        }.map(\.tint)
        var distinct: [CalendarTint] = []
        for tint in tints where !distinct.contains(tint) { distinct.append(tint) }
        let ink: Color = isToday ? theme.onAccentInk : (!inMonth ? theme.inkFaintColor.opacity(0.6) : (day < ui.today ? theme.inkDimColor : theme.inkColor))
        return Button { ui.focus = day } label: {
            VStack(spacing: 2) {
                Text("\(day.day)")
                    .font(.system(size: 17, weight: isToday ? .bold : .regular))
                    .foregroundStyle(ink)
                    .frame(width: 36, height: 36)
                    .background {
                        if isToday { Circle().fill(theme.accentColor) }
                        else if isFocus { Circle().strokeBorder(theme.accentColor, lineWidth: 1.5) }
                    }
                HStack(spacing: 3) {
                    ForEach(Array(distinct.prefix(3).enumerated()), id: \.offset) { _, tint in
                        Circle().fill(theme.color(for: tint)).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
                .opacity(inMonth ? 1 : 0.5)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(CalendarText.longDay(day)), \(tints.count) event\(tints.count == 1 ? "" : "s")\(isToday ? ", today" : "")")
        .accessibilityAddTraits(day == ui.focusDay ? .isSelected : [])
    }
}

/// "TODAY · THU 24 — 2 left" and the next days with events, each as a card of rows.
struct MonthAgenda: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let ui = app.calendar.ui
        let zone = app.zone
        let now = app.now()
        let start = ui.focusDay
        let items = app.calendar.events(from: start.startDate(in: zone), to: start.adding(days: 14).startDate(in: zone))
        let days = (0..<14).map { start.adding(days: $0) }.compactMap { day -> (CivilDate, [AgendaEvent])? in
            let list = items.filter { item in
                if item.event.isAllDay {
                    return (item.event.start.date ?? day) <= day && (item.event.end.date ?? day.adding(days: 1)) > day
                }
                return CivilDate(item.start(in: zone), in: zone) == day
            }
            .filter { day != ui.today || $0.event.isAllDay || $0.end(in: zone) > now }
            return list.isEmpty && day != start ? nil : (day, list)
        }
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(days.prefix(7)), id: \.0) { day, list in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        let label = "\(day.weekday.shortName) \(day.day)"
                        Eyebrow(day == ui.today ? "Today · \(label)" : label, color: day == ui.today ? theme.brassInkColor : nil)
                        Spacer()
                        Text(countText(day, list)).font(PhoneFont.footnote).foregroundStyle(theme.inkFaintColor)
                    }
                    .padding(.horizontal, 4)
                    InsetCard {
                        if list.isEmpty {
                            Text("Nothing scheduled.").font(PhoneFont.secondary).foregroundStyle(theme.inkDimColor).padding(16)
                        } else {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { RowDivider(inset: 16) }
                                MonthAgendaRow(item: item, now: now)
                            }
                        }
                    }
                }
            }
        }
    }

    private func countText(_ day: CivilDate, _ list: [AgendaEvent]) -> String {
        if day == app.calendar.ui.today { return "\(list.count) left" }
        return "\(list.count) event\(list.count == 1 ? "" : "s")"
    }
}

private struct MonthAgendaRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: AgendaEvent
    var now: Date

    var body: some View {
        let zone = app.zone
        Button { app.calendar.ui.edit(item) } label: {
            HStack(spacing: 12) {
                Text(item.event.isAllDay ? "all-day" : CalendarText.clock(item.start(in: zone), zone: zone))
                    .font(PhoneFont.mono)
                    .foregroundStyle(item.event.isAllDay ? theme.inkDimColor : theme.inkColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 76, alignment: .leading)
                RoundedRectangle(cornerRadius: 2).fill(theme.color(for: item.tint)).frame(width: 3).frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.event.title).font(PhoneFont.bodySemibold).foregroundStyle(theme.inkColor).multilineTextAlignment(.leading)
                    if let detail { Text(detail).font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var detail: String? {
        var parts: [String] = []
        if let location = item.event.location, !location.isEmpty { parts.append(location) }
        if !item.event.isAllDay, item.start(in: app.zone) <= now, item.end(in: app.zone) > now { parts.append("now") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
