import SwiftUI
import ThubanDeskCore

/// Settings → Accounts (design artboard "Settings · Accounts"): linked Google accounts (primary first) with Add /
/// Sign out, then Defaults beside a compact Appearance card (1 : 1.15), then the OAuth client. Before a client is
/// saved, a "Connect Google" card with the step-by-step setup comes first.
struct AccountsSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if app.clientConfig == nil && !app.isFixtureMode {
                SetupCard()
            }
            GoogleAccountsCard()
            RatioRow(ratios: [1, 1.15], spacing: 18) {
                DefaultsCard()
                CompactAppearanceCard()
            }
            if app.clientConfig != nil || app.isFixtureMode {
                OAuthClientCard()
            }
        }
    }
}

// MARK: - First-time setup

private struct SetupCard: View {
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SettingsCard("Connect Google · about 10 minutes, once") {
            Hairline()
            VStack(alignment: .leading, spacing: 20) {
                Text("Thuban Desk signs in with an OAuth client from your own Google Cloud project. Follow the steps, paste the client below, then add your account.")
                    .font(ThubanFont.body(13.5))
                    .foregroundStyle(theme.inkDimColor)
                    .fixedSize(horizontal: false, vertical: true)
                SetupStepsView()
                OAuthClientForm()
            }
            .padding(18)
        }
    }
}

// MARK: - Accounts

private struct GoogleAccountsCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Google accounts", count: app.accounts.count)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            if app.accounts.isEmpty {
                Hairline()
                Text("No account linked yet.")
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkDimColor)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
            ForEach(Array(app.accounts.enumerated()), id: \.element.id) { index, account in
                Hairline()
                AccountRow(account: account, isPrimary: index == 0, tint: app.accountTint(account.id))
            }
            Hairline()
            footer
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.bgColor)
        }
        .background(theme.panelColor)
        .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }

    @ViewBuilder
    private var footer: some View {
        switch app.signIn {
        case .waitingForBrowser:
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Finish signing in in your browser…").font(ThubanFont.body(14)).foregroundStyle(theme.inkColor)
                Button("Cancel") { app.cancelSignIn() }.buttonStyle(SecondaryButtonStyle(height: 32))
            }
        case .idle, .failed:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    Button { app.addAccount() } label: {
                        HStack(spacing: 7) { Icon(.plus, size: 15); Text("Add Google account") }
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 34))
                    .disabled(app.clientConfig == nil)
                    .help(app.isFixtureMode ? "Sign-in is off in fixture mode" : "Sign in with Google in your browser")
                    HStack(spacing: 6) {
                        ExternalGlyph(size: 13)
                        Text(app.clientConfig == nil ? "Save your OAuth client above first." : "Opens Google sign-in in your browser. Thuban Desk never sees your password.")
                    }
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkDimColor)
                }
                if case .failed(let message) = app.signIn { SettingsNote(text: message, tone: .negative) }
            }
        }
    }
}

private struct AccountRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var account: GoogleAccount
    var isPrimary: Bool
    var tint: CalendarTint

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(name: account.displayName ?? account.email, tint: tint, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(account.email).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(theme.inkColor).lineLimit(1)
                    if isPrimary {
                        Chip("Primary", kind: .accent).help("The earliest linked account. New events and mail use it unless Defaults say otherwise.")
                    }
                }
                HStack(spacing: 6) {
                    Text("Linked \(linked)")
                    Text("·")
                    Icon(.calendar, size: 13)
                    Text("Calendar · \(calendarCount) calendar\(calendarCount == 1 ? "" : "s")")
                    Text("·")
                    Icon(.mail, size: 13)
                    Text("Gmail")
                }
                .font(ThubanFont.body(13))
                .foregroundStyle(theme.inkDimColor)
                .lineLimit(1)
            }
            Spacer(minLength: 12)
            status
            if account.disconnected {
                Button("Sign in again") { app.addAccount(loginHint: account.email) }
                    .buttonStyle(SecondaryButtonStyle(height: 32))
            }
            Button("Sign out") { confirmSignOut() }
                .buttonStyle(GhostButtonStyle(height: 32))
                .accessibilityLabel("Sign out \(account.email)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var status: some View {
        HStack(spacing: 7) {
            Circle().fill(account.disconnected || app.syncErrors[account.id] != nil ? theme.negColor : theme.signalColor).frame(width: 7, height: 7)
            Text(statusText).lineLimit(1)
        }
        .font(ThubanFont.body(13))
        .foregroundStyle(account.disconnected ? theme.negTextColor : theme.inkDimColor)
        .help(app.syncErrors[account.id] ?? "")
    }

    private var statusText: String {
        if account.disconnected { return "Signed out by Google" }
        if app.syncErrors[account.id] != nil { return "Sync failed" }
        guard let synced = account.lastSynced else { return "Not synced yet" }
        return "Synced \(DeskFormat.time(synced, zone: app.zone))"
    }

    private var calendarCount: Int { app.calendar.calendars.filter { $0.account == account.id }.count }

    private var linked: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = app.zone
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: account.linkedAt)
    }

    private func confirmSignOut() {
        let id = account.id
        let primaryNote = isPrimary && app.accounts.count > 1 ? " \(app.accounts[1].email) becomes your primary account." : ""
        app.confirm(ConfirmRequest(
            title: "Sign out \(account.email)?",
            message: "Thuban Desk forgets this account's token and saved mail and events.\(primaryNote) Nothing in your Google account changes, and you can sign in again any time.",
            actionLabel: "Sign out", destructive: true, workingLabel: "Signing out…") { confirmed in
                try await app.removeAccount(id, confirmed: confirmed)
            })
    }
}

// MARK: - OAuth client (configured)

/// "GOOGLE OAUTH CLIENT  ● Configured" with the client ID in mono; Change reveals the form; Setup guide opens the sheet.
private struct OAuthClientCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var editing = false

    var body: some View {
        SettingsCard("Google OAuth client") {
            Chip(app.clientConfig == nil ? "Not set" : "Configured", kind: app.clientConfig == nil ? .neg : .pos, dot: true)
        } content: {
            Hairline()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.clientConfig?.clientID ?? "No client saved")
                            .font(ThubanFont.mono(13))
                            .foregroundStyle(theme.inkColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Text("Desktop app client · stored only in this Mac's private credentials file")
                            .font(ThubanFont.body(12.5))
                            .foregroundStyle(theme.inkDimColor)
                    }
                    Spacer(minLength: 12)
                    Button("Setup guide") { app.showSetupGuide() }
                        .buttonStyle(GhostButtonStyle(height: 32, tinted: true))
                    Button(editing ? "Close" : "Change") { editing.toggle() }
                        .buttonStyle(SecondaryButtonStyle(height: 32))
                }
                if editing {
                    OAuthClientForm()
                }
            }
            .padding(18)
        }
    }
}

// MARK: - Defaults

private struct DefaultsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        SettingsCard("Defaults") {
            Hairline()
            SettingsRow("New events go to", detail: app.calendar.defaultCalendar.map { domain($0.account) }) {
                DeskMenu(tint: app.calendar.defaultCalendar?.tint, text: app.calendar.defaultCalendar?.name ?? "Choose", label: "Default calendar") {
                    ForEach(app.accounts) { account in
                        Section(account.email) {
                            ForEach(app.calendar.calendars.filter { $0.canWrite && $0.account == account.id }) { ref in
                                Button(ref.name) { app.settings.defaultCalendar = ref.key }
                            }
                        }
                    }
                }
            }
            Hairline()
            SettingsRow("New mail is sent from", detail: "Replies use the account the thread arrived in") {
                DeskMenu(tint: app.mail.defaultSendAccount.map { app.accountTint($0) }, text: app.mail.defaultSendAccount.map(domain) ?? "Choose", label: "Default sending account") {
                    ForEach(app.accounts) { account in
                        Button(account.email) { app.settings.defaultSendAccount = account.id }
                    }
                }
            }
            Hairline()
            SettingsRow("Week starts on") {
                DeskMenu(tint: nil, text: app.settings.weekStartsOnMonday ? "Monday" : "Sunday", label: "Week starts on") {
                    Button("Sunday") { app.settings.weekStartsOnMonday = false }
                    Button("Monday") { app.settings.weekStartsOnMonday = true }
                }
            }
            Hairline()
            SettingsRow("Calendar opens in", detail: "Day, week or month; the last one you used is kept") {
                DeskMenu(tint: nil, text: app.settings.calendarViewMode.label, label: "Calendar view") {
                    ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                        Button(mode.label) { app.settings.calendarViewMode = mode }
                    }
                }
            }
            Hairline()
            SettingsRow("Show declined events") {
                ThubanToggle(isOn: Binding(get: { app.settings.showDeclinedEvents }, set: { app.settings.showDeclinedEvents = $0 }), label: "Show declined events")
            }
            Hairline()
            SettingsRow("Load remote images in mail", detail: "Trackers are blocked either way") {
                ThubanToggle(isOn: Binding(get: { app.settings.loadRemoteImages }, set: { app.settings.loadRemoteImages = $0 }), label: "Load remote images in mail")
            }
        }
    }

    private func domain(_ account: String) -> String { String(account.split(separator: "@").last ?? Substring(account)) }
}

// MARK: - Appearance (compact)

private struct CompactAppearanceCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SettingsCard("Appearance") {
            SegmentedPicker(selection: Binding(get: { app.themeSelection.mode }, set: { app.setAppearanceMode($0) }),
                            options: AppearanceMode.allCases.map { SegmentOption($0, $0.label) },
                            segmentHeight: SegmentedPickerHeight.toolbar)
                .fixedSize()
        } content: {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(SchemeCardModel.presets) { card in
                    CompactSchemeCard(card: card, isSelected: card.id == app.themeSelection.schemeId) { app.selectScheme(id: card.id) }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            Text("The same schemes as Thuban Study and Atlas. Calendar colors follow the scheme.")
                .font(ThubanFont.body(12.5)).foregroundStyle(theme.inkDimColor)
                .padding(18)
        }
    }
}

private struct CompactSchemeCard: View {
    @Environment(\.thubanTheme) private var theme
    var card: SchemeCardModel
    var isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text(card.label).font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(isSelected ? theme.brassInkColor : theme.inkColor)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if card.isDefault {
                        Text("Default").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.brassInkColor)
                            .padding(.horizontal, 5).frame(height: 19)
                            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius).strokeBorder(theme.accentColor, lineWidth: 1))
                            .fixedSize()
                    }
                }
                HStack(spacing: 5) {
                    ForEach(Array(card.dots.enumerated()), id: \.offset) { _, hex in
                        // Scheme swatches preview other schemes' raw colours (the one place a hex is drawn).
                        Circle().fill(Color(hex: hex)).frame(width: 11, height: 11)
                    }
                }
                HStack(spacing: 0) {
                    Color(hex: card.lightBg)
                    Color(hex: card.darkBg)
                }
                .frame(height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
            }
            .padding(10)
            .background(isSelected ? theme.accentTintColor : (hovering ? theme.panel2Color : theme.panelColor),
                        in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
                .strokeBorder(isSelected ? theme.accentColor : theme.lineColor, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(card.label) scheme")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Menu button

/// The design's select button: 32 pt, line2 border, optional tint dot, up/down chevrons; opens a native menu.
struct DeskMenu<Items: View>: View {
    @Environment(\.thubanTheme) private var theme
    var tint: CalendarTint?
    var text: String
    var label: String
    @ViewBuilder var items: () -> Items

    var body: some View {
        Menu {
            items()
        } label: {
            HStack(spacing: 8) {
                if let tint { TintDot(tint: tint) }
                Text(text).font(ThubanFont.body(14)).foregroundStyle(theme.inkColor).lineLimit(1)
                Icon(.upDown, size: 13).foregroundStyle(theme.inkDimColor)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("\(label): \(text)")
    }
}

// MARK: - Layout

/// Children side by side at fixed width ratios (the design's `1fr 1.15fr` grid), top-aligned.
struct RatioRow: Layout {
    var ratios: [CGFloat]
    var spacing: CGFloat

    private func widths(total: CGFloat, count: Int) -> [CGFloat] {
        let ratios = (0..<count).map { $0 < self.ratios.count ? self.ratios[$0] : 1 }
        let sum = ratios.reduce(0, +)
        let available = max(0, total - spacing * CGFloat(max(0, count - 1)))
        return ratios.map { available * $0 / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 900
        let columns = widths(total: total, count: subviews.count)
        let height = zip(subviews, columns).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(total: bounds.width, count: subviews.count)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: nil))
            x += width + spacing
        }
    }
}
