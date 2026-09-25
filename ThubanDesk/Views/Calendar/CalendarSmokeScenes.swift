import Foundation
import ThubanDeskCore

/// Calendar screens for the smoke walk (owned by the Calendar engineer). Names sort the PNGs: 20–29. Every scene
/// sets the state it needs (theme included) and nothing here ever saves, deletes or answers anything: the scope
/// dialog and the delete confirmation are only shown, then dismissed.
enum CalendarSmokeScenes {
    static let scenes: [SmokeScene] = [
        SmokeScene("20-calendar-week", settle: 2) { app in
            await reset(app, mode: .week)
        },
        SmokeScene("21-calendar-week-popover") { app in
            await reset(app, mode: .week)
            if let item = await find(app, "Study group", dayOffset: 0) { app.calendar.ui.select(item) }
        },
        SmokeScene("22-calendar-month", settle: 2) { app in
            await reset(app, mode: .month)
        },
        SmokeScene("23-calendar-day") { app in
            await reset(app, mode: .day)
        },
        SmokeScene("24-calendar-editor") { app in
            await reset(app, mode: .week)
            await openEditor(app, "Study group", dayOffset: 0)
        },
        SmokeScene("25-calendar-scope", settle: 2) { app in
            await reset(app, mode: .week)
            guard let gym = await find(app, "Gym", dayOffset: 0) else { return }
            let zone = app.zone
            let start = gym.event.startDate(in: zone).addingTimeInterval(30 * 60)
            let end = gym.event.endDate(in: zone).addingTimeInterval(30 * 60)
            let tz = gym.event.start.timeZone ?? zone.identifier
            // Shows the scope dialog for a dropped drag; the smoke never presses "Move events".
            app.calendar.ui.commitMove(gym, start: .timed(start, timeZone: tz), end: .timed(end, timeZone: tz))
        },
        SmokeScene("26-calendar-invitation") { app in
            await reset(app, mode: .week)
            if let item = await find(app, "Interview", dayOffset: 1) { app.calendar.ui.select(item) }
        },
        SmokeScene("26b-calendar-delete-confirm", capture: .sheet) { app in
            await reset(app, mode: .week)
            // Opens the ConfirmWriteSheet only; the harness captures it and dismisses it without confirming.
            if let item = await find(app, "Dinner with Mom", dayOffset: -4) { app.calendar.ui.requestDelete(item) }
        },
        SmokeScene("27-calendar-week-dark", settle: 2) { app in
            await reset(app, mode: .week, dark: true)
            if let item = await find(app, "Study group", dayOffset: 0) { app.calendar.ui.select(item) }
        },
        SmokeScene("28-calendar-editor-dark") { app in
            await reset(app, mode: .week, dark: true)
            await openEditor(app, "Study group", dayOffset: 0)
        },
        SmokeScene("28b-calendar-month-dark") { app in
            await reset(app, mode: .month, dark: true)
        },
        SmokeScene("29-calendar-new-event") { app in
            await reset(app, mode: .week)
            let ui = app.calendar.ui
            ui.newEvent(on: ui.today, startMinute: 16 * 60, endMinute: 17 * 60)
            ui.editor?.title = "Coffee with Sam"
            ui.editor?.location = "Starbucks · Student Union"
            ui.editor?.repeatKind = .weekly
            ui.editor?.weekdays = [.thursday]
            ui.editor?.endKind = .after
            ui.editor?.count = 6
        },
    ]

    /// Calendar area, light (or dark) Brass, nothing open, the design's week.
    @MainActor
    static func reset(_ app: AppModel, mode: CalendarViewMode, dark: Bool = false) async {
        app.setThemeSelection(ThemeSelection(mode: dark ? .dark : .light, schemeId: SchemePresets.defaultId, custom: nil))
        app.select(.calendar)
        app.searchText = ""
        let ui = app.calendar.ui
        ui.cancelScope()
        ui.editor = nil
        ui.closePopover()
        ui.errorMessage = nil
        ui.focus = nil
        ui.miniMonth = nil
        ui.setMode(mode)
        let range = ui.visibleRange
        await app.calendar.ensureEvents(from: range.start, to: range.end)
    }

    /// The event titled `prefix…` on today + `dayOffset`.
    @MainActor
    static func find(_ app: AppModel, _ prefix: String, dayOffset: Int) async -> AgendaEvent? {
        let ui = app.calendar.ui
        let day = ui.today.adding(days: dayOffset)
        await app.calendar.ensureEvents(from: day.startDate(in: app.zone), to: day.adding(days: 1).startDate(in: app.zone))
        return app.calendar.events(from: day.startDate(in: app.zone), to: day.adding(days: 1).startDate(in: app.zone))
            .first { $0.event.title.hasPrefix(prefix) }
    }

    @MainActor
    static func openEditor(_ app: AppModel, _ prefix: String, dayOffset: Int) async {
        guard let item = await find(app, prefix, dayOffset: dayOffset) else { return }
        let ui = app.calendar.ui
        let master = await ui.loadMaster(for: item)
        ui.editor = EventDraft(item: item, master: master, zone: app.zone, canEdit: ui.canEdit(item))
    }
}
