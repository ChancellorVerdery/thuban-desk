import SwiftUI
import ThubanDeskCore

/// Search (no board; the house list style): one field for mail and events. Events come from the loaded calendar
/// months (core `SearchMatch`), mail from Gmail search across every account (shared `DeskSearch`). Results are
/// inset cards: EVENTS · n and MAIL · n; recent searches when the field is empty.
struct SearchTab: View {
    var body: some View {
        NavigationStack {
            SearchScreen()
        }
    }
}

struct SearchScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    @FocusState private var focused: Bool
    @State private var search = DeskSearch.shared
    @AppStorage("phone.recentSearches") private var recentRaw = ""

    var body: some View {
        @Bindable var router = router
        PhoneScreen(title: "Search") {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                PhoneSearchField(text: $router.searchText, placeholder: "Mail and events", onSubmit: submit, focus: $focused)
                if search.query.isEmpty {
                    recents
                } else {
                    results
                }
            }
            .padding(.horizontal, PhoneMetrics.gutter)
            .padding(.bottom, 24)
        }
        .onChange(of: router.searchText) { _, text in search.update(text: text, app: app) }
        .onAppear {
            if router.searchText.isEmpty {
                if !SmokeHarness.isEnabled { focused = true }
            } else {
                search.update(text: router.searchText, app: app)
            }
        }
    }

    private var recents: some View {
        let items = recentRaw.split(separator: "\n").map(String.init)
        return VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                PhoneEmptyState(icon: .search, text: "Search subjects, people and events across every account.")
            } else {
                Eyebrow("Recent").padding(.horizontal, 4)
                InsetCard {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        if index > 0 { RowDivider(inset: 50) }
                        Button { router.searchText = item } label: {
                            PhoneRow {
                                HStack(spacing: 12) {
                                    Icon(.clock, size: 18).foregroundStyle(theme.inkFaintColor)
                                    Text(item).font(PhoneFont.body).foregroundStyle(theme.inkColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Eyebrow("Events · \(search.events.count)")
                    if search.isSearchingEvents { ProgressView().controlSize(.mini).tint(theme.brassInkColor) }
                }
                .padding(.horizontal, 4)
                InsetCard {
                    if search.events.isEmpty {
                        Text(search.isSearchingEvents ? "Searching…" : "No events match.").font(PhoneFont.secondary).foregroundStyle(theme.inkDimColor).padding(16)
                    }
                    ForEach(Array(search.events.prefix(8).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RowDivider(inset: 16) }
                        Button { remember(); app.calendar.ui.edit(item) } label: { eventRow(item) }
                            .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Eyebrow("Mail · \(search.threads.count)")
                    if search.isSearchingMail { ProgressView().controlSize(.mini).tint(theme.brassInkColor) }
                }
                .padding(.horizontal, 4)
                InsetCard {
                    if search.threads.isEmpty {
                        Text(search.isSearchingMail ? "Searching…" : "No mail matches.").font(PhoneFont.secondary).foregroundStyle(theme.inkDimColor).padding(16)
                    }
                    ForEach(Array(search.threads.prefix(12).enumerated()), id: \.element.id) { index, summary in
                        if index > 0 { RowDivider(inset: 30) }
                        Button { remember(); app.openThread(summary.key) } label: { ThreadRow(summary: summary) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func eventRow(_ item: AgendaEvent) -> some View {
        let zone = app.zone
        let day = CivilDate(item.start(in: zone), in: zone)
        return HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(day.weekday.shortName.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(theme.inkDimColor)
                Text("\(day.day)").font(PhoneFont.display(.headline)).foregroundStyle(theme.inkColor)
            }
            .frame(width: 40)
            RoundedRectangle(cornerRadius: 2).fill(theme.color(for: item.tint)).frame(width: 3).frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.event.title).font(PhoneFont.bodySemibold).foregroundStyle(theme.inkColor).lineLimit(1)
                Text(detail(item)).font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func detail(_ item: AgendaEvent) -> String {
        let zone = app.zone
        let day = CivilDate(item.start(in: zone), in: zone)
        var parts = ["\(CalendarText.shortMonth(day.month)) \(day.day)"]
        parts.append(item.event.isAllDay ? "All day" : CalendarText.timeRange(item.start(in: zone), item.end(in: zone), zone: zone))
        if let location = item.event.location, !location.isEmpty { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    private func submit() {
        search.update(text: router.searchText, app: app)
        remember()
    }

    private func remember() {
        let q = router.searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        var items = recentRaw.split(separator: "\n").map(String.init).filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        items.insert(q, at: 0)
        recentRaw = items.prefix(6).joined(separator: "\n")
    }
}
