import SwiftUI
import ThubanDeskCore

/// "Change a repeating event" (design: RecurringScope): scrim over the calendar, a 500 pt card with the series,
/// the question and one radio card per scope, then Cancel · Move events / Save / Delete.
struct ScopeOverlay: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var prompt: ScopePrompt

    var body: some View {
        let ui = app.calendar.ui
        ZStack {
            theme.inkColor.opacity(theme.isDark ? 0 : 0.30)
                .overlay(Color.black.opacity(theme.isDark ? 0.5 : 0))
                .contentShape(Rectangle())
                .onTapGesture { ui.cancelScope() }
                .accessibilityHidden(true)
            ScopeDialog(prompt: prompt)
                .padding(.top, 158)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct ScopeDialog: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var prompt: ScopePrompt

    var body: some View {
        let ui = app.calendar.ui
        let zone = app.zone
        let item = prompt.item
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Icon(.repeats, size: 18)
                    .foregroundStyle(theme.brassInkColor)
                    .frame(width: 36, height: 36)
                    .background(theme.accentTintColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(CalendarText.scopeTitle(prompt.action))
                        .font(ThubanFont.display(20))
                        .foregroundStyle(theme.inkColor)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 6) {
                        TintDot(tint: item.tint, size: 7)
                        Text(item.event.title + (prompt.master.map { " · " + CalendarText.seriesSubtitle(master: $0, zone: zone) } ?? ""))
                            .lineLimit(1)
                    }
                    .font(ThubanFont.body(13.5))
                    .foregroundStyle(theme.inkDimColor)
                }
            }
            Text((try? AttributedString(markdown: CalendarText.scopePrompt(prompt.action, instance: item.event, zone: zone))) ?? AttributedString())
                .font(ThubanFont.body(14.5))
                .foregroundStyle(theme.inkColor)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                ForEach(prompt.scopes, id: \.self) { scope in
                    ScopeOption(title: scope.title,
                                detail: CalendarText.scopeDetail(scope, action: prompt.action, master: prompt.master, instance: item.event, zone: zone),
                                isSelected: prompt.selected == scope) {
                        ui.scope?.selected = scope
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Apply to")
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { ui.cancelScope() }
                    .buttonStyle(SecondaryButtonStyle(height: 34))
                    .keyboardShortcut(.cancelAction)
                Button(ui.isWorking ? "Saving…" : CalendarText.scopeButton(prompt.action)) { ui.confirmScope() }
                    .buttonStyle(PrimaryButtonStyle(height: 34))
                    .keyboardShortcut(.defaultAction)
                    .disabled(ui.isWorking)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 500)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
        .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.12), radius: 24, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(CalendarText.scopeTitle(prompt.action))
    }
}

private struct ScopeOption: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var detail: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                RadioDot(isOn: isSelected).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(ThubanFont.body(14.5, weight: .semibold)).foregroundStyle(theme.inkColor)
                    Text(detail).font(ThubanFont.body(13)).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.accentTintColor : theme.panelColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(isSelected ? theme.accentColor : theme.lineColor, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// 16 pt radio: accent ring 5 pt around a panel dot when on; a 1.5 pt line2 ring when off.
struct RadioDot: View {
    @Environment(\.thubanTheme) private var theme
    var isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(theme.accentColor)
                Circle().fill(theme.panelColor).frame(width: 6, height: 6)
            } else {
                Circle().fill(theme.panelColor)
                Circle().strokeBorder(theme.line2Color, lineWidth: 1.5)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}
