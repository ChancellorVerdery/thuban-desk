import SwiftUI
import ThubanDeskCore

/// "Change a repeating event" as an iOS action sheet over the editor (board "Change a repeating event"): the series
/// ("Gym · UREC repeats Tue, Thu, Sat at 7:00 AM"), the question, one row per scope from the core planner — Only this
/// event / Every Thursday like this / This and following events / All events — each with what happens, and Cancel.
/// Choosing a row runs it (the shared `CalendarUIState.confirmScope`; deletes still go through the confirm sheet).
struct ScopeActionSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var prompt: ScopePrompt

    var body: some View {
        let ui = app.calendar.ui
        let zone = app.calendar.calendar(prompt.item.calendar)?.zone ?? app.zone
        ZStack(alignment: .bottom) {
            theme.scrimColor
                .ignoresSafeArea()
                .onTapGesture { ui.cancelScope() }
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text(heading(zone: zone))
                            .font(PhoneFont.footnoteSemibold)
                            .foregroundStyle(theme.inkDimColor)
                        Text(question(zone: zone))
                            .font(PhoneFont.footnote)
                            .foregroundStyle(theme.inkDimColor)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(prompt.scopes, id: \.self) { scope in
                        Rectangle().fill(theme.lineColor).frame(height: 1)
                        Button {
                            ui.scope?.selected = scope
                            ui.confirmScope()
                        } label: {
                            VStack(spacing: 2) {
                                Text(scope.title)
                                    .font(PhoneFont.bodySemibold)
                                    .foregroundStyle(isDelete ? theme.negTextColor : theme.brassInkColor)
                                Text(CalendarText.scopeDetail(scope, action: prompt.action, master: prompt.master, instance: prompt.item.event, zone: zone))
                                    .font(PhoneFont.footnote)
                                    .foregroundStyle(theme.inkDimColor)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(ui.isWorking)
                    }
                }
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button { ui.cancelScope() } label: {
                    Text("Cancel")
                        .font(PhoneFont.bodySemibold)
                        .foregroundStyle(theme.inkColor)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var isDelete: Bool { if case .delete = prompt.action { return true } else { return false } }

    /// "Gym · UREC repeats Tue, Thu, Sat at 7:00 AM".
    private func heading(zone: TimeZone) -> String {
        guard let master = prompt.master else { return "\(prompt.item.event.title) repeats" }
        return "\(prompt.item.event.title) \(CalendarText.seriesSubtitle(master: master, zone: zone))"
    }

    /// The core prompt with its Markdown bold stripped (the sheet shows it as one quiet line).
    private func question(zone: TimeZone) -> String {
        CalendarText.scopePrompt(prompt.action, instance: prompt.item.event, zone: zone).replacingOccurrences(of: "**", with: "")
    }
}

/// The Calendars sheet (Calendar tab's list button): every account's calendars with visibility switches.
struct CalendarsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let byAccount = Dictionary(grouping: app.calendar.calendars, by: \.account)
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Calendars").font(PhoneFont.inlineTitle).foregroundStyle(theme.inkColor)
                Spacer()
            }
            .overlay(alignment: .trailing) { NavTextButton("Done", bold: true) { dismiss() }.padding(.trailing, 8) }
            .padding(.top, 12)
            .frame(minHeight: 56)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(app.accounts) { account in
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(account.email).padding(.horizontal, 4)
                            InsetCard(fill: theme.bgColor) {
                                let list = byAccount[account.id] ?? []
                                if list.isEmpty {
                                    Text("No calendars loaded yet.").font(PhoneFont.secondary).foregroundStyle(theme.inkDimColor).padding(16)
                                }
                                ForEach(Array(list.enumerated()), id: \.element.id) { index, ref in
                                    if index > 0 { RowDivider(inset: 44) }
                                    PhoneRow {
                                        HStack(spacing: 12) {
                                            Circle().fill(theme.color(for: ref.tint)).frame(width: 12, height: 12)
                                            Text(ref.name).font(PhoneFont.body).foregroundStyle(theme.inkColor).lineLimit(1)
                                        }
                                    } trailing: {
                                        Toggle(ref.name, isOn: Binding(get: { !ref.isHidden }, set: { app.calendar.setHidden(!$0, ref.key) }))
                                            .labelsHidden()
                                            .tint(theme.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(PhoneMetrics.gutter)
            }
        }
        .background(theme.panelColor.ignoresSafeArea())
        .presentationBackground(theme.panelColor)
        .presentationDetents([.medium, .large])
    }
}
