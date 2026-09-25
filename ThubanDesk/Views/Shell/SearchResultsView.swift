import SwiftUI
import ThubanDeskCore

/// The title-bar search on Today and Settings: matching events (upcoming first) beside matching mail from every
/// account. Clicking an event opens it in Calendar; a thread opens in Mail. (Mail and Calendar filter in place and
/// show the other half in a strip — `SearchEventsStrip`, `SearchMailPill`.)
struct SearchResultsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let search = DeskSearch.shared
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    PageTitle(title: "Search", subtitle: "“\(search.query)” in Mail and Calendar", size: 30)
                    Spacer()
                    Button("Clear") { app.searchText = "" }
                        .buttonStyle(GhostButtonStyle(height: 30))
                        .accessibilityLabel("Clear search")
                }
                HStack(alignment: .top, spacing: 20) {
                    column("Events", count: search.isSearchingEvents ? nil : search.events.count, loading: search.isSearchingEvents,
                           empty: "No events match.") {
                        ForEach(search.events) { item in SearchEventRow(item: item) }
                    }
                    column("Mail", count: search.hasMailResults ? search.threads.count : nil, loading: !search.hasMailResults,
                           empty: "No mail matches.") {
                        ForEach(search.threads) { summary in SearchThreadRow(summary: summary) }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.bgColor)
    }

    private func column<Rows: View>(_ title: String, count: Int?, loading: Bool, empty: String,
                                    @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title, count: count) {
                if loading { ProgressView().controlSize(.small) }
            }
            if !loading && count == 0 {
                Text(empty)
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkDimColor)
                    .padding(.vertical, 6)
            }
            rows()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// An event result: tint bar, title, "Fri, Sep 25 · 3:00 – 3:45 PM · Zoom".
struct SearchEventRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: AgendaEvent
    var compact = false

    var body: some View {
        let event = item.event
        let past = item.end(in: app.zone) <= app.now()
        ListRowCard(action: { app.openEvent(item) }) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(theme.color(for: item.tint))
                    .frame(width: 3, height: compact ? 30 : 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(ThubanFont.body(compact ? 13.5 : 14.5, weight: .semibold))
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(1)
                    Text(detail(event))
                        .font(ThubanFont.body(compact ? 12 : 13))
                        .foregroundStyle(theme.inkDimColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if event.needsResponse {
                    Text("Not answered")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.signalTextColor)
                }
            }
            .opacity(past ? 0.6 : 1)
        }
        .accessibilityLabel("\(event.title), \(CalendarText.shortWhen(event, zone: app.zone))")
        .help("Open in Calendar")
    }

    private func detail(_ event: CalendarEvent) -> String {
        var parts = [CalendarText.shortWhen(event, zone: app.zone)]
        if let place = MailInvite.place(event) { parts.append(place) }
        return parts.joined(separator: " · ")
    }
}

/// A mail result: account dot, sender, date, subject and snippet.
struct SearchThreadRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var summary: ThreadSummary

    var body: some View {
        let unread = summary.labelIDs.contains(GmailSystemLabel.unread)
        ListRowCard(action: { app.openThread(summary.key) }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    TintDot(tint: app.mail.accountTint(summary.account), size: 7)
                    Text(summary.from?.displayName ?? "(no sender)")
                        .font(ThubanFont.body(14, weight: unread ? .bold : .semibold))
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(DeskFormat.listDate(summary.date, now: app.now(), zone: app.zone))
                        .font(ThubanFont.mono(12))
                        .foregroundStyle(theme.inkDimColor)
                }
                Text(summary.subject.isEmpty ? "(no subject)" : summary.subject)
                    .font(ThubanFont.body(13.5, weight: unread ? .semibold : .regular))
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(1)
                Text(summary.snippet)
                    .font(ThubanFont.body(12.5))
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("\(summary.from?.displayName ?? ""), \(summary.subject)")
        .help("Open in Mail")
    }
}

/// Mail, while searching: the events that match too (up to three), above the thread list.
struct SearchEventsStrip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let search = DeskSearch.shared
        if !search.query.isEmpty, !search.events.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("Events", count: search.events.count) {
                    if search.events.count > 3 {
                        Button("Show all") { app.select(.today) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.brassInkColor)
                            .accessibilityLabel("Show all search results")
                    }
                }
                ForEach(search.events.prefix(3)) { item in SearchEventRow(item: item, compact: true) }
            }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
            .thubanHairline(.bottom, color: theme.lineColor)
        }
    }
}

/// Calendar, while searching: "3 emails match “interview” · Show in Mail" and the next matching event when it is
/// outside the shown range.
struct SearchMailPill: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let search = DeskSearch.shared
        let range = app.calendar.ui.visibleRange
        let outside = search.events.first { !range.contains($0.start(in: app.zone)) }
        if !search.query.isEmpty, (search.hasMailResults && !search.threads.isEmpty) || outside != nil {
            HStack(spacing: 12) {
                Icon(.search, size: 14).foregroundStyle(theme.inkDimColor)
                if let outside {
                    Button {
                        app.openEvent(outside)
                    } label: {
                        Text("Also \(CalendarText.shortDate(CivilDate(outside.start(in: app.zone), in: app.zone))): \(outside.event.title)")
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.brassInkColor)
                    .accessibilityLabel("Show \(outside.event.title) in Calendar")
                }
                if outside != nil, search.hasMailResults, !search.threads.isEmpty {
                    Rectangle().fill(theme.line2Color).frame(width: 1, height: 14)
                }
                if search.hasMailResults, !search.threads.isEmpty {
                    let n = search.threads.count
                    Button {
                        app.select(.mail)
                    } label: {
                        Text("\(n) \(n == 1 ? "email matches" : "emails match") · Show in Mail").lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.brassInkColor)
                    .accessibilityLabel("Show \(n) matching emails in Mail")
                }
            }
            .font(ThubanFont.body(13, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(theme.panelColor, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.line2Color, lineWidth: 1))
            .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.08), radius: 10, y: 3)
        }
    }
}
