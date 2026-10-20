import SwiftUI
import ThubanDeskCore

@main
struct ThubanDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var appModel: AppModel

    init() {
        // Must run before anything touches NSApplication (see SharedTheme): an icon-only launch exits here.
        SharedTheme.refreshIconAndExitIfRequested { AppIconRenderer.render(theme: $0) }
        _appModel = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup("Thuban Desk") {
            ShellView()
                .environment(appModel)
                .frame(minWidth: 1180, minHeight: 720)
                .task { await appModel.load() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(appModel.area == .mail ? "New Message" : "New Event") { appModel.newItemRequest += 1 }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(before: .toolbar) {
                CalendarViewCommands(app: appModel)
                Divider()
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appModel.openSettings(appModel.settingsPane) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Button("Search Mail and Events") { appModel.searchFocusRequest += 1 }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandMenu("Go") {
                Button("Calendar") { appModel.select(.calendar) }.keyboardShortcut("1", modifiers: .command)
                Button("Mail") { appModel.select(.mail) }.keyboardShortcut("2", modifiers: .command)
                Button("Today") { appModel.select(.today) }.keyboardShortcut("3", modifiers: .command)
                Divider()
                Button("Refresh") { Task { await appModel.refreshAll() } }.keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

/// Calendar navigation in the View menu (also on bare keys in the grid: ← → T D W M ⌫, see CalendarAreaView).
private struct CalendarViewCommands: View {
    var app: AppModel

    var body: some View {
        let ui = app.calendar.ui
        let inCalendar = app.area == .calendar && ui.editor == nil && ui.scope == nil
        Button("Today") { ui.goToday() }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(!inCalendar)
        Button("Previous") { ui.step(-1) }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(!inCalendar)
        Button("Next") { ui.step(1) }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(!inCalendar)
        Divider()
        Button("Day") { ui.setMode(.day) }
            .keyboardShortcut("1", modifiers: [.command, .control])
            .disabled(!inCalendar)
        Button("Week") { ui.setMode(.week) }
            .keyboardShortcut("2", modifiers: [.command, .control])
            .disabled(!inCalendar)
        Button("Month") { ui.setMode(.month) }
            .keyboardShortcut("3", modifiers: [.command, .control])
            .disabled(!inCalendar)
        Divider()
        Button("Delete Event…") { if let item = ui.selectedItem { ui.requestDelete(item) } }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!inCalendar || ui.selectedItem.map { !ui.canDelete($0) } ?? true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // `--refresh-icon` (sent by another Thuban app after a scheme change): stamp the icon and exit before any UI.
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
