import SwiftUI
import ThubanDeskCore

/// Event editor sheet (board "Event editor sheet"): Cancel / Edit event / Save; title + location; calendar, all-day,
/// starts / ends (date and time pills with inline pickers), repeat (+ summary line); alert and guests; notes; and
/// "Delete event…". Saving a repeating event asks which events change (board "Change a repeating event") — the shared
/// `CalendarUIState` + core `RecurrenceEditPlanner` decide the calls. Invitations from others are read-only with RSVP.
struct EventEditorSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var draft: EventDraft?
    @State private var expanded: Picker?
    @State private var notes = ""
    @State private var guestText = ""
    @FocusState private var titleFocused: Bool

    enum Picker: Hashable { case startDate, startTime, endDate, endTime }

    var body: some View {
        let ui = app.calendar.ui
        ZStack {
            VStack(spacing: 0) {
                header
                if draft != nil {
                    ScrollView {
                        VStack(spacing: 18) {
                            if let error = ui.errorMessage {
                                PhoneBanner(text: error) { ui.errorMessage = nil }
                            }
                            if isInvitation { rsvpCard }
                            titleCard
                            timeCard
                            alertCard
                            notesCard
                            if let item = draft?.original, ui.canDelete(item) {
                                Button("Delete event…") { ui.requestDelete(item) }
                                    .font(PhoneFont.bodySemibold)
                                    .foregroundStyle(theme.negTextColor)
                                    .frame(maxWidth: .infinity, minHeight: PhoneMetrics.primaryHeight)
                                    .background(theme.bgColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, PhoneMetrics.gutter)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .disabled(!(draft?.canEdit ?? true) && !isInvitation)
                }
            }
            if let prompt = ui.scope {
                ScopeActionSheet(prompt: prompt)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: ui.scope?.id)
        .background(theme.panelColor.ignoresSafeArea())
        .presentationBackground(theme.panelColor)
        .presentationCornerRadius(12)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(ui.isWorking || ui.scope != nil)
        .confirmHost(active: true)
        .onAppear(perform: start)
    }

    private func start() {
        guard draft == nil, let editor = app.calendar.ui.editor else { return }
        draft = editor
        notes = HTMLSanitizer.plainText(editor.descriptionHTML)
        if editor.isNew, !SmokeHarness.isEnabled { titleFocused = true }
    }

    private var isInvitation: Bool { draft?.isInvitation ?? false }

    private var binding: Binding<EventDraft> {
        Binding(get: { draft ?? app.calendar.ui.editor! }, set: { draft = $0 })
    }

    // MARK: Header

    private var header: some View {
        let ui = app.calendar.ui
        return HStack {
            NavTextButton("Cancel") { ui.editor = nil }
            Spacer()
            Text(draft?.isNew ?? true ? "New event" : (draft?.canEdit ?? false ? "Edit event" : "Event"))
                .font(PhoneFont.inlineTitle).foregroundStyle(theme.inkColor)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if draft?.canEdit ?? false {
                NavTextButton(ui.isWorking ? "Saving…" : "Save", bold: true) { save() }
                    .disabled(ui.isWorking || !(draft?.isValid ?? false) || (draft?.title.trimmingCharacters(in: .whitespaces).isEmpty ?? true))
                    .opacity(draft?.isValid ?? false ? 1 : 0.5)
            } else {
                NavTextButton("Done", bold: true) { ui.editor = nil }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .frame(minHeight: 56)
    }

    private func save() {
        guard var draft else { return }
        if draft.descriptionEdited == false, notes != HTMLSanitizer.plainText(draft.descriptionHTML) {
            draft.descriptionHTML = HTMLSanitizer.plainTextToHTML(notes)
            draft.descriptionEdited = true
        }
        self.draft = draft
        app.calendar.ui.save(draft)
    }

    // MARK: Cards

    private var titleCard: some View {
        InsetCard(fill: theme.bgColor) {
            TextField("", text: binding.title, prompt: Text("Title").foregroundStyle(theme.inkFaintColor))
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.inkColor)
                .focused($titleFocused)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .accessibilityLabel("Title")
            RowDivider()
            HStack(spacing: 10) {
                Icon(.location, size: 18).foregroundStyle(theme.inkFaintColor)
                TextField("", text: binding.location, prompt: Text("Location").foregroundStyle(theme.inkFaintColor))
                    .font(PhoneFont.body)
                    .foregroundStyle(theme.inkColor)
                    .accessibilityLabel("Location")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
        }
    }

    private var timeCard: some View {
        let draft = binding
        return InsetCard(fill: theme.bgColor) {
            calendarRow
            RowDivider()
            PhoneRow {
                Text("All-day").font(PhoneFont.body).foregroundStyle(theme.inkColor)
            } trailing: {
                Toggle("All-day", isOn: draft.isAllDay).labelsHidden().tint(theme.accentColor)
            }
            RowDivider()
            dateRow("Starts", day: draft.wrappedValue.startDay, minute: draft.wrappedValue.startMinute, datePicker: .startDate, timePicker: .startTime)
            expandedPicker(for: [.startDate, .startTime])
            RowDivider()
            dateRow("Ends", day: draft.wrappedValue.endDay, minute: draft.wrappedValue.endMinute, datePicker: .endDate, timePicker: .endTime)
            expandedPicker(for: [.endDate, .endTime])
            if !draft.wrappedValue.isValid {
                Text("The event ends before it starts.").font(PhoneFont.footnote).foregroundStyle(theme.negTextColor)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
            RowDivider()
            repeatRow
        }
    }

    private var calendarRow: some View {
        let writable = app.calendar.calendars.filter(\.canWrite)
        let current = app.calendar.calendar(binding.wrappedValue.calendar)
        return Menu {
            ForEach(writable) { ref in
                Button { binding.wrappedValue.calendar = ref.key } label: {
                    Text("\(ref.name) · \(ref.account.split(separator: "@").last.map(String.init) ?? "")")
                }
            }
        } label: {
            PhoneRow {
                Text("Calendar").font(PhoneFont.body).foregroundStyle(theme.inkColor)
            } trailing: {
                HStack(spacing: 6) {
                    Circle().fill(theme.color(for: current?.tint ?? .accent)).frame(width: 10, height: 10)
                    Text(calendarLabel(current)).font(PhoneFont.body).foregroundStyle(theme.inkDimColor).lineLimit(1)
                    Icon(.upDown, size: 14).foregroundStyle(theme.chevronColor)
                }
            }
        }
        .disabled(!(draft?.isNew ?? false))
        .accessibilityLabel("Calendar, \(calendarLabel(current))")
    }

    private func calendarLabel(_ ref: CalendarRef?) -> String {
        guard let ref else { return "Choose" }
        return "\(ref.name) · \(ref.account.split(separator: "@").last.map(String.init) ?? "")"
    }

    private func dateRow(_ label: String, day: CivilDate, minute: Int, datePicker: Picker, timePicker: Picker) -> some View {
        PhoneRow {
            Text(label).font(PhoneFont.body).foregroundStyle(theme.inkColor)
        } trailing: {
            HStack(spacing: 8) {
                pill(CalendarText.editorDate(day).replacingOccurrences(of: ", \(day.year)", with: ""), selected: expanded == datePicker, accent: false) {
                    expanded = expanded == datePicker ? nil : datePicker
                }
                .accessibilityLabel("\(label) date, \(CalendarText.longDay(day))")
                if !(draft?.isAllDay ?? false) {
                    pill(CalendarText.clock(minutes: minute), selected: expanded == timePicker, accent: true) {
                        expanded = expanded == timePicker ? nil : timePicker
                    }
                    .accessibilityLabel("\(label) time, \(CalendarText.clock(minutes: minute))")
                }
            }
        }
    }

    private func pill(_ text: String, selected: Bool, accent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(accent ? PhoneFont.bodySemibold : PhoneFont.body)
                .monospacedDigit()
                .foregroundStyle(accent ? theme.brassInkColor : theme.inkColor)
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(accent ? theme.accentTintColor : theme.fillColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(accent || selected ? theme.accentColor : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func expandedPicker(for pickers: [Picker]) -> some View {
        if let open = expanded, pickers.contains(open) {
            let draft = binding
            let zone = app.zone
            switch open {
            case .startDate, .endDate:
                let isStart = open == .startDate
                DatePicker("", selection: Binding(
                    get: { (isStart ? draft.wrappedValue.startDay : draft.wrappedValue.endDay).startDate(in: zone).addingTimeInterval(12 * 3600) },
                    set: { date in
                        let day = CivilDate(date, in: zone)
                        if isStart { draft.wrappedValue.setStart(day: day) } else { draft.wrappedValue.endDay = day }
                    }), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.timeZone, zone)
                    .tint(theme.accentColor)
                    .padding(.horizontal, 8)
            case .startTime, .endTime:
                let isStart = open == .startTime
                DatePicker("", selection: Binding(
                    get: {
                        let d = draft.wrappedValue
                        return EventLayout.date(on: isStart ? d.startDay : d.endDay, minutes: isStart ? d.startMinute : d.endMinute, zone: zone)
                    },
                    set: { date in
                        let d = draft.wrappedValue
                        let day = isStart ? d.startDay : d.endDay
                        let minute = Int(EventLayout.minutes(of: date, from: day, zone: zone).rounded())
                        if isStart { draft.wrappedValue.setStart(minute: minute) } else { draft.wrappedValue.endMinute = max(0, min(1439, minute)) }
                    }), displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.timeZone, zone)
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)
                    .clipped()
            }
        }
    }

    private var repeatRow: some View {
        let draft = binding
        let kinds: [EventDraft.RepeatKind] = [.never, .daily, .weekly, .monthly, .yearly]
        return VStack(alignment: .leading, spacing: 0) {
            Menu {
                ForEach(kinds) { kind in
                    Button(kind.label) { draft.wrappedValue.repeatKind = kind }
                }
            } label: {
                PhoneRow(chevron: true) {
                    Text("Repeat").font(PhoneFont.body).foregroundStyle(theme.inkColor)
                } trailing: {
                    Text(repeatValue).font(PhoneFont.body).foregroundStyle(theme.inkDimColor).lineLimit(1)
                }
            }
            .accessibilityLabel("Repeat, \(repeatValue)")
            if draft.wrappedValue.repeatKind == .weekly, draft.wrappedValue.isNew || draft.wrappedValue.repeatChanged {
                HStack(spacing: 6) {
                    ForEach(Weekday.ordered(from: app.calendar.ui.firstWeekday), id: \.self) { day in
                        let on = draft.wrappedValue.weekdays.contains(day)
                        Button {
                            if on, draft.wrappedValue.weekdays.count > 1 { draft.wrappedValue.weekdays.remove(day) } else { draft.wrappedValue.weekdays.insert(day) }
                        } label: {
                            Text(String(day.shortName.prefix(2)))
                                .font(PhoneFont.footnoteSemibold)
                                .foregroundStyle(on ? theme.onAccentInk : theme.inkDimColor)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(on ? theme.accentColor : theme.fillColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(day.name)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            if let summary = draft.wrappedValue.repeatSummary(now: app.now()) {
                Text(summaryLine(summary)).font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
    }

    private var repeatValue: String {
        guard let draft else { return "" }
        switch draft.repeatKind {
        case .weekly:
            let days = Weekday.ordered(from: app.calendar.ui.firstWeekday).filter(draft.weekdays.contains)
            return draft.interval == 1 ? days.map(\.shortName).joined(separator: ", ") : "Every \(draft.interval) weeks"
        default: return draft.repeatKind.label
        }
    }

    /// "Weekly on Tue, Thu, Sat · started Aug 25".
    private func summaryLine(_ summary: String) -> String {
        guard let master = draft?.master, !(draft?.repeatChanged ?? true) else { return summary }
        let zone = master.start.zone ?? app.zone
        return "\(summary) · started \(CalendarText.shortDate(master.start.civilDate(in: zone)))"
    }

    private var alertCard: some View {
        let draft = binding
        return InsetCard(fill: theme.bgColor) {
            Menu {
                ForEach(EventAlert.presets, id: \.self) { alert in
                    Button(alert.label) { draft.wrappedValue.alert = alert; draft.wrappedValue.alertEdited = true }
                }
            } label: {
                PhoneRow {
                    Text("Alert").font(PhoneFont.body).foregroundStyle(theme.inkColor)
                } trailing: {
                    HStack(spacing: 6) {
                        Text(draft.wrappedValue.alert.label).font(PhoneFont.body).foregroundStyle(theme.inkDimColor)
                        Icon(.upDown, size: 14).foregroundStyle(theme.chevronColor)
                    }
                }
            }
            .accessibilityLabel("Alert, \(draft.wrappedValue.alert.label)")
            RowDivider()
            guestsSection
            if let link = draft.wrappedValue.original?.event.hangoutLink ?? draft.wrappedValue.original?.event.conferenceData?.videoURI,
               let url = URL(string: link) {
                RowDivider()
                Link(destination: url) {
                    HStack(spacing: 10) {
                        Icon(.video, size: 20)
                        Text("Join Google Meet").font(PhoneFont.body)
                        Spacer()
                    }
                    .foregroundStyle(theme.brassInkColor)
                    .padding(.horizontal, 16)
                    .frame(minHeight: PhoneMetrics.rowHeight)
                }
            }
        }
    }

    private var guestsSection: some View {
        let draft = binding
        let guests = draft.wrappedValue.attendees.filter { $0.isSelf != true && $0.resource != true }
        return VStack(alignment: .leading, spacing: 0) {
            PhoneRow {
                Text("Guests").font(PhoneFont.body).foregroundStyle(theme.inkColor)
            } trailing: {
                Text(guests.isEmpty ? "None" : CalendarText.replyCounts(guests)).font(PhoneFont.body).foregroundStyle(theme.inkDimColor).lineLimit(1)
            }
            ForEach(guests, id: \.email) { guest in
                HStack(spacing: 10) {
                    PhoneAvatar(name: guest.name, tint: AvatarTint.tint(forEmail: guest.email), size: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(guest.name).font(PhoneFont.secondary).foregroundStyle(theme.inkColor).lineLimit(1)
                        Text(guest.responseStatus?.guestLabel ?? "No reply").font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor)
                    }
                    Spacer()
                    if draft.wrappedValue.canEdit {
                        Button { draft.wrappedValue.removeGuest(guest.email) } label: {
                            Icon(.close, size: 14, lineWidth: 2).foregroundStyle(theme.inkDimColor).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(guest.name)")
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 4)
            }
            if draft.wrappedValue.canEdit {
                HStack(spacing: 10) {
                    Icon(.guests, size: 18).foregroundStyle(theme.inkFaintColor)
                    TextField("", text: $guestText, prompt: Text("Add guests by email").foregroundStyle(theme.inkFaintColor))
                        .font(PhoneFont.body)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { draft.wrappedValue.addGuests(from: guestText); guestText = "" }
                        .accessibilityLabel("Add guests by email")
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
            }
        }
    }

    private var notesCard: some View {
        ZStack(alignment: .topLeading) {
            if notes.isEmpty {
                Text("Notes").font(PhoneFont.body).foregroundStyle(theme.inkFaintColor).padding(.horizontal, 16).padding(.vertical, 14)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $notes)
                .font(PhoneFont.body)
                .foregroundStyle(theme.inkColor)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .frame(minHeight: 88)
                .accessibilityLabel("Notes")
                .onChange(of: notes) { _, value in
                    guard var d = draft else { return }
                    d.descriptionHTML = HTMLSanitizer.plainTextToHTML(value)
                    d.descriptionEdited = true
                    draft = d
                }
        }
        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
    }

    private var rsvpCard: some View {
        let ui = app.calendar.ui
        return InsetCard(fill: theme.bgColor) {
            VStack(alignment: .leading, spacing: 10) {
                Text(draft?.organizerName.map { "Invited by \($0)" } ?? "Invitation").font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor)
                HStack(spacing: 8) {
                    ForEach([(ResponseStatus.accepted, "Yes"), (.tentative, "Maybe"), (.declined, "No")], id: \.0) { status, title in
                        let chosen = draft?.rsvp == status
                        Button {
                            if let item = draft?.original { ui.rsvp(status, item); draft?.rsvp = status }
                        } label: {
                            Text(title)
                                .font(PhoneFont.secondarySemibold)
                                .foregroundStyle(chosen ? theme.onAccentInk : theme.inkColor)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(chosen ? theme.accentColor : theme.panelColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(chosen ? .clear : theme.line2Color, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
            }
            .padding(14)
        }
    }
}

extension ResponseStatus {
    /// "Going" / "Maybe" / "Not going" / "No reply" (guest list).
    var guestLabel: String {
        switch self {
        case .accepted: return "Going"
        case .tentative: return "Maybe"
        case .declined: return "Not going"
        case .needsAction: return "No reply"
        }
    }
}
