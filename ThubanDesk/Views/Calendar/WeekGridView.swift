import SwiftUI
import ThubanDeskCore

/// Marks the event whose popover is open, so the area can place the popover beside it.
struct SelectedEventAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

/// Week and Day grids (design: Main): day headers, the all-day row, and a scrolling 24-hour grid (50 pt an hour,
/// opens at 7 AM) with overlapping events side by side, the current-time line, past events dimmed. Drag an event
/// to move it (15-minute steps, across days), drag its bottom edge to resize, drag on empty space to create one.
struct WeekGridView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var days: [CivilDate]

    @State private var drag: GridDrag?
    @State private var create: CreateDrag?

    private let hh = CalendarMetrics.hourHeight
    private let gutter = CalendarMetrics.gutter

    var body: some View {
        let ui = app.calendar.ui
        let zone = app.zone
        let first = days.first ?? ui.focusDay
        let last = days.last ?? ui.focusDay
        let items = ui.events(from: first.startDate(in: zone), to: last.adding(days: 1).startDate(in: zone))
        let bars = allDayBars(items)
        GeometryReader { geo in
            let colW = max(40, (geo.size.width - gutter) / CGFloat(max(1, days.count)))
            VStack(spacing: 0) {
                header(colW: colW)
                allDayRow(bars: bars, colW: colW)
                timeGrid(items: items, colW: colW, width: geo.size.width)
            }
        }
        .background(theme.bgColor)
    }

    // MARK: Header

    private func header(colW: CGFloat) -> some View {
        let ui = app.calendar.ui
        return HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ForEach(days, id: \.self) { day in
                let isToday = day == ui.today
                let weekend = day.weekday == .saturday || day.weekday == .sunday
                Button {
                    if days.count > 1 { ui.show(day, mode: .day) }
                } label: {
                    HStack(spacing: 8) {
                        Text(day.weekday.shortName.uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .kerning(0.96)
                            .foregroundStyle(isToday ? theme.brassInkColor : theme.inkDimColor)
                        if isToday {
                            Text("\(day.day)")
                                .font(ThubanFont.display(19, weight: .bold))
                                .foregroundStyle(theme.onAccentColor)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(theme.accentColor))
                        } else {
                            Text("\(day.day)")
                                .font(ThubanFont.display(19))
                                .foregroundStyle(weekend ? theme.inkDimColor : theme.inkColor)
                        }
                        if days.count == 1 {
                            Text(CalendarText.monthTitle(year: day.year, month: day.month))
                                .font(ThubanFont.body(13))
                                .foregroundStyle(theme.inkFaintColor)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(width: colW, height: CalendarMetrics.headerHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .thubanHairline(.leading, color: theme.lineColor)
                .accessibilityLabel(CalendarText.longDay(day) + (isToday ? ", today" : ""))
                .help(days.count > 1 ? "Show this day" : "")
            }
        }
        .frame(height: CalendarMetrics.headerHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panelColor)
        .thubanHairline(.bottom, color: theme.lineColor)
    }

    // MARK: All-day row

    struct Bar: Identifiable {
        var item: AgendaEvent
        var first: Int
        var last: Int
        var lane: Int
        var id: String { item.id }
    }

    /// All-day and ≥ 24 h events as bars across the days they cover.
    private func allDayBars(_ items: [AgendaEvent]) -> [Bar] {
        let zone = app.zone
        guard let first = days.first else { return [] }
        var bars: [Bar] = []
        for item in items where isBar(item.event) {
            let startDay = item.event.start.civilDate(in: zone)
            let endDay = item.event.isAllDay ? item.event.end.civilDate(in: zone).adding(days: -1)
                : CivilDate(item.event.endDate(in: zone).addingTimeInterval(-1), in: zone)
            let a = max(0, first.days(to: startDay)), b = min(days.count - 1, first.days(to: max(startDay, endDay)))
            guard a <= b else { continue }
            bars.append(Bar(item: item, first: a, last: b, lane: 0))
        }
        let lanes = EventLayout.lanes(bars.map { $0.first...$0.last })
        for index in bars.indices { bars[index].lane = lanes[index] }
        return bars
    }

    private func isBar(_ event: CalendarEvent) -> Bool {
        event.isAllDay || event.endDate(in: app.zone).timeIntervalSince(event.startDate(in: app.zone)) >= 86_400
    }

    private func allDayRow(bars: [Bar], colW: CGFloat) -> some View {
        let ui = app.calendar.ui
        let lanes = (bars.map(\.lane).max() ?? -1) + 1
        let shownLanes = min(lanes, 4)
        let height = max(44, 18 + CGFloat(shownLanes) * 24 + CGFloat(max(0, shownLanes - 1)) * 4)
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                Text("all-day")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkFaintColor)
                    .frame(width: gutter - 8, alignment: .trailing)
                    .padding(.top, 13)
                    .frame(width: gutter, height: height, alignment: .topLeading)
                ForEach(days, id: \.self) { day in
                    Color.clear
                        .frame(width: colW, height: height)
                        .calendarDayGround(isToday: day == ui.today, isWeekend: false, theme: theme)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { ui.newEvent(on: day, allDay: true) }
                        .onTapGesture { ui.closePopover() }
                        .thubanHairline(.leading, color: theme.lineColor)
                }
            }
            ForEach(bars.filter { $0.lane < shownLanes }) { bar in
                AllDayChip(item: bar.item, isPast: bar.item.event.endDate(in: app.zone) <= app.now())
                    .frame(width: CGFloat(bar.last - bar.first + 1) * colW - 8, height: 24)
                    .offset(x: gutter + CGFloat(bar.first) * colW + 4, y: 9 + CGFloat(bar.lane) * 28)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panelColor)
        .thubanHairline(.bottom, color: theme.line2Color)
    }

    // MARK: Timed grid

    /// One day's piece of a timed event.
    struct Block: Identifiable {
        var item: AgendaEvent
        var dayIndex: Int
        var startMinute: Double
        var endMinute: Double
        var slot: EventLayout.Slot
        var id: String { "\(item.id)#\(dayIndex)" }
    }

    private func blocks(_ items: [AgendaEvent]) -> [Block] {
        let zone = app.zone
        var result: [Block] = []
        for (index, day) in days.enumerated() {
            let dayStart = day.startDate(in: zone), dayEnd = day.adding(days: 1).startDate(in: zone)
            let pieces = items.filter { !isBar($0.event) && $0.event.startDate(in: zone) < dayEnd && $0.event.endDate(in: zone) > dayStart }
                .map { item -> (AgendaEvent, Double, Double) in
                    let s = max(0, EventLayout.minutes(of: item.event.startDate(in: zone), from: day, zone: zone))
                    let e = min(1440, EventLayout.minutes(of: item.event.endDate(in: zone), from: day, zone: zone))
                    return (item, s, max(e, s))
                }
            let slots = EventLayout.columns(pieces.map { (start: $0.1, end: $0.2) }, minimumLength: 22)
            for (piece, slot) in zip(pieces, slots) {
                result.append(Block(item: piece.0, dayIndex: index, startMinute: piece.1, endMinute: piece.2, slot: slot))
            }
        }
        return result
    }

    private func timeGrid(items: [AgendaEvent], colW: CGFloat, width: CGFloat) -> some View {
        let ui = app.calendar.ui
        let blocks = blocks(items)
        let pending = ui.pendingMove
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    // Scroll anchors, one per hour, 8 pt above the hour line so its label shows whole.
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in Color.clear.frame(height: hh).id(hour) }
                    }
                    .frame(width: 1)
                    .offset(y: -8)
                    dayColumns(colW: colW)
                    hourLines(width: width)
                    ForEach(blocks) { block in
                        blockView(block, colW: colW, pending: pending)
                    }
                    if let pending, let ghost = pendingGhost(pending, colW: colW) {
                        ghost
                    }
                    if let create {
                        creationPreview(create, colW: colW)
                    }
                    nowLine(colW: colW).zIndex(3)
                }
                .frame(width: width, height: 24 * hh, alignment: .topLeading)
            }
            .scrollIndicators(.never)
            .onAppear { scrollToMorning(proxy, blocks: blocks) }
            .onChange(of: ui.scrollRequest) { _, _ in scrollToMorning(proxy, blocks: blocks) }
        }
    }

    private func scrollToMorning(_ proxy: ScrollViewProxy, blocks: [Block]) {
        let earliest = blocks.map { Int($0.startMinute) / 60 }.min() ?? 7
        var hour = max(0, min(7, earliest))
        // Opened from elsewhere (Today, Mail, search): keep the selected event in view.
        if let selected = app.calendar.ui.selectedItem, !selected.event.isAllDay {
            let startHour = Calendar.gregorian(app.zone).component(.hour, from: selected.start(in: app.zone))
            if startHour >= 12 { hour = max(0, startHour - 3) }
        }
        DispatchQueue.main.async { proxy.scrollTo(hour, anchor: .top) }
    }

    private func dayColumns(colW: CGFloat) -> some View {
        let ui = app.calendar.ui
        return HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                let weekend = days.count > 1 && (day.weekday == .saturday || day.weekday == .sunday)
                Color.clear
                    .frame(width: colW, height: 24 * hh)
                    .calendarDayGround(isToday: day == ui.today, isWeekend: weekend, theme: theme)
                    .thubanHairline(.leading, color: theme.lineColor)
                    .contentShape(Rectangle())
                    .gesture(createGesture(dayIndex: index, colW: colW))
            }
        }
    }

    private func hourLines(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<24, id: \.self) { hour in
                let y = CGFloat(hour) * hh
                Rectangle().fill(theme.lineColor)
                    .frame(width: max(0, width - gutter), height: 1)
                    .offset(x: gutter, y: y)
                if hour > 0 {
                    Text(CalendarText.hourLabel(hour))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkFaintColor)
                        .frame(width: gutter - 10, alignment: .trailing)
                        .offset(y: y - 7)
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func nowLine(colW: CGFloat) -> some View {
        let ui = app.calendar.ui
        if let index = days.firstIndex(of: ui.today) {
            let minutes = EventLayout.minutes(of: app.now(), from: ui.today, zone: app.zone)
            let y = CGFloat(minutes / 60) * hh
            let x = gutter + CGFloat(index) * colW
            ZStack(alignment: .topLeading) {
                Rectangle().fill(theme.negTextColor).frame(width: colW, height: 2).offset(x: x, y: y)
                Circle().fill(theme.negTextColor).frame(width: 10, height: 10).offset(x: x - 5, y: y - 4)
                Text(CalendarText.clock(app.now(), zone: app.zone, suffix: false))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.negTextColor)
                    .padding(.leading, 4)
                    .frame(width: gutter - 6, alignment: .trailing)
                    .background(theme.bgColor)
                    .offset(y: y - 8)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: Blocks

    private func frame(start: Double, end: Double, dayIndex: Int, slot: EventLayout.Slot, colW: CGFloat) -> CGRect {
        let inner = colW - 8
        let fraction = slot.fraction
        let x = gutter + CGFloat(dayIndex) * colW + 3 + CGFloat(fraction.x) * inner
        let w = CGFloat(fraction.width) * inner - (slot.column + slot.span < slot.columns ? 2 : 0)
        let y = CGFloat(start / 60) * hh + 1
        let h = max(18, CGFloat((end - start) / 60) * hh - 2)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    @ViewBuilder
    private func blockView(_ block: Block, colW: CGFloat, pending: PendingMove?) -> some View {
        let ui = app.calendar.ui
        let item = block.item
        let isPending = pending?.item.id == item.id
        let movedRect = pending.flatMap { isPending ? pendingFrame($0, colW: colW) : nil }
        if !isPending || movedRect != nil {
            let base = movedRect ?? frame(start: block.startMinute, end: block.endMinute, dayIndex: block.dayIndex, slot: block.slot, colW: colW)
            let dragging = drag?.blockID == block.id
            let rect = dragging ? dragged(base, block: block, colW: colW) : base
            let editable = ui.canEdit(item) && !item.event.isAllDay && !isPending
            TimedEventBlock(item: item, height: rect.height, isPast: item.event.endDate(in: app.zone) <= app.now() && !isPending && !dragging,
                            isHighlighted: isPending || dragging,
                            timeText: dragging ? dragTimeText(block, colW: colW) : (isPending ? pendingTimeText(pending!) : nil),
                            isSelected: ui.selectedID == item.id)
                .frame(width: rect.width, height: rect.height)
                .anchorPreference(key: SelectedEventAnchorKey.self, value: .bounds) { ui.selectedID == item.id && !isPending ? $0 : nil }
                .overlay(alignment: .bottom) {
                    if editable, rect.height >= 24 {
                        ResizeHandle()
                            .gesture(resizeGesture(block, colW: colW))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if !isPending { ui.select(item) } }
                .gesture(editable ? moveGesture(block, colW: colW) : nil)
                .offset(x: rect.minX, y: rect.minY)
                .zIndex(dragging || isPending ? 2 : 1)
        }
    }

    // MARK: Pending move (dropped, waiting for the scope choice / save)

    /// Where a dropped event now sits (nil when its new day is not shown).
    private func pendingFrame(_ pending: PendingMove, colW: CGFloat) -> CGRect? {
        let zone = app.zone
        let startDate = pending.start.instant(in: zone), endDate = pending.end.instant(in: zone)
        let day = CivilDate(startDate, in: zone)
        guard let index = days.firstIndex(of: day) else { return nil }
        let s = EventLayout.minutes(of: startDate, from: day, zone: zone)
        let e = min(1440, EventLayout.minutes(of: endDate, from: day, zone: zone))
        return frame(start: s, end: e, dayIndex: index, slot: .init(column: 0, columns: 1), colW: colW)
    }

    private func pendingTimeText(_ pending: PendingMove) -> String {
        CalendarText.timeRange(pending.start.instant(in: app.zone), pending.end.instant(in: app.zone), zone: app.zone)
    }

    private func pendingGhost(_ pending: PendingMove, colW: CGFloat) -> AnyView? {
        let zone = app.zone
        let event = pending.item.event
        let day = event.start.civilDate(in: zone)
        guard let index = days.firstIndex(of: day), !event.isAllDay else { return nil }
        let s = EventLayout.minutes(of: event.startDate(in: zone), from: day, zone: zone)
        let e = min(1440, EventLayout.minutes(of: event.endDate(in: zone), from: day, zone: zone))
        let rect = frame(start: s, end: e, dayIndex: index, slot: .init(column: 0, columns: 1), colW: colW)
        return AnyView(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(theme.color(for: pending.item.tint), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        )
    }

    // MARK: Drag to move / resize

    struct GridDrag: Equatable {
        enum Kind { case move, resize }
        var blockID: String
        var kind: Kind
        var translation: CGSize
    }

    private func deltas(_ drag: GridDrag, colW: CGFloat) -> (days: Int, minutes: Int) {
        let minutes = EventLayout.snap(minutes: Double(drag.translation.height / hh * 60))
        let dayShift = drag.kind == .move ? Int((drag.translation.width / colW).rounded()) : 0
        return (dayShift, minutes)
    }

    private func dragged(_ base: CGRect, block: Block, colW: CGFloat) -> CGRect {
        guard let drag else { return base }
        let d = deltas(drag, colW: colW)
        var rect = base
        switch drag.kind {
        case .move:
            let dayShift = max(-block.dayIndex, min(days.count - 1 - block.dayIndex, d.days))
            rect.origin.x = gutter + CGFloat(block.dayIndex + dayShift) * colW + 3
            rect.size.width = colW - 8
            rect.origin.y = base.minY + CGFloat(d.minutes) / 60 * hh
        case .resize:
            rect.size.height = max(CGFloat(15) / 60 * hh - 2, base.height + CGFloat(d.minutes) / 60 * hh)
        }
        return rect
    }

    /// New start / end for a drag (wall-clock minutes, whole-day shifts).
    private func movedTimes(_ block: Block, drag: GridDrag, colW: CGFloat) -> (Date, Date) {
        let zone = app.zone
        let event = block.item.event
        let start = event.startDate(in: zone), end = event.endDate(in: zone)
        let d = deltas(drag, colW: colW)
        switch drag.kind {
        case .move:
            let dayShift = max(-block.dayIndex, min(days.count - 1 - block.dayIndex, d.days))
            let startDay = CivilDate(start, in: zone).adding(days: dayShift)
            let startMinute = Int(EventLayout.minutes(of: start, from: CivilDate(start, in: zone), zone: zone).rounded()) + d.minutes
            let newStart = EventLayout.date(on: startDay, minutes: startMinute, zone: zone)
            return (newStart, newStart.addingTimeInterval(end.timeIntervalSince(start)))
        case .resize:
            let endDay = CivilDate(end, in: zone)
            let endMinute = Int(EventLayout.minutes(of: end, from: endDay, zone: zone).rounded()) + d.minutes
            let newEnd = max(start.addingTimeInterval(15 * 60), EventLayout.date(on: endDay, minutes: endMinute, zone: zone))
            return (start, newEnd)
        }
    }

    private func dragTimeText(_ block: Block, colW: CGFloat) -> String? {
        guard let drag else { return nil }
        let (s, e) = movedTimes(block, drag: drag, colW: colW)
        return CalendarText.timeRange(s, e, zone: app.zone)
    }

    private func moveGesture(_ block: Block, colW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                drag = GridDrag(blockID: block.id, kind: .move, translation: value.translation)
            }
            .onEnded { value in
                let final = GridDrag(blockID: block.id, kind: .move, translation: value.translation)
                drag = nil
                commit(block, final, colW: colW)
            }
    }

    private func resizeGesture(_ block: Block, colW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                drag = GridDrag(blockID: block.id, kind: .resize, translation: value.translation)
            }
            .onEnded { value in
                let final = GridDrag(blockID: block.id, kind: .resize, translation: value.translation)
                drag = nil
                commit(block, final, colW: colW)
            }
    }

    private func commit(_ block: Block, _ final: GridDrag, colW: CGFloat) {
        let d = deltas(final, colW: colW)
        guard d.days != 0 || d.minutes != 0 else { return }
        let (s, e) = movedTimes(block, drag: final, colW: colW)
        let tz = block.item.event.start.timeZone ?? app.zone.identifier
        app.calendar.ui.commitMove(block.item, start: .timed(s, timeZone: tz), end: .timed(e, timeZone: tz))
    }

    // MARK: Drag on empty space to create

    struct CreateDrag: Equatable {
        var dayIndex: Int
        var startMinute: Int
        var endMinute: Int
    }

    private func createGesture(dayIndex: Int, colW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let a = EventLayout.snap(minutes: Double(value.startLocation.y / hh * 60), step: 15)
                let aFloor = (Int(value.startLocation.y / hh * 60) / 15) * 15
                let b = EventLayout.snap(minutes: Double(value.location.y / hh * 60), step: 15)
                guard abs(value.translation.height) > 6 else { return }
                let lo = min(aFloor, b), hi = max(a, b)
                create = CreateDrag(dayIndex: dayIndex, startMinute: max(0, lo), endMinute: min(1440, max(hi, lo + 15)))
            }
            .onEnded { value in
                let ui = app.calendar.ui
                defer { create = nil }
                if let create {
                    ui.newEvent(on: days[dayIndex], startMinute: create.startMinute, endMinute: create.endMinute)
                    return
                }
                // A click: closes an open popover, otherwise starts an hour-long event there.
                if ui.selectedID != nil { ui.closePopover(); return }
                let minute = (Int(value.location.y / hh * 60) / 30) * 30
                ui.newEvent(on: days[dayIndex], startMinute: minute, endMinute: minute + 60)
            }
    }

    private func creationPreview(_ create: CreateDrag, colW: CGFloat) -> some View {
        let rect = frame(start: Double(create.startMinute), end: Double(create.endMinute), dayIndex: create.dayIndex,
                         slot: .init(column: 0, columns: 1), colW: colW)
        return VStack(alignment: .leading, spacing: 0) {
            Text(CalendarText.clock(minutes: create.startMinute) + " – " + CalendarText.clock(minutes: create.endMinute))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(theme.brassInkColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            Spacer(minLength: 0)
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .background(theme.accentTintColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
        .offset(x: rect.minX, y: rect.minY)
        .allowsHitTesting(false)
    }
}

/// The bottom edge of a block: drag to change the end time.
private struct ResizeHandle: View {
    var body: some View {
        Color.clear
            .frame(height: 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Event blocks

/// A timed event in the grid (design: soft fill, 3 pt bar in the calendar colour, title / time / place; one line
/// when short; dashed when you have not answered the invitation; past events at 62 %).
struct TimedEventBlock: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: AgendaEvent
    var height: CGFloat
    var isPast: Bool
    var isHighlighted: Bool = false
    var timeText: String? = nil
    var isSelected: Bool = false

    var body: some View {
        let event = item.event
        let tint = item.tint
        let text = theme.textColor(for: tint)
        let tentative = event.needsResponse || event.selfResponse == .tentative
        let short = height < 38
        let zone = app.zone
        let range = timeText ?? CalendarText.timeRange(event.startDate(in: zone), event.endDate(in: zone), zone: zone)
        ZStack(alignment: .topLeading) {
            if short {
                Text("\(CalendarText.clock(event.startDate(in: zone), zone: zone, suffix: false)) · \(event.title)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(text)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, max(1, min(3, (height - 16) / 2)))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(event.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(text)
                        .lineLimit(1)
                    Text(range)
                        .font(.system(size: 11.5))
                        .foregroundStyle(text.opacity(0.85))
                        .lineLimit(1)
                    if height >= 68, let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(.system(size: 11.5))
                            .foregroundStyle(text.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if tentative {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.panelColor)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(theme.color(for: tint), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.softColor(for: tint))
            }
        }
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, style: .continuous)
                .fill(theme.color(for: tint))
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.accentColor, lineWidth: 2).padding(-2)
            } else if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.color(for: tint), lineWidth: 1)
            }
        }
        .opacity(isPast ? 0.62 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.title), \(range)")
        .accessibilityAddTraits(.isButton)
        .help(event.title)
    }
}

/// An all-day bar (design: 24 pt, soft fill, 12 pt semibold in the calendar's text colour).
struct AllDayChip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: AgendaEvent
    var isPast: Bool
    var height: CGFloat = 24
    var radius: CGFloat = 6

    var body: some View {
        let ui = app.calendar.ui
        let tentative = item.event.needsResponse
        Button {
            ui.select(item)
        } label: {
            Text(item.event.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textColor(for: item.tint))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(tentative ? theme.panelColor : theme.softColor(for: item.tint), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    if tentative {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(theme.color(for: item.tint), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    } else if ui.selectedID == item.id {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(theme.color(for: item.tint), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isPast ? 0.62 : 1)
        .anchorPreference(key: SelectedEventAnchorKey.self, value: .bounds) { ui.selectedID == item.id ? $0 : nil }
        .accessibilityLabel("\(item.event.title), all day")
        .help(item.event.title)
    }
}
