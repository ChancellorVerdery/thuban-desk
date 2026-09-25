import AppKit
import SwiftUI
import ThubanDeskCore

/// Calendar (design: Main = Week, Month; plus Day): toolbar, sidebar (mini month, calendars by account, invitations),
/// the grid, the event popover, the editor sheet and the repeating-event scope dialog. Keyboard: ← / → move by the
/// view's period, T jumps to today, D / W / M switch views, Esc closes the top-most panel, ⌘N adds an event.
struct CalendarAreaView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let ui = app.calendar.ui
        let range = ui.visibleRange
        VStack(spacing: 0) {
            CalendarToolbar()
            HStack(spacing: 0) {
                CalendarSidebar()
                    .frame(width: CalendarMetrics.sidebarWidth)
                Group {
                    switch ui.mode {
                    case .month: MonthGridView(weeks: ui.monthWeeks(ui.focusMonth), month: ui.focusMonth)
                    case .week, .day: WeekGridView(days: ui.gridDays)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlayPreferenceValue(SelectedEventAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, let id = ui.selectedID, let item = ui.item(id: id) {
                    EventPopoverPlacement(target: proxy[anchor], container: proxy.size) {
                        EventPopover(item: item)
                    }
                }
            }
        }
        .overlay {
            if let draft = ui.editor {
                EditorOverlay(draft: draft)
            }
        }
        .overlay {
            if let prompt = ui.scope {
                ScopeOverlay(prompt: prompt)
            }
        }
        .overlay(alignment: .bottom) {
            if ui.errorMessage == nil, ui.editor == nil, ui.scope == nil {
                SearchMailPill().padding(.bottom, 18)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = ui.errorMessage {
                CalendarErrorBanner(message: message) { ui.errorMessage = nil }
                    .padding(.bottom, 18)
            }
        }
        .background(CalendarKeyMonitor())
        .task(id: RangeKey(range: range, calendars: app.calendar.visibleCalendars.map(\.id))) {
            app.calendar.visibleRange = range
            await app.calendar.ensureEvents(from: range.start, to: range.end)
            // Invitations in the sidebar look a few weeks ahead.
            let ahead = range.end.addingTimeInterval(21 * 86_400)
            await app.calendar.ensureEvents(from: range.end, to: ahead)
        }
        .onChange(of: app.newItemRequest) { _, _ in
            guard app.area == .calendar else { return }
            ui.newEvent()
        }
    }

    private struct RangeKey: Hashable {
        var range: DateInterval
        var calendars: [String]
    }
}

/// Shared sizes (design: Main.dc.html).
enum CalendarMetrics {
    static let sidebarWidth: CGFloat = 260
    static let toolbarHeight: CGFloat = 48
    static let gutter: CGFloat = 56
    static let hourHeight: CGFloat = 50
    static let headerHeight: CGFloat = 56
    static let popoverWidth: CGFloat = 332
}

// MARK: - Toolbar

/// Day / Week / Month · Today · ‹ › · title … Eastern Time · New event.
struct CalendarToolbar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let ui = app.calendar.ui
        HStack(spacing: 12) {
            SegmentedPicker(selection: Binding(get: { ui.mode }, set: { ui.setMode($0) }),
                            options: CalendarViewMode.allCases.map { SegmentOption($0, $0.label) },
                            segmentHeight: 26)
                .accessibilityLabel("View")
            Button("Today") { ui.goToday() }
                .buttonStyle(SecondaryButtonStyle(height: 30))
                .help("Go to today (T)")
            HStack(spacing: 2) {
                IconButton(.chevronLeft, label: "Previous", size: 30, iconSize: 15) { ui.step(-1) }
                IconButton(.chevronRight, label: "Next", size: 30, iconSize: 15) { ui.step(1) }
            }
            Text(ui.title)
                .font(ThubanFont.display(19))
                .foregroundStyle(theme.inkColor)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if ui.isWorking || app.calendar.isLoading {
                ProgressView().controlSize(.small).padding(.trailing, 4)
            }
            Text(app.zone.localizedName(for: .generic, locale: Locale(identifier: "en_US")) ?? app.zone.identifier)
                .font(ThubanFont.body(13))
                .foregroundStyle(theme.inkFaintColor)
                .padding(.trailing, 8)
            Button {
                ui.newEvent()
            } label: {
                HStack(spacing: 7) {
                    Icon(.plus, size: 15)
                    Text("New event")
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 32))
            .help("New event (⌘N)")
        }
        .padding(.horizontal, 16)
        .frame(height: CalendarMetrics.toolbarHeight)
        .frame(maxWidth: .infinity)
        .background(theme.bgColor)
        .thubanHairline(.bottom, color: theme.lineColor)
    }
}

// MARK: - Backgrounds

extension View {
    /// The design's day-column grounds: today warm, weekends a touch lighter than the page.
    @ViewBuilder
    func calendarDayGround(isToday: Bool, isWeekend: Bool, theme: ResolvedTheme, base: Color? = nil) -> some View {
        if isToday {
            background { ZStack { theme.panelColor; theme.accentTintColor.opacity(theme.isDark ? 0.35 : 0.45) } }
        } else if isWeekend {
            background { ZStack { theme.bgColor; theme.panelColor.opacity(0.55) } }
        } else if let base {
            background(base)
        } else {
            self
        }
    }
}

// MARK: - Error banner

struct CalendarErrorBanner: View {
    @Environment(\.thubanTheme) private var theme
    var message: String
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Icon(.info, size: 15).foregroundStyle(theme.negTextColor)
            Text(message).font(ThubanFont.body(13.5)).foregroundStyle(theme.inkColor).lineLimit(3)
            Button("Dismiss", action: dismiss).buttonStyle(GhostButtonStyle(height: 26))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.negColor.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.08), radius: 12, y: 4)
        .frame(maxWidth: 560)
    }
}

// MARK: - Keyboard

/// ← / → / T / D / W / M / Esc while the calendar is showing and no text field has focus.
struct CalendarKeyMonitor: NSViewRepresentable {
    @Environment(AppModel.self) private var app

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(app: app)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private var monitor: Any?

        func install(app: AppModel) {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak app] event in
                guard let app else { return event }
                // ⌘← ⌘→ ⌘⌫ are View-menu shortcuts in Calendar; while a text field is being edited they keep their
                // text meaning (line start / end, delete to line start), so hand them to the field editor first.
                if event.modifierFlags.intersection([.command, .control, .option]) == .command, [123, 124, 51].contains(event.keyCode),
                   let text = NSApp.keyWindow?.firstResponder as? NSTextView,
                   MainActor.assumeIsolated({ app.area == .calendar }) {
                    text.keyDown(with: event)
                    return nil
                }
                let keyCode = event.keyCode, characters = event.charactersIgnoringModifiers, flags = event.modifierFlags
                let handled = MainActor.assumeIsolated { Self.handle(keyCode: keyCode, characters: characters, flags: flags, app: app) }
                return handled ? nil : event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private static func handle(keyCode: UInt16, characters: String?, flags allFlags: NSEvent.ModifierFlags, app: AppModel) -> Bool {
            guard app.area == .calendar, app.pendingConfirmation == nil else { return false }
            let ui = app.calendar.ui
            let flags = allFlags.intersection([.command, .control, .option])
            guard flags.isEmpty else { return false }
            if keyCode == 53 { return ui.dismissTop() } // Escape
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSText || responder is NSTextView { return false }
            guard ui.editor == nil, ui.scope == nil else { return false }
            switch keyCode {
            case 123: ui.step(-1); return true // ←
            case 124: ui.step(1); return true // →
            case 51, 117: // ⌫ / ⌦: delete the selected event (through the confirm sheet)
                guard let item = ui.selectedItem, ui.canDelete(item) else { return false }
                ui.requestDelete(item)
                return true
            default: break
            }
            switch characters?.lowercased() {
            case "t": ui.goToday(); return true
            case "d": ui.setMode(.day); return true
            case "w": ui.setMode(.week); return true
            case "m": ui.setMode(.month); return true
            default: return false
            }
        }
    }
}
