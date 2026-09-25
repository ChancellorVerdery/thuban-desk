import SwiftUI
import ThubanDeskCore

/// Design sidebar (236 pt, panel): All inboxes · Pinned · Starred · Sent · Drafts · Archive · Spam · Trash, then
/// ACCOUNTS (each inbox, primary marked) and LABELS (merged by name across accounts) + New label, and at the
/// bottom "2 filters active · Manage".
struct MailSidebar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var newLabel = false

    var body: some View {
        let mail = app.mail
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 2) {
                        ForEach(MailFolder.system, id: \.self) { folder in
                            let scope = MailScope(folder: folder)
                            SidebarRow(title: folder == .inbox ? "All inboxes" : folder.title, icon: icon(folder),
                                       count: mail.folderCount(folder), isSelected: mail.scope == scope) { select(scope) }
                        }
                    }
                    if app.accounts.count > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            eyebrow("Accounts")
                            ForEach(app.accounts) { account in
                                let scope = MailScope(folder: .inbox, account: account.id)
                                SidebarRow(title: mail.accountDomain(account.id), suffix: account.id == app.primaryAccount?.id ? "· primary" : nil,
                                           dot: mail.accountTint(account.id), count: mail.folderCount(.inbox, account: account.id),
                                           isSelected: mail.scope == scope, faded: account.disconnected) { select(scope) }
                                    .help(account.id + (account.disconnected ? " — needs sign-in" : ""))
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        eyebrow("Labels")
                        ForEach(mail.mergedLabels) { label in
                            let scope = MailScope(folder: .label(label.name))
                            SidebarRow(title: label.name, icon: .label, count: label.unread > 0 ? label.unread : nil,
                                       isSelected: mail.scope == scope) { select(scope) }
                        }
                        Button { newLabel = true } label: {
                            HStack(spacing: 10) {
                                Icon(.plus, size: 15)
                                Text("New label").font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(theme.brassInkColor)
                            .padding(.horizontal, 9)
                            .frame(height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $newLabel, arrowEdge: .trailing) {
                            NewLabelForm(targets: []) { newLabel = false }
                                .environment(\.thubanTheme, theme)
                                .environment(app)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 14)
            }
            .scrollIndicators(.never)

            HStack(spacing: 8) {
                Icon(.filter, size: 14)
                Text(filtersText).font(ThubanFont.small)
                Spacer(minLength: 4)
                Button("Manage") { app.openSettings(.filters) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.brassInkColor)
                    .accessibilityLabel("Manage filters")
            }
            .foregroundStyle(theme.inkDimColor)
            .padding(.horizontal, 21)
            .padding(.bottom, 14)
        }
        .frame(width: 236)
        .frame(maxHeight: .infinity)
        .background(theme.panelColor)
        .thubanHairline(.trailing, color: theme.lineColor)
    }

    private var filtersText: String {
        let count = app.mail.activeFilterCount
        return count == 0 ? "No filters" : "\(count) filter\(count == 1 ? "" : "s") active"
    }

    private func select(_ scope: MailScope) {
        app.mail.selection = nil
        app.mail.scope = scope
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(ThubanFont.micro)
            .kerning(0.96)
            .foregroundStyle(theme.inkDimColor)
            .padding(.horizontal, 9)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func icon(_ folder: MailFolder) -> IconName {
        switch folder {
        case .inbox: return .inbox
        case .pinned: return .pin
        case .starred: return .star
        case .sent: return .sent
        case .drafts: return .drafts
        case .archive: return .archive
        case .spam: return .spam
        case .trash: return .trash
        case .label: return .label
        }
    }
}

/// One sidebar row: 30 pt, radius 7; selected = panel2 + line2 border, brass icon and count.
struct SidebarRow: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var suffix: String?
    var icon: IconName?
    var dot: CalendarTint?
    var count: Int?
    var isSelected: Bool
    var faded: Bool = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let dot {
                    TintDot(tint: dot, size: 8).padding(.horizontal, 3)
                } else if let icon {
                    Icon(icon, size: 15).foregroundStyle(isSelected ? theme.brassInkColor : theme.inkDimColor)
                }
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 14, weight: isSelected ? .semibold : .medium)).foregroundStyle(theme.inkColor)
                    if let suffix { Text(suffix).font(.system(size: 14)).foregroundStyle(theme.inkFaintColor) }
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text(String(count)).font(ThubanFont.mono(12)).foregroundStyle(isSelected ? theme.brassInkColor : theme.inkDimColor)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(isSelected ? theme.panel2Color : (hovering ? theme.panel2Color.opacity(0.55) : .clear),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(isSelected ? theme.line2Color : .clear, lineWidth: 1))
            .opacity(faded ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title + (count.map { ", \($0)" } ?? ""))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
