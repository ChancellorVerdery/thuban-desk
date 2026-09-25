import SwiftUI
import ThubanDeskCore

/// Today (design artboard "Today"): a 48 pt toolbar with the date, then two columns — the day's agenda (Done / Now /
/// free gaps / upcoming) and tomorrow on the left; "Needs a reply" threads, pending invitations with RSVP and the
/// rule footnote on the right. Re-renders every minute so Now and the countdowns stay current.
struct TodayAreaView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let model = TodayModel(app: app)
            VStack(spacing: 0) {
                TodayToolbar(model: model)
                ScrollView {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 16) {
                            AgendaCard(model: model)
                            TomorrowCard(model: model)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        VStack(alignment: .leading, spacing: 16) {
                            NeedsReplyCard(model: model)
                            InvitationsCard(model: model)
                            footnote
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                }
                .scrollIndicators(.automatic)
            }
        }
        // ⌘N ("New Event" in the menu while Today is showing) does what the toolbar's New event button does.
        .onChange(of: app.newItemRequest) { _, _ in
            guard app.area == .today else { return }
            app.requestNewEvent()
        }
        .task {
            let today = CivilDate(app.now(), in: app.zone)
            await app.calendar.ensureEvents(from: today.startDate(in: app.zone), to: today.adding(days: 2).startDate(in: app.zone))
        }
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 6) {
            Icon(.info, size: 13).padding(.top, 2)
            Text("A thread needs a reply when a person wrote to you directly, asked something, and you haven’t answered in 7 days. Newsletters and notifications never appear here.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(ThubanFont.body(12.5))
        .foregroundStyle(theme.inkFaintColor)
        .lineSpacing(2)
    }
}

// MARK: - Toolbar

private struct TodayToolbar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var model: TodayModel

    var body: some View {
        HStack(spacing: 12) {
            Text(Self.longDate(model.today))
                .font(ThubanFont.display(19))
                .foregroundStyle(theme.inkColor)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(ThubanFont.body(13.5))
                .foregroundStyle(theme.inkDimColor)
                .lineLimit(1)
            Spacer(minLength: 12)
            Button { app.requestNewEvent() } label: {
                HStack(spacing: 7) { Icon(.plus, size: 15); Text("New event") }
            }
            .buttonStyle(SecondaryButtonStyle(height: 32))
            .help("New event (opens Calendar)")
            Button { app.requestCompose() } label: {
                HStack(spacing: 7) { Icon(.mail, size: 15); Text("Compose") }
            }
            .buttonStyle(SecondaryButtonStyle(height: 32))
            .help("New message (opens Mail)")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(theme.bgColor)
        .thubanHairline(.bottom, color: theme.lineColor)
    }

    private var subtitle: String {
        var parts: [String] = []
        let left = model.remainingCount
        parts.append(left == 0 ? "Nothing else scheduled" : "\(left) event\(left == 1 ? "" : "s") ahead")
        if !model.replies.isEmpty { parts.append("\(model.replies.count) to answer") }
        if !model.invitations.isEmpty { parts.append("\(model.invitations.count) invitation\(model.invitations.count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    /// "Thursday, September 24".
    static func longDate(_ day: CivilDate) -> String {
        let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        return "\(day.weekday.name), \(months[day.month - 1]) \(day.day)"
    }
}

// MARK: - Shared bits

/// A Today card: panel, 1 px line border, radius 10.
struct TodayCard<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }
}

/// "Open week" / "Open Mail": 13 pt semibold brass text link.
struct TodayLinkButton: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.brassInkColor)
                .opacity(hovering ? 0.8 : 1)
                .underline(hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
