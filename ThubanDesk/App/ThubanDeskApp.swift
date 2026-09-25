import SwiftUI
import ThubanDeskCore

@main
struct ThubanDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var appModel = AppModel()

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
                Button("New") { appModel.newItemRequest += 1 }
                    .keyboardShortcut("n", modifiers: .command)
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
