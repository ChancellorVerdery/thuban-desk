import SwiftUI
import ThubanDeskCore

/// The editor's form controls (design: EventEditor): 32 pt boxes with a line2 border on the field ground.
struct EditorBox<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var width: CGFloat?
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 8) { content() }
            .font(ThubanFont.body(14))
            .foregroundStyle(theme.inkColor)
            .padding(.horizontal, 10)
            .frame(width: width, height: 32, alignment: .leading)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Label column (96 pt, right-aligned, 13.5 dim) + controls.
struct EditorRow<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    var alignment: VerticalAlignment = .center
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: alignment, spacing: 12) {
            Text(label)
                .font(ThubanFont.body(13.5))
                .foregroundStyle(theme.inkDimColor)
                .frame(width: 96, alignment: .trailing)
                .padding(.top, alignment == .top ? 7 : 0)
            HStack(spacing: 8) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "Thu, Sep 24, 2026 ⌄" — opens a month to pick from.
struct DateBox: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Binding var day: CivilDate
    var label: String
    var width: CGFloat = 178
    @State private var open = false
    @State private var month: YearMonth?

    var body: some View {
        Button {
            month = YearMonth(day)
            open = true
        } label: {
            EditorBox(width: width) {
                Text(CalendarText.editorDate(day)).lineLimit(1)
                Spacer(minLength: 0)
                Icon(.chevronDown, size: 13).foregroundStyle(theme.inkFaintColor)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(CalendarText.longDay(day))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            MiniMonthView(month: month ?? YearMonth(day), highlighted: nil, today: app.calendar.ui.today,
                          firstWeekday: app.calendar.ui.firstWeekday, selected: day,
                          onPick: { picked in day = picked; open = false },
                          onMonth: { month = $0 })
                .frame(width: 228)
                .padding(14)
                .background(theme.panelColor)
                .environment(\.thubanTheme, theme)
        }
    }
}

/// "7:00 PM ⇅": type a time ("7:30p", "19:30") or step 15 minutes with the arrows / ↑ ↓.
struct TimeBox: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var minute: Int
    var label: String
    var width: CGFloat = 100
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        EditorBox(width: width) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(commit)
                .onKeyPress(.upArrow) { stepBy(15); return .handled }
                .onKeyPress(.downArrow) { stepBy(-15); return .handled }
                .accessibilityLabel(label)
            StepArrows(up: { stepBy(15) }, down: { stepBy(-15) })
        }
        .onAppear { text = CalendarText.clock(minutes: minute) }
        .onChange(of: minute) { _, value in if !focused { text = CalendarText.clock(minutes: value) } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        if let parsed = CalendarText.parseClock(text) { minute = parsed }
        text = CalendarText.clock(minutes: minute)
    }

    private func stepBy(_ delta: Int) {
        let base = CalendarText.parseClock(text) ?? minute
        let next = ((base + delta) / 15) * 15
        minute = max(0, min(24 * 60 - 15, next))
        text = CalendarText.clock(minutes: minute)
    }
}

/// "1 ⇅" — a small number with stepper arrows.
struct NumberBox: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var value: Int
    var label: String
    var range: ClosedRange<Int> = 1...99
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        EditorBox(width: 56) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(ThubanFont.mono(13))
                .focused($focused)
                .onSubmit(commit)
                .onKeyPress(.upArrow) { bump(1); return .handled }
                .onKeyPress(.downArrow) { bump(-1); return .handled }
                .accessibilityLabel(label)
            StepArrows(up: { bump(1) }, down: { bump(-1) })
        }
        .onAppear { text = "\(value)" }
        .onChange(of: value) { _, v in if !focused { text = "\(v)" } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        if let parsed = Int(text.trimmingCharacters(in: .whitespaces)) { value = min(range.upperBound, max(range.lowerBound, parsed)) }
        text = "\(value)"
    }

    private func bump(_ delta: Int) {
        value = min(range.upperBound, max(range.lowerBound, (Int(text) ?? value) + delta))
        text = "\(value)"
    }
}

/// The ⇅ icon split into an up half and a down half.
private struct StepArrows: View {
    @Environment(\.thubanTheme) private var theme
    var up: () -> Void
    var down: () -> Void

    var body: some View {
        Icon(.upDown, size: 13)
            .foregroundStyle(theme.inkFaintColor)
            .overlay {
                VStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle()).onTapGesture(perform: up)
                    Color.clear.contentShape(Rectangle()).onTapGesture(perform: down)
                }
                .frame(width: 18, height: 26)
            }
            .accessibilityElement()
            .accessibilityLabel("Step")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: up()
                case .decrement: down()
                @unknown default: break
                }
            }
    }
}

/// 38 × 22 switch (design: accent when on; seg ground with a panel knob when off).
struct EditorSwitch: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? theme.accentColor : theme.panel2Color)
                Capsule().strokeBorder(isOn ? .clear : theme.line2Color, lineWidth: 1)
                Circle()
                    .fill(theme.panelColor)
                    .overlay(Circle().strokeBorder(isOn ? .clear : theme.line2Color, lineWidth: 1))
                    .frame(width: 18, height: 18)
                    .padding(2)
            }
            .frame(width: 38, height: 22)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

/// S M T W T F S circles (design: 32 pt, accent fill when on).
struct WeekdayToggles: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var selection: Set<Weekday>
    var firstWeekday: Weekday

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Weekday.ordered(from: firstWeekday), id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { if selection.count > 1 { selection.remove(day) } } else { selection.insert(day) }
                } label: {
                    Text(String(day.shortName.prefix(1)))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? theme.onAccentColor : theme.inkDimColor)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(on ? theme.accentColor : theme.panelColor))
                        .overlay(Circle().strokeBorder(on ? theme.accentColor : theme.line2Color, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.name)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }
}

/// A radio line: ◉ label [control].
struct RadioLine<Control: View>: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    var isOn: Bool
    var action: () -> Void
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 10) {
            Button(action: action) {
                HStack(spacing: 10) {
                    RadioDot(isOn: isOn)
                    Text(label).font(ThubanFont.body(14)).foregroundStyle(theme.inkColor).frame(width: 44, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ends \(label.lowercased())")
            .accessibilityAddTraits(isOn ? [.isSelected] : [])
            control()
        }
        .frame(height: 32)
    }
}
