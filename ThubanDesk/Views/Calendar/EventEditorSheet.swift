import SwiftUI
import ThubanDeskCore

/// Scrim + the editor sheet hanging from the title bar (design: EventEditor, 940 pt wide).
struct EditorOverlay: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var draft: EventDraft

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                theme.inkColor.opacity(theme.isDark ? 0 : 0.30)
                    .overlay(Color.black.opacity(theme.isDark ? 0.5 : 0))
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
                EventEditorSheet(draft: Binding(get: { app.calendar.ui.editor ?? draft }, set: { app.calendar.ui.editor = $0 }))
                    .frame(width: min(940, geo.size.width - 32), height: min(824, geo.size.height - 24))
                    .id(draft.id)
            }
        }
    }
}

/// Title, calendar, all-day, starts / ends, time zone, location, repeat builder | guests with replies, rich
/// description | Delete event · Cancel · Save. An invitation from someone else gets the "Going?" bar on top.
struct EventEditorSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Binding var draft: EventDraft
    @State private var richText = RichTextController()
    @State private var linkOpen = false
    @State private var calendarMenuOpen = false
    @State private var linkText = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        let ui = app.calendar.ui
        VStack(spacing: 0) {
            if draft.isInvitation, let item = draft.original {
                invitationBar(item)
            }
            HStack(alignment: .top, spacing: 0) {
                ScrollView(.vertical) { leftColumn.padding(.horizontal, 24).padding(.vertical, 20) }
                    .scrollIndicators(.automatic)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1.1)
                    .thubanHairline(.trailing, color: theme.lineColor)
                rightColumn
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(width: 448)
            }
            .frame(maxHeight: .infinity)
            .disabled(!draft.canEdit)
            footer(ui)
        }
        .background(theme.panelColor)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous))
        .overlay(
            UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous)
                .strokeBorder(theme.line2Color, lineWidth: 1)
                .padding(.top, -1)
                .clipped()
        )
        .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.12), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(draft.isNew ? "New event" : "Edit event")
        .onAppear { if draft.isNew { titleFocused = true } }
    }

    // MARK: Invitation bar

    private func invitationBar(_ item: AgendaEvent) -> some View {
        let ui = app.calendar.ui
        return HStack(spacing: 12) {
            Icon(.mail, size: 16).foregroundStyle(theme.brassInkColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(draft.organizerName ?? "Someone") invited you")
                    .font(ThubanFont.body(14, weight: .semibold))
                    .foregroundStyle(theme.inkColor)
                Text(item.event.guestsCanModify == true ? "Guests can edit this event. Your changes are sent to everyone."
                     : "Only \(draft.organizerName ?? "the organizer") can change this event. Your reply is sent to them.")
                    .font(ThubanFont.body(12.5))
                    .foregroundStyle(theme.inkDimColor)
            }
            Spacer(minLength: 8)
            Text("Going?").font(ThubanFont.body(13, weight: .semibold)).foregroundStyle(theme.inkDimColor)
            HStack(spacing: 2) {
                rsvpButton("Yes", .accepted, item, ui)
                rsvpButton("Maybe", .tentative, item, ui)
                rsvpButton("No", .declined, item, ui)
            }
            .padding(3)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("RSVP")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(theme.accentTintColor)
        .thubanHairline(.bottom, color: theme.lineColor)
    }

    private func rsvpButton(_ label: String, _ status: ResponseStatus, _ item: AgendaEvent, _ ui: CalendarUIState) -> some View {
        let on = draft.rsvp == status
        let colors: (Color, Color) = {
            switch status {
            case .accepted: return (theme.posSoftColor, theme.posTextColor)
            case .tentative: return (theme.warnSoftColor, theme.brassInkColor)
            default: return (theme.negSoftColor, theme.negTextColor)
            }
        }()
        return Button {
            draft.rsvp = status
            ui.rsvp(status, item)
        } label: {
            HStack(spacing: 5) {
                if on { Icon(.check, size: 13, lineWidth: 2.2) }
                Text(label)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? colors.1 : theme.inkDimColor)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(on ? colors.0 : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    // MARK: Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Add a title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(ThubanFont.display(22))
                .foregroundStyle(theme.inkColor)
                .focused($titleFocused)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                .accessibilityLabel("Title")
            EditorRow(label: "Calendar") { calendarPicker }
            Hairline()
            EditorRow(label: "All-day") { EditorSwitch(isOn: $draft.isAllDay, label: "All-day") }
            EditorRow(label: "Starts") {
                DateBox(day: Binding(get: { draft.startDay }, set: { draft.setStart(day: $0) }), label: "Start date")
                if !draft.isAllDay {
                    TimeBox(minute: Binding(get: { draft.startMinute }, set: { draft.setStart(minute: $0) }), label: "Start time")
                }
            }
            EditorRow(label: "Ends") {
                DateBox(day: $draft.endDay, label: "End date")
                if !draft.isAllDay {
                    TimeBox(minute: $draft.endMinute, label: "End time")
                }
                Text(draft.isValid ? CalendarText.duration(minutes: draft.durationMinutes) : "Ends before it starts")
                    .font(ThubanFont.body(13))
                    .foregroundStyle(draft.isValid ? theme.inkFaintColor : theme.negTextColor)
                    .lineLimit(1)
                    .fixedSize()
            }
            if !draft.isAllDay {
                EditorRow(label: "Time zone") {
                    Text(zoneText).font(ThubanFont.body(14)).foregroundStyle(theme.inkDimColor)
                }
            }
            EditorRow(label: "Location") {
                TextField("Add a place or link", text: $draft.location)
                    .textFieldStyle(.plain)
                    .font(ThubanFont.body(14))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                    .accessibilityLabel("Location")
            }
            Hairline()
            repeatSection
        }
    }

    private var zoneText: String {
        let zone = app.zone
        let name = zone.localizedName(for: .generic, locale: Locale(identifier: "en_US")) ?? zone.identifier
        let city = zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? ""
        return city.isEmpty ? name : "\(name) — \(city)"
    }

    private var calendarPicker: some View {
        let current = app.calendar.calendar(draft.calendar)
        let box = EditorBox {
            TintDot(tint: current?.tint ?? .accent, size: 9)
            Text(current?.name ?? "Calendar")
            Text(draft.calendar.account).font(ThubanFont.body(13)).foregroundStyle(theme.inkFaintColor).lineLimit(1)
            if draft.isNew { Icon(.upDown, size: 13).foregroundStyle(theme.inkFaintColor) }
        }
        .fixedSize()
        return Group {
            if draft.isNew {
                Button { calendarMenuOpen = true } label: { box }
                    .buttonStyle(.plain)
                    .popover(isPresented: $calendarMenuOpen, arrowEdge: .bottom) { calendarList }
                    .help("Choose a calendar")
            } else {
                box.help("An event stays on its calendar; duplicate it to put a copy on another.")
            }
        }
        .accessibilityLabel("Calendar")
        .accessibilityValue(current?.name ?? "")
    }

    private var calendarList: some View {
        let refs = app.calendar.calendars.filter { $0.canWrite }
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(app.accounts) { account in
                let mine = refs.filter { $0.account == account.id }
                if !mine.isEmpty {
                    Text(account.id)
                        .font(ThubanFont.body(12, weight: .semibold))
                        .foregroundStyle(theme.inkDimColor)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                    ForEach(mine) { ref in
                        Button {
                            draft.calendar = ref.key
                            calendarMenuOpen = false
                        } label: {
                            HStack(spacing: 8) {
                                TintDot(tint: ref.tint, size: 9)
                                Text(ref.name).font(ThubanFont.body(14)).foregroundStyle(theme.inkColor)
                                Spacer(minLength: 12)
                                if ref.key == draft.calendar { Icon(.check, size: 13).foregroundStyle(theme.brassInkColor) }
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(8)
        .frame(minWidth: 240)
        .background(theme.panelColor)
        .environment(\.thubanTheme, theme)
    }

    // MARK: Repeat

    private var repeatOptions: [SegmentOption<EventDraft.RepeatKind>] {
        var kinds: [EventDraft.RepeatKind] = [.never, .daily, .weekly, .monthly]
        if draft.repeatKind == .yearly { kinds.append(.yearly) }
        if draft.repeatKind == .custom { kinds.append(.custom) }
        return kinds.map { SegmentOption($0, $0.label) }
    }

    @ViewBuilder
    private var repeatSection: some View {
        let ui = app.calendar.ui
        EditorRow(label: "Repeat") {
            SegmentedPicker(selection: Binding(get: { draft.repeatKind }, set: { kind in
                if kind == .weekly, draft.weekdays.isEmpty { draft.weekdays = [draft.startDay.weekday] }
                draft.repeatKind = kind
            }), options: repeatOptions, segmentHeight: 26)
            .accessibilityLabel("Repeat")
        }
        switch draft.repeatKind {
        case .never:
            EmptyView()
        case .custom:
            EditorRow(label: "") {
                Text("This event repeats on a schedule this editor can’t show. It is kept as it is unless you pick another pattern.")
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkDimColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        default:
            EditorRow(label: "Every") {
                NumberBox(value: $draft.interval, label: "Repeat every")
                Text(unitText).font(ThubanFont.body(14)).foregroundStyle(theme.inkColor)
            }
            if draft.repeatKind == .weekly {
                EditorRow(label: "") {
                    WeekdayToggles(selection: $draft.weekdays, firstWeekday: ui.firstWeekday)
                }
            }
            if draft.repeatKind == .monthly {
                EditorRow(label: "") {
                    SegmentedPicker(selection: $draft.monthlyByWeekday,
                                    options: [SegmentOption(false, draft.monthlyLabels.byDate), SegmentOption(true, draft.monthlyLabels.byWeekday)],
                                    segmentHeight: 26)
                }
            }
            EditorRow(label: "Ends", alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    RadioLine(label: "Never", isOn: draft.endKind == .never, action: { draft.endKind = .never }) { EmptyView() }
                    RadioLine(label: "On", isOn: draft.endKind == .onDate, action: { draft.endKind = .onDate }) {
                        DateBox(day: $draft.untilDay, label: "Last date")
                            .simultaneousGesture(TapGesture().onEnded { draft.endKind = .onDate })
                    }
                    RadioLine(label: "After", isOn: draft.endKind == .after, action: { draft.endKind = .after }) {
                        NumberBox(value: $draft.count, label: "Number of times", range: 1...999)
                            .simultaneousGesture(TapGesture().onEnded { draft.endKind = .after })
                        Text("times").font(ThubanFont.body(14)).foregroundStyle(theme.inkDimColor)
                    }
                }
            }
            if let summary = draft.repeatSummary(now: app.now()) {
                HStack(spacing: 8) {
                    Icon(.repeats, size: 14)
                    Text(summary)
                }
                .font(ThubanFont.body(13.5, weight: .semibold))
                .foregroundStyle(theme.brassInkColor)
                .padding(.leading, 108)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var unitText: String {
        let plural = draft.interval != 1
        switch draft.repeatKind {
        case .daily: return plural ? "days" : "day"
        case .weekly: return plural ? "weeks on" : "week on"
        case .monthly: return plural ? "months" : "month"
        case .yearly: return plural ? "years" : "year"
        default: return ""
        }
    }

    // MARK: Right column

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("GUESTS").font(ThubanFont.micro).kerning(0.96).foregroundStyle(theme.inkDimColor)
                Spacer()
                if !draft.attendees.isEmpty {
                    Text(CalendarText.replyCounts(draft.attendees)).font(ThubanFont.body(13)).foregroundStyle(theme.inkDimColor)
                }
            }
            HStack(spacing: 8) {
                Icon(.guests, size: 14).foregroundStyle(theme.inkFaintColor)
                TextField("Add guests by name or email", text: $draft.newGuest)
                    .textFieldStyle(.plain)
                    .font(ThubanFont.body(14))
                    .onSubmit { draft.addGuests(from: draft.newGuest) }
                    .accessibilityLabel("Add guests")
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
            if !draft.attendees.isEmpty {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(Array(draft.attendees.enumerated()), id: \.element.email) { index, guest in
                            guestRow(guest, tint: guestTint(index))
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: min(CGFloat(draft.attendees.count) * 41, 205))
            }
            Text("DESCRIPTION").font(ThubanFont.micro).kerning(0.96).foregroundStyle(theme.inkDimColor).padding(.top, 8)
            VStack(spacing: 0) {
                formattingBar
                RichTextEditor(html: draft.descriptionHTML, controller: richText, theme: theme, isEditable: draft.canEdit) { html in
                    draft.descriptionHTML = html
                    draft.descriptionEdited = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
            .frame(maxHeight: .infinity)
            HStack(spacing: 6) {
                Icon(.info, size: 13)
                Text("Formatting and links are kept; scripts and embeds are removed.")
            }
            .font(ThubanFont.body(12.5))
            .foregroundStyle(theme.inkFaintColor)
        }
    }

    private func guestTint(_ index: Int) -> CalendarTint {
        let guest = draft.attendees[index]
        if guest.isSelf == true { return .accent }
        let others = draft.attendees.prefix(index).filter { $0.isSelf != true }.count
        return [CalendarTint.signal, .pos, .neg, .grey][others % 4]
    }

    private func guestRow(_ guest: EventAttendee, tint: CalendarTint) -> some View {
        let isSelf = guest.isSelf == true || app.ownAddresses.contains(guest.email.lowercased())
        let organizer = guest.organizer == true
        return HStack(spacing: 10) {
            AvatarView(name: guest.displayName ?? guest.email, tint: tint, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text((guest.displayName ?? guest.email) + (isSelf ? " (you)" : ""))
                    .font(ThubanFont.body(14, weight: .semibold))
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(1)
                Text(guest.email + (organizer ? " · Organizer" : "") + (guest.optional == true ? " · Optional" : ""))
                    .font(ThubanFont.body(12.5))
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            replyBadge(guest.responseStatus ?? .needsAction)
            if !organizer, !isSelf, draft.canEdit {
                Button {
                    draft.removeGuest(guest.email)
                } label: {
                    Icon(.close, size: 12).foregroundStyle(theme.inkFaintColor).frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(guest.displayName ?? guest.email)")
            }
        }
        .frame(minHeight: 40)
        .thubanHairline(.bottom, color: theme.lineColor)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func replyBadge(_ status: ResponseStatus) -> some View {
        switch status {
        case .accepted:
            HStack(spacing: 4) { Icon(.check, size: 13, lineWidth: 2.2); Text("Going") }
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.posTextColor)
        case .tentative:
            Text("Maybe").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.brassInkColor)
        case .declined:
            Text("Not going").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.negTextColor)
        case .needsAction:
            Text("No reply").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.inkFaintColor)
        }
    }

    private var formattingBar: some View {
        HStack(spacing: 2) {
            formatButton("Bold") { Text("B").font(.system(size: 15, weight: .bold, design: .serif)) } action: { richText.toggleBold() }
            formatButton("Italic") { Text("I").font(.system(size: 15, design: .serif).italic()) } action: { richText.toggleItalic() }
            formatButton("Underline") { Text("U").font(.system(size: 15, design: .serif)).underline() } action: { richText.toggleUnderline() }
            formatButton("Bulleted list") { Icon(.bulletList, size: 15) } action: { richText.toggleList(numbered: false) }
            formatButton("Numbered list") { Icon(.numberedList, size: 15) } action: { richText.toggleList(numbered: true) }
            formatButton("Link") { Icon(.link, size: 15) } action: { linkText = ""; linkOpen = true }
                .popover(isPresented: $linkOpen, arrowEdge: .bottom) {
                    HStack(spacing: 8) {
                        TextField("https://…", text: $linkText)
                            .thubanField(height: 30)
                            .frame(width: 240)
                            .onSubmit(applyLink)
                        Button("Add link", action: applyLink).buttonStyle(PrimaryButtonStyle(height: 30))
                    }
                    .padding(12)
                    .background(theme.panelColor)
                    .environment(\.thubanTheme, theme)
                }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .thubanHairline(.bottom, color: theme.lineColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting")
    }

    private func applyLink() {
        richText.addLink(linkText)
        linkOpen = false
    }

    private func formatButton<Label: View>(_ name: String, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(theme.inkDimColor)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .help(name)
    }

    // MARK: Footer

    private func footer(_ ui: CalendarUIState) -> some View {
        HStack(spacing: 10) {
            if let item = draft.original, ui.canDelete(item) {
                Button {
                    ui.editor = nil
                    ui.requestDelete(item)
                } label: {
                    HStack(spacing: 7) { Icon(.trash, size: 15); Text("Delete event") }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.negTextColor)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Asks before deleting")
            }
            Spacer(minLength: 8)
            if let item = draft.original, item.event.isRecurringInstance || item.event.isRecurringMaster, draft.canEdit {
                Text("Changing a repeating event asks which events to update.")
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(1)
            } else if !draft.canEdit {
                Text("You can’t change this event.").font(ThubanFont.body(13)).foregroundStyle(theme.inkDimColor)
            }
            Button(draft.canEdit ? "Cancel" : "Close") { ui.editor = nil }
                .buttonStyle(SecondaryButtonStyle(height: 34))
                .keyboardShortcut(.cancelAction)
            if draft.canEdit {
                Button(ui.isWorking ? "Saving…" : "Save") { ui.save(draft) }
                    .buttonStyle(PrimaryButtonStyle(height: 34))
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!draft.isValid || ui.isWorking)
                    .help("Save (⌘S)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(theme.bgColor)
        .thubanHairline(.top, color: theme.lineColor)
    }
}
