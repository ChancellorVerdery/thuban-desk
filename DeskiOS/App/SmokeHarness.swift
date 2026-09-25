import Foundation
import ThubanDeskCore
import UIKit
import os

/// iOS visual smoke (scripts/ios_smoke.sh), driven by `THUBAN_DESK_SMOKE=1` with the fixture backend
/// (`THUBAN_DESK_FIXTURES=1`, in-process fake Google, sends refused) and the clock pinned to Thu Sep 24 2:40 PM.
/// The app walks the scenes; after each one settles it writes `Documents/smoke/state.txt` = "<index> <name>", the
/// host takes `xcrun simctl io <udid> screenshot <name>.png` and answers with `Documents/smoke/ack.txt` = "<index>".
/// "done" ends the walk. Nothing is ever confirmed: a scene that opens the confirm sheet is captured and dismissed.
@MainActor
enum SmokeHarness {
    static let variable = "THUBAN_DESK_SMOKE"
    private static let logger = Logger(subsystem: "org.thuban.desk.ios", category: "smoke")

    static var isEnabled: Bool { ProcessInfo.processInfo.environment[variable] == "1" }

    static var filter: [String] {
        (ProcessInfo.processInfo.environment["THUBAN_DESK_SMOKE_SCENES"] ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("smoke", isDirectory: true)
    }

    struct Scene {
        var name: String
        var settle: Double = 1.6
        var prepare: @MainActor (AppModel, PhoneRouter) async -> Void
    }

    static func startIfEnabled(app: AppModel) {
        guard isEnabled else { return }
        Task { await run(app: app) }
    }

    private static func run(app: AppModel) async {
        let router = PhoneRouter.shared
        let fm = FileManager.default
        try? fm.removeItem(at: directory)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard app.isFixtureMode else {
            write("error smoke requires THUBAN_DESK_FIXTURES=1", to: "state.txt")
            return
        }
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        await sleep(2.5)
        let words = filter
        let scenes = (isPad ? padScenes : phoneScenes).filter { scene in words.isEmpty || words.contains { scene.name.contains($0) } }
        for (index, scene) in scenes.enumerated() {
            await reset(app, router)
            await scene.prepare(app, router)
            await sleep(scene.settle)
            write("\(index) \(scene.name)", to: "state.txt")
            print("smoke: \(scene.name)")
            if !(await waitForAck(index)) { logger.error("smoke: no ack for \(scene.name, privacy: .public)"); break }
        }
        await reset(app, router)
        if let fixture = app.fixture {
            let sends = fixture.log.filter { $0.hasSuffix("/messages/send") || $0.hasSuffix("/drafts/send") }
            if !sends.isEmpty { write("error a send endpoint was called: \(sends)", to: "state.txt"); return }
        }
        write("done", to: "state.txt")
    }

    // MARK: Scenes

    static var phoneScenes: [Scene] {
        [
            Scene(name: "01-today") { _, router in router.tab = .today },
            Scene(name: "02-calendar-day") { app, router in
                router.tab = .calendar
                router.calendarMode = .day
                app.calendar.ui.goToday()
            },
            Scene(name: "03-calendar-3days") { _, router in router.tab = .calendar; router.calendarMode = .threeDays },
            Scene(name: "04-calendar-month", settle: 2) { _, router in router.tab = .calendar; router.calendarMode = .month },
            Scene(name: "05-mail-inbox", settle: 2) { _, router in router.showMailbox(MailScope()) },
            Scene(name: "06-mailboxes") { _, router in router.tab = .mail; router.mailPath = [] },
            Scene(name: "07-thread", settle: 2.5) { app, router in
                router.showMailbox(MailScope())
                if let key = await interviewThread(app) { router.showThread(key) }
            },
            Scene(name: "08-reply-sheet", settle: 2) { app, router in
                router.showMailbox(MailScope())
                guard let key = await interviewThread(app), let thread = try? await app.mail.thread(key),
                      let last = thread.messages.last(where: { !$0.isDraft && !$0.isSent }) else { return }
                router.showThread(key)
                await sleep(0.8)
                let model = PhoneComposeModel.reply(to: last, in: key, all: false, app: app)
                model.initialBody = replyBody
                model.savedAt = app.now().addingTimeInterval(60)
                router.compose = model
            },
            Scene(name: "09-send-confirm", settle: 1.5) { app, router in
                router.showMailbox(MailScope())
                guard let key = await interviewThread(app), let thread = try? await app.mail.thread(key),
                      let last = thread.messages.last(where: { !$0.isDraft && !$0.isSent }) else { return }
                let model = PhoneComposeModel.reply(to: last, in: key, all: false, app: app)
                model.initialBody = replyBody
                router.compose = model
                await sleep(1.2)
                model.bodyChanged(replyBody)
                model.requestSend { }
            },
            Scene(name: "10-event-editor", settle: 2) { app, router in
                router.tab = .calendar
                router.calendarMode = .day
                guard let gym = await gymToday(app) else { return }
                let master = await app.calendar.ui.loadMaster(for: gym)
                var draft = EventDraft(item: gym, master: master, zone: app.zone, canEdit: app.calendar.ui.canEdit(gym))
                draft.setStart(minute: 7 * 60 + 30)
                app.calendar.ui.editor = draft
            },
            Scene(name: "11-repeat-scope", settle: 2.5) { app, router in
                router.tab = .calendar
                guard let gym = await gymToday(app) else { return }
                let master = await app.calendar.ui.loadMaster(for: gym)
                var draft = EventDraft(item: gym, master: master, zone: app.zone, canEdit: true)
                draft.setStart(minute: 7 * 60 + 30)
                app.calendar.ui.editor = draft
                await sleep(1.0)
                app.calendar.ui.save(draft)
            },
            Scene(name: "12-search", settle: 2.5) { _, router in
                router.tab = .search
                router.searchText = "interview"
            },
            Scene(name: "13-settings") { _, router in router.tab = .today; router.todayPath = [.settings] },
            Scene(name: "14-account") { app, router in
                router.tab = .today
                router.todayPath = [.settings, .account(app.primaryAccount?.id ?? "")]
            },
            Scene(name: "15-calendars-sheet") { _, router in router.tab = .calendar; router.showCalendars = true },
            Scene(name: "16-label-picker") { app, router in
                router.showMailbox(MailScope())
                if let key = await interviewThread(app) { router.labelTargets = [key] }
            },
            Scene(name: "17-mail-dark-select", settle: 2) { app, router in
                app.setAppearanceMode(.dark)
                router.showMailbox(MailScope())
                router.mailSelecting = true
                app.mail.checked = Set(app.mail.visibleThreads.dropFirst(3).prefix(2).map(\.key))
            },
            Scene(name: "18-mail-dark", settle: 2) { app, router in
                app.setAppearanceMode(.dark)
                router.showMailbox(MailScope())
            },
            Scene(name: "19-today-dark") { app, router in app.setAppearanceMode(.dark); router.tab = .today },
            Scene(name: "20-calendar-dark") { app, router in
                app.setAppearanceMode(.dark)
                router.tab = .calendar
                router.calendarMode = .day
            },
            Scene(name: "21-thread-dark", settle: 2.5) { app, router in
                app.setAppearanceMode(.dark)
                router.showMailbox(MailScope())
                if let key = await interviewThread(app) { router.showThread(key) }
            },
        ]
    }

    static var padScenes: [Scene] {
        [
            Scene(name: "pad-01-mail", settle: 3) { app, router in
                router.padSection = .mail(MailScope())
                router.showMailbox(MailScope())
                if let key = await interviewThread(app) { router.padThread = key; await app.mail.open(key) }
            },
            Scene(name: "pad-02-today") { _, router in router.padSection = .today },
            Scene(name: "pad-03-calendar") { _, router in router.padSection = .calendar; router.calendarMode = .threeDays },
            Scene(name: "pad-04-month") { _, router in router.padSection = .calendar; router.calendarMode = .month },
            Scene(name: "pad-05-settings") { _, router in router.padSection = .settings },
            Scene(name: "pad-06-mail-dark", settle: 3) { app, router in
                app.setAppearanceMode(.dark)
                router.padSection = .mail(MailScope())
                router.showMailbox(MailScope())
                if let key = await interviewThread(app) { router.padThread = key }
            },
        ]
    }

    // MARK: Helpers

    static let replyBody = NSAttributedString(
        string: "Hi Priya,\n\nConfirmed for Friday at 3:00 PM. I just accepted the invite. Looking forward to meeting Marcus.\n\nThanks,",
        attributes: [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label])

    private static func reset(_ app: AppModel, _ router: PhoneRouter) async {
        app.pendingConfirmation = nil
        router.compose = nil
        router.showCalendars = false
        router.labelTargets = nil
        app.calendar.ui.scope = nil
        app.calendar.ui.editor = nil
        app.calendar.ui.errorMessage = nil
        router.mailSelecting = false
        app.mail.checked = []
        router.todayPath = []
        router.searchText = ""
        router.toast = nil
        app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
        await sleep(0.6)
    }

    static func interviewThread(_ app: AppModel) async -> ThreadKey? {
        for _ in 0..<20 {
            if let hit = app.mail.threads.first(where: { $0.subject.contains("Interview confirmed") }) { return hit.key }
            await sleep(0.25)
        }
        return nil
    }

    static func gymToday(_ app: AppModel) async -> AgendaEvent? {
        let zone = app.zone
        let today = CivilDate(app.now(), in: zone)
        await app.calendar.ensureEvents(from: today.startDate(in: zone), to: today.adding(days: 1).startDate(in: zone))
        return app.calendar.events(from: today.startDate(in: zone), to: today.adding(days: 1).startDate(in: zone))
            .first { $0.event.title.hasPrefix("Gym") }
    }

    private static func write(_ text: String, to name: String) {
        try? Data(text.utf8).write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    private static func waitForAck(_ index: Int) async -> Bool {
        let url = directory.appendingPathComponent("ack.txt")
        for _ in 0..<300 {
            if let text = try? String(contentsOf: url, encoding: .utf8), Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) == index {
                return true
            }
            await sleep(0.1)
        }
        return false
    }

    static func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
