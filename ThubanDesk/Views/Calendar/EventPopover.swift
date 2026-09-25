import AppKit
import SwiftUI
import ThubanDeskCore

/// Places the popover beside the clicked event: to its right when it sits in the left half of the area, else to its
/// left; vertically near the event, kept inside the area.
struct EventPopoverPlacement<Content: View>: View {
    var target: CGRect
    var container: CGSize
    @ViewBuilder var content: () -> Content
    @State private var height: CGFloat = 300

    var body: some View {
        let width = CalendarMetrics.popoverWidth
        let x: CGFloat = target.midX > container.width / 2 ? target.minX - 11 - width : target.maxX + 9
        let clampedX = max(8, min(container.width - width - 8, x))
        let top = max(CalendarMetrics.toolbarHeight + 8, min(container.height - height - 8, target.minY - 20))
        content()
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .offset(x: clampedX, y: top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.opacity)
    }
}

/// Event details (design: Main popover): calendar eyebrow, serif title, when / repeat / place / guests rows, the
/// description, then Edit · Duplicate · Delete — or Going? Accept · Maybe · Decline for an unanswered invitation.
struct EventPopover: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: AgendaEvent

    var body: some View {
        let ui = app.calendar.ui
        let event = item.event
        let ref = app.calendar.calendar(item.calendar)
        let invitation = event.needsResponse
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                TintDot(tint: item.tint, size: 8)
                Text(((ref?.name ?? "Calendar") + (invitation ? " · Invitation" : "")).uppercased())
                    .font(ThubanFont.micro)
                    .kerning(0.96)
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(1)
                Spacer(minLength: 4)
                IconButton(.close, label: "Close", size: 26, iconSize: 14) { ui.closePopover() }
                    .keyboardShortcut(.cancelAction)
            }
            Text(event.title)
                .font(ThubanFont.display(20))
                .foregroundStyle(theme.inkColor)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            detailRow(.clock, CalendarText.when(event, zone: app.zone))
            if let repeats = ui.repeatSummary(for: item) {
                detailRow(.repeats, repeats)
            }
            if let location = event.location, !location.isEmpty {
                detailRow(.location, location)
            }
            if let video = event.videoLink, let url = URL(string: video) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 8) {
                        Icon(.link, size: 14)
                        Text("Join \(event.conferenceData?.conferenceSolution?.name ?? "video call")")
                            .font(ThubanFont.body(13.5, weight: .semibold))
                    }
                    .foregroundStyle(theme.brassInkColor)
                }
                .buttonStyle(.plain)
                .help(video)
            }
            if let guests = CalendarText.guestSummary(event) {
                detailRow(.guests, guests)
            }
            let description = HTMLSanitizer.richText(event.description)
            if !description.characters.isEmpty {
                Text(description)
                    .font(ThubanFont.body(13.5))
                    .foregroundStyle(theme.inkColor)
                    .lineSpacing(3)
                    .lineLimit(7)
                    .tint(theme.accentStrongColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .thubanHairline(.top, color: theme.lineColor)
            }
            if invitation {
                rsvpFooter(ui)
            } else {
                actionFooter(ui, ref: ref)
            }
        }
        .padding(16)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
        .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.10), radius: 18, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Event details")
    }

    private func detailRow(_ icon: IconName, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Icon(icon, size: 14).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(ThubanFont.body(13.5))
        .foregroundStyle(theme.inkDimColor)
    }

    private func actionFooter(_ ui: CalendarUIState, ref: CalendarRef?) -> some View {
        HStack(spacing: 6) {
            if ui.canEdit(item) {
                Button("Edit") { ui.edit(item) }
                    .buttonStyle(SecondaryButtonStyle(height: 30))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Details") { ui.edit(item) }
                    .buttonStyle(SecondaryButtonStyle(height: 30))
            }
            Button("Duplicate") { ui.duplicate(item) }
                .buttonStyle(GhostButtonStyle(height: 30, horizontalPadding: 14))
            Spacer(minLength: 0)
            if ui.canDelete(item) {
                Button {
                    ui.requestDelete(item)
                } label: {
                    HStack(spacing: 7) {
                        Icon(.trash, size: 15)
                        Text("Delete")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.negTextColor)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Asks before deleting")
            }
        }
        .padding(.top, 10)
        .thubanHairline(.top, color: theme.lineColor)
    }

    private func rsvpFooter(_ ui: CalendarUIState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GOING?").font(ThubanFont.micro).kerning(0.96).foregroundStyle(theme.inkDimColor)
            HStack(spacing: 6) {
                Button {
                    ui.rsvp(.accepted, item)
                } label: {
                    HStack(spacing: 6) { Icon(.check, size: 15); Text("Accept") }.frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(height: 30))
                Button { ui.rsvp(.tentative, item) } label: { Text("Maybe").fixedSize() }
                    .buttonStyle(SecondaryButtonStyle(height: 30))
                Button { ui.rsvp(.declined, item) } label: { Text("Decline").fixedSize() }
                    .buttonStyle(SecondaryButtonStyle(height: 30))
            }
            Button("Open details") { ui.edit(item) }
                .buttonStyle(GhostButtonStyle(height: 26, tinted: true, horizontalPadding: 0))
        }
        .padding(.top, 10)
        .thubanHairline(.top, color: theme.lineColor)
    }
}
