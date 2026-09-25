import SwiftUI
import ThubanDeskCore

/// The invitation card in a message (design): day tile (weekday in the loss colour, serif date), title, time ·
/// place · guests, whether you're free then, and GOING? Yes / Maybe / No — answering patches your RSVP.
struct InvitationCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var invite: AgendaEvent
    @State private var working: ResponseStatus?
    @State private var error: String?

    var body: some View {
        let zone = app.zone
        let event = invite.event
        let start = event.startDate(in: zone)
        let dayEvents = app.calendar.events(from: CivilDate(start, in: zone).startDate(in: zone),
                                            to: CivilDate(start, in: zone).adding(days: 1).startDate(in: zone))
        let availability = MailInvite.availability(of: event, among: dayEvents, zone: zone)
        let response = event.selfResponse ?? .needsAction
        HStack(spacing: 14) {
            VStack(spacing: 1) {
                Text(weekday(start, zone: zone))
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.84)
                    .foregroundStyle(theme.negTextColor)
                Text(dayNumber(start, zone: zone))
                    .font(ThubanFont.display(21))
                    .foregroundStyle(theme.inkColor)
            }
            .frame(width: 48, height: 52)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(theme.inkColor).lineLimit(1)
                Text(MailInvite.detailLine(event, zone: zone)).font(.system(size: 13)).foregroundStyle(theme.inkDimColor).lineLimit(1)
                availabilityLine(availability)
                Button { app.openEvent(invite) } label: {
                    HStack(spacing: 5) {
                        Icon(.calendar, size: 12)
                        Text("Show in Calendar")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.brassInkColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .accessibilityLabel("Show \(event.title) in Calendar")
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(theme.negTextColor).lineLimit(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                Text("GOING?").font(.system(size: 12, weight: .semibold)).kerning(0.96).foregroundStyle(theme.inkDimColor)
                HStack(spacing: 2) {
                    ForEach([ResponseStatus.accepted, .tentative, .declined], id: \.self) { status in
                        rsvpButton(status, current: response)
                    }
                }
                .padding(3)
                .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("RSVP")
            }
        }
        .padding(14)
        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Invitation: \(event.title)")
    }

    @ViewBuilder
    private func availabilityLine(_ availability: MailInvite.Availability) -> some View {
        let text = MailInvite.availabilityText(availability, zone: app.zone)
        switch availability {
        case .conflict:
            HStack(spacing: 5) {
                Icon(.info, size: 12, lineWidth: 2.2)
                Text(text)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(theme.negTextColor)
        case .free:
            HStack(spacing: 5) {
                Icon(.check, size: 12, lineWidth: 2.2)
                Text(text)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(theme.posTextColor)
        case .allDay:
            EmptyView()
        }
    }

    private func rsvpButton(_ status: ResponseStatus, current: ResponseStatus) -> some View {
        let selected = status == current
        return Button {
            answer(status)
        } label: {
            Text(working == status ? "…" : status.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(selected ? theme.panelColor : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(selected ? theme.line2Color : .clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(working != nil)
        .accessibilityLabel(status.label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func answer(_ status: ResponseStatus) {
        guard invite.event.selfResponse != status else { return }
        working = status
        error = nil
        Task {
            defer { working = nil }
            do { try await app.calendar.rsvp(status, to: invite.event, in: invite.calendar) } catch { self.error = error.localizedDescription }
        }
    }

    private func weekday(_ date: Date, zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = zone
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private func dayNumber(_ date: Date, zone: TimeZone) -> String {
        String(CivilDate(date, in: zone).day)
    }
}
