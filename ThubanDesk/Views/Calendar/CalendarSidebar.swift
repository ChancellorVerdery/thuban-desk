import SwiftUI
import ThubanDeskCore

/// Left column (design: Main): mini month, calendars grouped by account with colour checkboxes (click to show /
/// hide, right-click for colour and default), and the pending-invitations card.
struct CalendarSidebar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let ui = app.calendar.ui
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                    MiniMonthView(month: ui.miniMonth ?? ui.focusMonth,
                                  highlighted: highlightedDays(ui),
                                  today: ui.today,
                                  firstWeekday: ui.firstWeekday,
                                  onPick: { day in ui.show(day) },
                                  onMonth: { month in ui.miniMonth = month })
                    calendarsList
                }
                .padding(.top, 18)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            SidebarInvitationsCard()
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.panelColor)
        .thubanHairline(.trailing, color: theme.lineColor)
    }

    private func highlightedDays(_ ui: CalendarUIState) -> ClosedRange<CivilDate>? {
        switch ui.mode {
        case .day: return ui.focusDay...ui.focusDay
        case .week, .month:
            let days = ui.gridDays
            guard let first = days.first, let last = days.last else { return nil }
            return first...last
        }
    }

    private var calendarsList: some View {
        let calendars = app.calendar.calendars
        return VStack(alignment: .leading, spacing: 4) {
            Text("CALENDARS")
                .font(ThubanFont.micro)
                .kerning(0.96)
                .foregroundStyle(theme.inkDimColor)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            if calendars.isEmpty {
                Text(app.calendar.isLoading ? "Loading calendars…" : "No calendars yet.")
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkFaintColor)
                    .padding(.horizontal, 8)
            }
            ForEach(Array(app.accounts.enumerated()), id: \.element.id) { index, account in
                let refs = calendars.filter { $0.account == account.id }
                if !refs.isEmpty || account.disconnected {
                    if index > 0 { Spacer().frame(height: 6) }
                    AccountHeading(email: account.id, isPrimary: account.id == app.primaryAccount?.id, disconnected: account.disconnected)
                    ForEach(refs) { ref in
                        CalendarRow(ref: ref)
                    }
                }
            }
        }
    }
}

private struct AccountHeading: View {
    @Environment(\.thubanTheme) private var theme
    var email: String
    var isPrimary: Bool
    var disconnected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(email)
                .font(ThubanFont.body(13, weight: .semibold))
                .foregroundStyle(theme.inkDimColor)
                .lineLimit(1)
                .truncationMode(.tail)
            if isPrimary {
                Text("Primary")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.brassInkColor)
                    .padding(.horizontal, 6)
                    .frame(height: 19)
                    .background(theme.accentTintColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
                    .fixedSize()
            }
            if disconnected {
                Text("Signed out").thubanChip(kind: .neg).fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A calendar with its colour checkbox; click toggles visibility.
private struct CalendarRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var ref: CalendarRef
    @State private var hovering = false

    var body: some View {
        let shown = !ref.isHidden
        Button {
            app.calendar.setHidden(shown, ref.key)
        } label: {
            HStack(spacing: 10) {
                CalendarCheckbox(tint: ref.tint, isOn: shown)
                Text(ref.name)
                    .font(ThubanFont.body(14))
                    .foregroundStyle(shown ? theme.inkColor : theme.inkFaintColor)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !shown {
                    Text("Hidden").font(ThubanFont.body(12)).foregroundStyle(theme.inkFaintColor)
                } else if app.calendar.defaultCalendar?.key == ref.key, hovering {
                    Text("Default").font(ThubanFont.body(12)).foregroundStyle(theme.inkFaintColor)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(hovering ? theme.panel2Color : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(ref.name)
        .accessibilityValue(shown ? "Shown" : "Hidden")
        .accessibilityAddTraits(shown ? [.isSelected] : [])
        .contextMenu {
            Picker("Colour", selection: Binding(get: { ref.tint }, set: { app.calendar.setTint($0, ref.key) })) {
                ForEach(CalendarTint.allCases, id: \.self) { tint in Text(tint.label).tag(tint) }
            }
            Button("Use Google’s colour") { app.calendar.setTint(nil, ref.key) }
            if ref.canWrite {
                Divider()
                Button("New events go here") { app.settings.defaultCalendar = ref.key }
            }
        }
    }
}

/// 16 pt rounded square in the calendar colour with a check; an outlined empty square when hidden.
struct CalendarCheckbox: View {
    @Environment(\.thubanTheme) private var theme
    var tint: CalendarTint
    var isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(theme.color(for: tint))
                Icon(.check, size: 12, lineWidth: 2.4).foregroundStyle(theme.isDark ? theme.bgColor : theme.inkColor)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1.5)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - Invitations

/// "INVITATIONS 1 · Interview · Crescent Labs · Fri, Sep 25 · 3:00 – 3:45 PM · [Respond]".
private struct SidebarInvitationsCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let invitations = app.calendar.pendingInvitations
        if let first = invitations.first {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("INVITATIONS").font(ThubanFont.micro).kerning(0.96).foregroundStyle(theme.inkDimColor)
                    Spacer()
                    Text("\(invitations.count)").font(ThubanFont.mono(12)).foregroundStyle(theme.brassInkColor)
                }
                Text(first.event.title)
                    .font(ThubanFont.body(14, weight: .semibold))
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(2)
                Text(CalendarText.shortWhen(first.event, zone: app.zone))
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkDimColor)
                Button("Respond") { respond(first) }
                    .buttonStyle(SecondaryButtonStyle(height: 28))
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHint("Shows the invitation with Yes, Maybe and No")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
        }
    }

    private func respond(_ item: AgendaEvent) {
        let ui = app.calendar.ui
        let day = item.event.start.civilDate(in: app.zone)
        if ui.mode == .month || !ui.gridDays.contains(day) { ui.show(day, mode: ui.mode == .month ? .week : nil) }
        ui.select(item)
    }
}

// MARK: - Mini month

/// The sidebar's month (also the editor's date picker): 7 × 5–6 days, the shown range as a soft band, today in an
/// accent circle.
struct MiniMonthView: View {
    @Environment(\.thubanTheme) private var theme
    var month: YearMonth
    var highlighted: ClosedRange<CivilDate>?
    var today: CivilDate
    var firstWeekday: Weekday
    var selected: CivilDate? = nil
    var onPick: (CivilDate) -> Void
    var onMonth: (YearMonth) -> Void

    var body: some View {
        let weekdays = Weekday.ordered(from: firstWeekday)
        let first = month.firstDay
        let offset = (first.weekday.calendarWeekday - firstWeekday.calendarWeekday + 7) % 7
        let start = first.adding(days: -offset)
        let length = EventLayout.daysInMonth(year: month.year, month: month.month)
        let rows = Int(ceil(Double(offset + length) / 7))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text(CalendarText.monthTitle(year: month.year, month: month.month))
                    .font(ThubanFont.display(16))
                    .foregroundStyle(theme.inkColor)
                Spacer()
                IconButton(.chevronLeft, label: "Previous month", size: 26, iconSize: 14) { onMonth(month.adding(months: -1)) }
                IconButton(.chevronRight, label: "Next month", size: 26, iconSize: 14) { onMonth(month.adding(months: 1)) }
            }
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    ForEach(weekdays, id: \.self) { day in
                        Text(String(day.shortName.prefix(1)))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.inkFaintColor)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 2)
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            let day = start.adding(days: row * 7 + column)
                            dayCell(day, column: column)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: CivilDate, column: Int) -> some View {
        let inRange = highlighted.map { $0.contains(day) } ?? false
        let isToday = day == today
        let isSelected = selected == day
        let inMonth = day.month == month.month && day.year == month.year
        let leftEnd = inRange && (column == 0 || day == highlighted?.lowerBound)
        let rightEnd = inRange && (column == 6 || day == highlighted?.upperBound)
        return Button {
            onPick(day)
        } label: {
            Text("\(day.day)")
                .font(.system(size: 12.5, weight: isToday || isSelected ? .bold : .regular))
                .foregroundStyle(isToday ? theme.onAccentColor : (isSelected ? theme.brassInkColor : (inMonth ? theme.inkColor : theme.inkFaintColor)))
                .frame(width: 26, height: 26)
                .background {
                    if isToday {
                        Circle().fill(theme.accentColor)
                    } else if isSelected {
                        Circle().strokeBorder(theme.accentColor, lineWidth: 1.5)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background {
                    if inRange {
                        UnevenRoundedRectangle(topLeadingRadius: leftEnd ? 7 : 0, bottomLeadingRadius: leftEnd ? 7 : 0,
                                               bottomTrailingRadius: rightEnd ? 7 : 0, topTrailingRadius: rightEnd ? 7 : 0, style: .continuous)
                            .fill(theme.accentTintColor)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CalendarText.longDay(day))
        .accessibilityAddTraits(isToday ? [.isSelected] : [])
    }
}
