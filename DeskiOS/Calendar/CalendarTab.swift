import SwiftUI
import ThubanDeskCore

/// Calendar (boards "Calendar · Day" and "Calendar · Month"): Today pill, Calendars + New event, "September 2026",
/// Day / 3 Days / Month, then the week strip + time grid with the now line, or the month grid + agenda by day.
/// Tapping an event opens the editor sheet (shared `CalendarUIState`: editor, repeating-event scopes, delete).
struct CalendarTab: View {
    var body: some View {
        NavigationStack {
            CalendarScreen()
        }
    }
}

struct CalendarScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        @Bindable var router = router
        let ui = app.calendar.ui
        let focus = ui.focusDay
        VStack(spacing: 0) {
            navRow
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(CalendarText.monthName(focus.month)).font(PhoneFont.largeTitle).foregroundStyle(theme.inkColor)
                    .accessibilityAddTraits(.isHeader)
                Text(String(focus.year)).font(PhoneFont.display(.title2)).foregroundStyle(theme.inkFaintColor)
                Spacer()
            }
            .padding(.horizontal, PhoneMetrics.gutter)
            .padding(.top, 2)
            .padding(.bottom, 8)
            PhoneSegmented(options: PhoneCalendarMode.allCases.map { ($0, $0.title) }, selection: $router.calendarMode, accessibilityName: "Calendar view")
                .padding(.horizontal, PhoneMetrics.gutter)
                .padding(.bottom, 8)
            if let error = ui.errorMessage {
                PhoneBanner(text: error) { ui.errorMessage = nil }.padding(.horizontal, PhoneMetrics.gutter).padding(.bottom, 6)
            }
            switch router.calendarMode {
            case .day, .threeDays:
                WeekStrip()
                TimeGridView(dayCount: router.calendarMode.dayCount)
            case .month:
                MonthView()
            }
        }
        .background(theme.bgColor.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: rangeKey) { await load() }
    }

    private var navRow: some View {
        HStack(spacing: 4) {
            Button { app.calendar.ui.goToday() } label: {
                Text("Today")
                    .font(PhoneFont.secondarySemibold)
                    .foregroundStyle(theme.inkColor)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                    .frame(minHeight: PhoneMetrics.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            Spacer()
            NavIconButton(.listDots, label: "Calendars") { router.showCalendars = true }
            NavIconButton(.plus, label: "New event") { app.requestNewEvent(on: app.calendar.ui.focusDay) }
        }
        .padding(.horizontal, 8)
        .frame(height: PhoneMetrics.navHeight)
    }

    /// The loaded span: the focus week (± a few days) or the month grid.
    private var range: DateInterval {
        let ui = app.calendar.ui
        let zone = app.zone
        switch router.calendarMode {
        case .month:
            let weeks = ui.monthWeeks(ui.focusMonth).flatMap { $0 }
            let first = weeks.first ?? ui.focusDay, last = (weeks.last ?? ui.focusDay).adding(days: 21)
            return DateInterval(start: first.startDate(in: zone), end: last.startDate(in: zone))
        default:
            let start = ui.weekStart(of: ui.focusDay)
            return DateInterval(start: start.startDate(in: zone), end: start.adding(days: 10).startDate(in: zone))
        }
    }

    private var rangeKey: String { "\(router.calendarMode.rawValue)|\(range.start.timeIntervalSince1970)|\(app.accounts.count)" }

    private func load() async {
        app.calendar.visibleRange = range
        await app.calendar.ensureEvents(from: range.start, to: range.end)
    }
}

// MARK: - Week strip

/// S M T W T F S with the day numbers (today filled with the accent, the focused day ringed) and one dot per day in
/// the first event's colour. Swipe for the previous / next week.
struct WeekStrip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let ui = app.calendar.ui
        let start = ui.weekStart(of: ui.focusDay)
        let days = (0..<7).map { start.adding(days: $0) }
        let zone = app.zone
        let events = app.calendar.events(from: start.startDate(in: zone), to: start.adding(days: 7).startDate(in: zone))
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isToday = day == ui.today
                let isFocus = day == ui.focusDay
                let dot = events.first { item in
                    let s = CivilDate(item.start(in: zone), in: zone), e = CivilDate(item.end(in: zone).addingTimeInterval(-1), in: zone)
                    return s <= day && e >= day
                }?.tint
                Button { ui.focus = day } label: {
                    VStack(spacing: 3) {
                        Text(String(day.weekday.shortName.prefix(1)))
                            .font(.system(size: 11, weight: isToday ? .bold : .semibold))
                            .foregroundStyle(isToday ? theme.brassInkColor : theme.inkFaintColor)
                        Text("\(day.day)")
                            .font(.system(size: 17, weight: isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? theme.onAccentInk : (day < ui.today ? theme.inkDimColor : theme.inkColor))
                            .frame(width: 36, height: 36)
                            .background {
                                if isToday { Circle().fill(theme.accentColor) }
                                else if isFocus { Circle().strokeBorder(theme.accentColor, lineWidth: 1.5) }
                            }
                        Circle().fill(dot.map { theme.color(for: $0) } ?? .clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CalendarText.longDay(day) + (isToday ? ", today" : ""))
                .accessibilityAddTraits(isFocus ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .gesture(DragGesture(minimumDistance: 24).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 40 else { return }
            ui.focus = ui.focusDay.adding(days: value.translation.width < 0 ? 7 : -7)
        })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Week")
    }
}

// MARK: - Time grid

/// Day / 3 Days: a panel header with the day (and "4 events · Eastern"), all-day events, then 24 hours at 48 pt with
/// hairlines, event blocks in soft tint with a 3 pt bar, and the brass now line with its "2:40" label.
struct TimeGridView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var dayCount: Int

    static let hourHeight: CGFloat = 48
    static let labelWidth: CGFloat = 56

    var body: some View {
        let ui = app.calendar.ui
        let zone = app.zone
        let days = (0..<dayCount).map { ui.focusDay.adding(days: $0) }
        let start = days[0].startDate(in: zone), end = days[days.count - 1].adding(days: 1).startDate(in: zone)
        let items = app.calendar.events(from: start, to: end)
        let allDay = items.filter { $0.event.isAllDay }
        let timed = items.filter { !$0.event.isAllDay }
        VStack(spacing: 0) {
            header(days: days, count: items.count, allDay: allDay)
            ScrollViewReader { proxy in
                ScrollView {
                    grid(days: days, timed: timed)
                        .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .onAppear { scrollToNow(proxy) }
                .onChange(of: ui.scrollRequest) { _, _ in scrollToNow(proxy) }
                .refreshable { await app.calendar.refresh() }
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 1.5, abs(value.translation.width) > 60 else { return }
            ui.focus = ui.focusDay.adding(days: (value.translation.width < 0 ? 1 : -1) * dayCount)
        })
    }

    /// Shows the now line about a third of the way down (the board: 10 AM at the top at 2:40 PM).
    private func scrollToNow(_ proxy: ScrollViewProxy) {
        let minutes = EventLayout.minutes(of: app.now(), from: app.calendar.ui.today, zone: app.zone)
        let hour = max(0, min(16, Int(minutes / 60) - 4))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { proxy.scrollTo("hour-\(hour)", anchor: .top) }
    }

    @ViewBuilder private func header(days: [CivilDate], count: Int, allDay: [AgendaEvent]) -> some View {
        let ui = app.calendar.ui
        VStack(spacing: 0) {
            if days.count == 1 {
                HStack(spacing: 10) {
                    Text(CalendarText.longDay(days[0])).font(PhoneFont.secondarySemibold).foregroundStyle(theme.inkColor)
                    Spacer()
                    Text("\(count) event\(count == 1 ? "" : "s") · \(zoneName)").font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
            } else {
                HStack(spacing: 0) {
                    Text(zoneAbbreviation).font(.caption2).foregroundStyle(theme.inkFaintColor).frame(width: Self.labelWidth + 4)
                    ForEach(days, id: \.self) { day in
                        let isToday = day == ui.today
                        HStack(spacing: 4) {
                            Text(day.weekday.shortName).font(PhoneFont.footnote).foregroundStyle(isToday ? theme.brassInkColor : theme.inkDimColor)
                            Text("\(day.day)").font(PhoneFont.secondarySemibold)
                                .foregroundStyle(isToday ? theme.onAccentInk : theme.inkColor)
                                .padding(.horizontal, isToday ? 6 : 0)
                                .background { if isToday { Capsule().fill(theme.accentColor) } }
                        }
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.trailing, 16)
            }
            if !allDay.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(allDay) { item in
                        Button { ui.edit(item) } label: {
                            HStack(spacing: 6) {
                                Text("all-day").font(.caption2.weight(.semibold)).foregroundStyle(theme.inkDimColor)
                                Text(item.event.title).font(PhoneFont.footnoteSemibold).foregroundStyle(theme.textColor(for: item.tint)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .frame(minHeight: 26)
                            .background(theme.softColor(for: item.tint), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, Self.labelWidth + 4)
                .padding(.trailing, 16)
                .padding(.bottom, 8)
            }
        }
        .background(theme.panelColor)
        .overlay(alignment: .top) { Rectangle().fill(theme.lineColor).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.lineColor).frame(height: 1) }
    }

    private var zoneName: String {
        let name = app.zone.localizedName(for: .generic, locale: Locale(identifier: "en_US")) ?? app.zone.identifier
        return name.replacingOccurrences(of: " Time", with: "")
    }

    private var zoneAbbreviation: String { app.zone.abbreviation(for: app.now()) ?? "" }

    private func grid(days: [CivilDate], timed: [AgendaEvent]) -> some View {
        let ui = app.calendar.ui
        let zone = app.zone
        let now = app.now()
        let height = Self.hourHeight * 24
        return GeometryReader { geo in
            let columnsWidth = geo.size.width - Self.labelWidth - 4 - 16
            let columnWidth = columnsWidth / CGFloat(days.count)
            ZStack(alignment: .topLeading) {
                // Hour rows (laid out, not offset, so ScrollViewReader can scroll to them) with their lines and labels.
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        ZStack(alignment: .topLeading) {
                            Rectangle().fill(theme.lineColor).frame(width: columnsWidth, height: 1)
                                .offset(x: Self.labelWidth + 4)
                            Text(hour == 12 ? "Noon" : CalendarText.hourLabel(hour))
                                .font(.caption2)
                                .foregroundStyle(theme.inkFaintColor)
                                .frame(width: Self.labelWidth - 4, alignment: .trailing)
                                .offset(y: -7)
                                .opacity(hour == 0 ? 0 : 1)
                                .accessibilityHidden(true)
                        }
                        .frame(width: geo.size.width, height: Self.hourHeight, alignment: .topLeading)
                    }
                }
                // Day separators (3 Days).
                if days.count > 1 {
                    ForEach(1..<days.count, id: \.self) { index in
                        Rectangle().fill(theme.lineColor).frame(width: 1, height: height)
                            .offset(x: Self.labelWidth + 4 + columnWidth * CGFloat(index))
                    }
                }
                // Events.
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    let dayItems = timed.filter { item in
                        item.start(in: zone) < day.adding(days: 1).startDate(in: zone) && item.end(in: zone) > day.startDate(in: zone)
                    }
                    let spans = dayItems.map { item -> (start: Double, end: Double) in
                        (max(0, EventLayout.minutes(of: item.start(in: zone), from: day, zone: zone)),
                         min(1440, EventLayout.minutes(of: item.end(in: zone), from: day, zone: zone)))
                    }
                    let slots = EventLayout.columns(spans, minimumLength: 30)
                    ForEach(Array(dayItems.enumerated()), id: \.element.id) { i, item in
                        let span = spans[i]
                        let slot = slots[i]
                        let x = Self.labelWidth + 4 + columnWidth * CGFloat(index) + columnWidth * slot.fraction.x
                        let w = columnWidth * slot.fraction.width - (slot.fraction.x + slot.fraction.width < 0.999 ? 2 : 0)
                        let y = CGFloat(span.start) / 60 * Self.hourHeight + 1
                        let h = max(22, CGFloat(span.end - span.start) / 60 * Self.hourHeight - 2)
                        EventBlock(item: item, compact: days.count > 1 || h < 44, isPast: item.end(in: zone) <= now)
                            .frame(width: max(10, w), height: h)
                            .offset(x: x, y: y)
                            .onTapGesture { ui.edit(item) }
                    }
                }
                // Now line.
                if let todayIndex = days.firstIndex(of: ui.today) {
                    let minutes = EventLayout.minutes(of: now, from: ui.today, zone: zone)
                    let y = CGFloat(minutes) / 60 * Self.hourHeight
                    NowLine(label: CalendarText.clock(now, zone: zone, suffix: false),
                            lineStart: Self.labelWidth + 4 + (days.count > 1 ? columnWidth * CGFloat(todayIndex) : 0),
                            lineWidth: days.count > 1 ? columnWidth : columnsWidth)
                        .offset(y: y - 6)
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .topLeading)
            .padding(.top, Self.topInset)
            .background(alignment: .topLeading) {
                // Scroll anchors 12 pt above each hour line, so the hour's label is not cut off at the top.
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in Color.clear.frame(height: Self.hourHeight).id("hour-\(hour)") }
                }
            }
        }
        .frame(height: height + Self.topInset)
    }

    static let topInset: CGFloat = 12
}

private struct NowLine: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    var lineStart: CGFloat
    var lineWidth: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Text(label)
                .font(PhoneFont.monoSmall)
                .foregroundStyle(theme.brassInkColor)
                .frame(width: TimeGridView.labelWidth - 4, alignment: .trailing)
                .background(theme.bgColor)
            HStack(spacing: 0) {
                Circle().fill(theme.brassInkColor).frame(width: 8, height: 8).offset(x: -4)
                Rectangle().fill(theme.brassInkColor).frame(width: lineWidth, height: 2).offset(x: -4)
            }
            .offset(x: lineStart)
        }
        .frame(height: 12)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now, \(label)")
    }
}

/// A timed event: soft tint ground, 3 pt bar, title + time · place in the tint's text colour.
struct EventBlock: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: AgendaEvent
    var compact: Bool
    var isPast: Bool

    var body: some View {
        let zone = app.zone
        let ink = theme.textColor(for: item.tint)
        HStack(spacing: 0) {
            Rectangle().fill(theme.color(for: item.tint)).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.event.title).font(compact ? PhoneFont.footnoteSemibold : PhoneFont.secondarySemibold).lineLimit(compact ? 2 : 1)
                Text(detail(zone)).font(compact ? .caption2 : PhoneFont.footnote).lineLimit(1)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, compact ? 6 : 10)
            .padding(.vertical, compact ? 3 : 6)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.softColor(for: item.tint))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(isPast ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the event")
    }

    private func detail(_ zone: TimeZone) -> String {
        let range = CalendarText.timeRange(item.start(in: zone), item.end(in: zone), zone: zone)
        if compact { return range }
        if let location = item.event.location, !location.isEmpty { return "\(range) · \(location)" }
        return range
    }
}
