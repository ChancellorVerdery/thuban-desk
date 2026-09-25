import AppKit
import SwiftUI
import ThubanDeskCore

// MARK: - Calendar

/// Settings → Calendar: every calendar by account with Show (local only — Google's own setting is untouched) and a
/// colour role; the default calendar is marked.
struct CalendarSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if app.calendar.calendars.isEmpty {
                PlaceholderPane(icon: .calendar, text: app.hasAccounts ? "Loading your calendars…" : "Link a Google account to see its calendars.")
            }
            ForEach(app.accounts) { account in
                let refs = app.calendar.calendars.filter { $0.account == account.id }
                if !refs.isEmpty {
                    SettingsCard(account.email) {
                        Text("\(refs.filter { !$0.isHidden }.count) of \(refs.count) shown").font(ThubanFont.body(12.5)).foregroundStyle(theme.inkDimColor)
                    } content: {
                        ForEach(refs) { ref in
                            Hairline()
                            CalendarSettingsRow(ref: ref, isDefault: app.calendar.defaultCalendar?.key == ref.key)
                        }
                    }
                }
            }
            SettingsNote(text: "Hiding a calendar only hides it in Thuban Desk. Colors are the scheme's roles, so every scheme stays readable; Default follows the color you picked in Google Calendar.")
        }
    }
}

private struct CalendarSettingsRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var ref: CalendarRef
    var isDefault: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(theme.color(for: ref.tint)).frame(width: 4, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(ref.name).font(ThubanFont.body(14.5, weight: .medium)).foregroundStyle(theme.inkColor).lineLimit(1)
                    if isDefault { Chip("New events", kind: .accent) }
                    if ref.isPrimary { Chip("Primary", kind: .neutral) }
                }
                if !ref.canWrite {
                    Text("Read-only").font(ThubanFont.body(12.5)).foregroundStyle(theme.inkDimColor)
                }
            }
            Spacer(minLength: 12)
            DeskMenu(tint: ref.tint, text: ref.tint.label, label: "\(ref.name) color") {
                Button("Default (from Google)") { app.calendar.setTint(nil, ref.key) }
                Divider()
                ForEach(CalendarTint.allCases, id: \.self) { tint in
                    Button(tint.label) { app.calendar.setTint(tint, ref.key) }
                }
            }
            ThubanToggle(isOn: Binding(get: { !ref.isHidden }, set: { app.calendar.setHidden(!$0, ref.key) }), label: "Show \(ref.name)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .opacity(ref.isHidden ? 0.7 : 1)
    }
}

// MARK: - Mail

/// Settings → Mail: sending account, remote images, each account's signature (from Gmail, read-only), and the
/// "Needs a reply" threads marked Done.
struct MailSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Sending") {
                Hairline()
                SettingsRow("New mail is sent from", detail: "Replies and forwards always use the account the thread arrived in") {
                    DeskMenu(tint: app.mail.defaultSendAccount.map { app.accountTint($0) }, text: app.mail.defaultSendAccount ?? "Choose", label: "Default sending account") {
                        ForEach(app.accounts) { account in
                            Button(account.email) { app.settings.defaultSendAccount = account.id }
                        }
                    }
                }
                Hairline()
                SettingsRow("Ask before sending", detail: "Every message is confirmed in a sheet before it leaves. This can’t be turned off.") {
                    Chip("Always", kind: .pos, dot: true)
                }
            }
            SettingsCard("Reading") {
                Hairline()
                SettingsRow("Load remote images", detail: "Off: images from the web load only when you press Load images. Trackers are blocked either way.") {
                    ThubanToggle(isOn: Binding(get: { app.settings.loadRemoteImages }, set: { app.settings.loadRemoteImages = $0 }), label: "Load remote images")
                }
                Hairline()
                SettingsRow("Threads marked Done in Today", detail: "They stay out of “Needs a reply” even if they still ask something") {
                    HStack(spacing: 10) {
                        Text("\(app.settings.dismissedNeedsReply.count)").font(ThubanFont.mono(13)).foregroundStyle(theme.inkDimColor)
                        Button("Reset") { app.settings.dismissedNeedsReply = [] }
                            .buttonStyle(SecondaryButtonStyle(height: 30))
                            .disabled(app.settings.dismissedNeedsReply.isEmpty)
                    }
                }
            }
            SettingsCard("Signatures") {
                Text("From Gmail").font(ThubanFont.body(12.5)).foregroundStyle(theme.inkDimColor)
            } content: {
                ForEach(app.accounts) { account in
                    Hairline()
                    HStack(alignment: .top, spacing: 14) {
                        TintDot(tint: app.accountTint(account.id)).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.email).font(ThubanFont.body(14.5, weight: .medium)).foregroundStyle(theme.inkColor)
                            Text(signature(account.id))
                                .font(ThubanFont.body(13))
                                .foregroundStyle(theme.inkDimColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
                Hairline()
                SettingsNote(text: "Signatures are edited in Gmail’s settings; Thuban Desk adds them to new messages.")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
        }
    }

    private func signature(_ account: String) -> String {
        guard let html = app.mail.sendAs[account]?.signature, !html.isEmpty else { return "No signature" }
        return HTMLSanitizer.plainText(html).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Filters

/// Settings → Filters: each account's Gmail filters in words ("From statements@… → Label “Receipts”").
struct FiltersSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(app.accounts) { account in
                let filters = app.mail.filters[account.id] ?? []
                SettingsCard(account.email) {
                    Text("\(filters.count) filter\(filters.count == 1 ? "" : "s")").font(ThubanFont.body(12.5)).foregroundStyle(theme.inkDimColor)
                } content: {
                    if filters.isEmpty {
                        Hairline()
                        Text("No filters.").font(ThubanFont.body(14)).foregroundStyle(theme.inkDimColor).padding(.horizontal, 18).padding(.vertical, 12)
                    }
                    ForEach(Array(filters.enumerated()), id: \.offset) { _, filter in
                        Hairline()
                        HStack(spacing: 12) {
                            Icon(.filter, size: 15).foregroundStyle(theme.inkDimColor)
                            Text(criteria(filter)).font(ThubanFont.body(14)).foregroundStyle(theme.inkColor).lineLimit(1)
                            Icon(.chevronRight, size: 13).foregroundStyle(theme.inkFaintColor)
                            Text(action(filter, account: account.id)).font(ThubanFont.body(14)).foregroundStyle(theme.inkDimColor).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                    }
                }
            }
            SettingsNote(text: "To add one, open a message in Mail and choose Filter messages like this. Edit or delete filters in Gmail’s settings.")
        }
    }

    private func criteria(_ filter: GmailFilter) -> String {
        guard let c = filter.criteria else { return "Any message" }
        var parts: [String] = []
        if let from = c.from { parts.append("From \(from)") }
        if let to = c.to { parts.append("To \(to)") }
        if let subject = c.subject { parts.append("Subject “\(subject)”") }
        if let query = c.query { parts.append("Matching “\(query)”") }
        if c.hasAttachment == true { parts.append("With attachment") }
        return parts.isEmpty ? "Any message" : parts.joined(separator: ", ")
    }

    private func action(_ filter: GmailFilter, account: String) -> String {
        guard let a = filter.action else { return "No action" }
        let labels = app.mail.labels[account] ?? []
        func name(_ id: String) -> String { labels.first { $0.id == id }?.name ?? id }
        var parts: [String] = []
        for id in a.addLabelIds ?? [] {
            switch id {
            case GmailSystemLabel.starred: parts.append("Star")
            case GmailSystemLabel.important: parts.append("Mark important")
            case GmailSystemLabel.trash: parts.append("Delete")
            default: parts.append("Label “\(name(id))”")
            }
        }
        for id in a.removeLabelIds ?? [] {
            switch id {
            case GmailSystemLabel.inbox: parts.append("Skip the inbox")
            case GmailSystemLabel.unread: parts.append("Mark as read")
            case GmailSystemLabel.spam: parts.append("Never send to Spam")
            default: parts.append("Remove “\(name(id))”")
            }
        }
        if let forward = a.forward { parts.append("Forward to \(forward)") }
        return parts.isEmpty ? "No action" : parts.joined(separator: ", ")
    }
}

// MARK: - About

struct AboutSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                AppArtView(size: 56, theme: theme)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Thuban Desk").font(ThubanFont.display(24)).foregroundStyle(theme.inkColor)
                    Text("Version \(version) · Google Calendar and Gmail for macOS")
                        .font(ThubanFont.body(13.5)).foregroundStyle(theme.inkDimColor)
                }
                Spacer(minLength: 0)
                Button("Setup guide") { app.showSetupGuide() }.buttonStyle(SecondaryButtonStyle(height: 32))
            }
            .thubanPanel(padding: 20)

            SettingsCard("How your accounts are treated") {
                Hairline()
                VStack(alignment: .leading, spacing: 12) {
                    fact(.account, "Your Google tokens stay in a private file on this Mac (credentials.json, readable only by you). No Keychain, no Thuban server.")
                    fact(.mail, "Nothing is sent without a confirmation sheet. Deleting forever, emptying Trash, deleting an event and signing out confirm too.")
                    fact(.calendar, "Mail and events are cached on this Mac so the app opens instantly; signing out removes that account's cache.")
                    fact(.info, "Thuban Desk only talks to Google’s servers.")
                }
                .padding(18)
            }

            SettingsCard("On this Mac") {
                Hairline()
                SettingsRow("Data folder", detail: AppPaths.home.path) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.home]) }
                        .buttonStyle(SecondaryButtonStyle(height: 30))
                }
                Hairline()
                SettingsRow("Sync", detail: syncDetail) {
                    Button(app.isSyncing ? "Syncing…" : "Sync now") { Task { await app.refreshAll() } }
                        .buttonStyle(SecondaryButtonStyle(height: 30))
                        .disabled(app.isSyncing || !app.hasAccounts)
                }
            }

            if app.isFixtureMode {
                SettingsNote(text: "Fixture mode: sample data from an in-process fake Google. Nothing reaches the network and sending is disabled.", tone: .negative)
            }
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }

    private var syncDetail: String {
        let every = "Every \(app.settings.refreshMinutes) minutes"
        guard let last = app.lastSync else { return every }
        return "\(every) · last \(DeskFormat.time(last, zone: app.zone))"
    }

    private func fact(_ icon: IconName, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(icon, size: 15).foregroundStyle(theme.brassInkColor).padding(.top, 1)
            Text(text).font(ThubanFont.body(13.5)).foregroundStyle(theme.inkColor).fixedSize(horizontal: false, vertical: true)
        }
    }
}
