import SwiftUI
import ThubanDeskCore

/// Settings → Accounts (design artboard "Settings · Accounts"): linked Google accounts with Add / Sign out, the
/// OAuth client the user created (client ID + secret — needed before the first sign-in), Defaults, and a compact
/// Appearance card.
struct AccountsSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GoogleAccountsCard()
            OAuthClientCard()
            HStack(alignment: .top, spacing: 18) {
                DefaultsCard().frame(minWidth: 420, maxWidth: .infinity)
                CompactAppearanceCard().frame(maxWidth: .infinity)
            }
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
            ForEach(Array(app.accounts.enumerated()), id: \.element.id) { index, account in
                Hairline()
                AccountRow(account: account, isPrimary: index == 0, tint: index.isMultiple(of: 2) ? .accent : .signal)
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
                Button("Cancel") { app.cancelSignIn() }.buttonStyle(.thubanSecondary)
            }
        case .idle, .failed:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    Button { app.addAccount() } label: {
                        HStack(spacing: 7) { Icon(.plus, size: 15); Text("Add Google account") }
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 34))
                    .disabled(app.clientConfig == nil || app.isFixtureMode)
                    HStack(spacing: 6) {
                        Glyph(.lock, size: 14)
                        Text(app.clientConfig == nil ? "Enter your OAuth client below first." : "Opens Google sign-in in your browser. Thuban Desk never sees your password.")
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
                    Text(account.email).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(theme.inkColor)
                    if isPrimary { Chip("Primary", kind: .accent) }
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
            }
            Spacer(minLength: 12)
            status
            if account.disconnected {
                Button("Sign in again") { app.addAccount(loginHint: account.email) }.buttonStyle(.thubanSecondary)
            }
            Button("Sign out") { confirmSignOut() }
                .buttonStyle(GhostButtonStyle(height: 32))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var status: some View {
        HStack(spacing: 7) {
            Circle().fill(account.disconnected ? theme.negColor : theme.signalColor).frame(width: 7, height: 7)
            Text(statusText)
        }
        .font(ThubanFont.body(13))
        .foregroundStyle(account.disconnected ? theme.negTextColor : theme.inkDimColor)
    }

    private var statusText: String {
        if account.disconnected { return "Signed out by Google" }
        if let error = app.syncErrors[account.id] { return "Sync failed · \(error.prefix(40))" }
        guard let synced = account.lastSynced else { return "Not synced yet" }
        return "Synced \(DeskFormat.time(synced, zone: app.zone))"
    }

    private var calendarCount: Int { app.calendar.calendars.filter { $0.account == account.id }.count }

    private var linked: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: account.linkedAt)
    }

    private func confirmSignOut() {
        let id = account.id
        app.confirm(ConfirmRequest(
            title: "Sign out \(account.email)?",
            message: "Thuban Desk forgets this account's token and saved mail and events. Nothing in your Google account changes. You can sign in again any time.",
            actionLabel: "Sign out", destructive: true, workingLabel: "Signing out…") { confirmed in
                try await app.removeAccount(id, confirmed: confirmed)
            })
    }
}

// MARK: - OAuth client

private struct OAuthClientCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var message: (String, SettingsNote.Tone)?
    @State private var isSaving = false

    var body: some View {
        SettingsCard("Google OAuth client") {
            if app.clientConfig != nil { Chip("Configured", kind: .pos) }
        } content: {
            Hairline()
            VStack(alignment: .leading, spacing: 12) {
                Text("Create a “Desktop app” OAuth client in Google Cloud Console (APIs: Gmail, Google Calendar) and paste its ID and secret. They are stored only in this Mac's private credentials file.")
                    .font(ThubanFont.body(13)).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .bottom, spacing: 12) {
                    LabeledField("Client ID") {
                        TextField("1234567890-abc.apps.googleusercontent.com", text: $clientID)
                            .thubanField(mono: true, height: 32)
                            .accessibilityLabel("Client ID")
                    }
                    LabeledField("Client secret") {
                        SecureField("GOCSPX-…", text: $clientSecret)
                            .thubanField(mono: true, height: 32)
                            .accessibilityLabel("Client secret")
                    }
                    .frame(width: 240)
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .buttonStyle(SecondaryButtonStyle(height: 32))
                        .disabled(isSaving || app.isFixtureMode)
                }
                if let message { SettingsNote(text: message.0, tone: message.1) }
            }
            .padding(18)
        }
        .onAppear {
            clientID = app.clientConfig?.clientID ?? ""
            clientSecret = app.clientConfig?.clientSecret ?? ""
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await app.saveClientConfig(clientID: clientID, clientSecret: clientSecret)
            message = (app.clientConfig == nil ? "Client removed." : "Saved. Add a Google account to sign in.", .positive)
        } catch {
            message = (error.localizedDescription, .negative)
        }
    }
}

// MARK: - Defaults

private struct DefaultsCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SettingsCard("Defaults") {
            Hairline()
            SettingsRow("New events go to", detail: app.calendar.defaultCalendar.map { domain($0.account) }) {
                Menu {
                    ForEach(app.calendar.calendars.filter(\.canWrite)) { ref in
                        Button("\(ref.name) — \(ref.account)") { app.settings.defaultCalendar = ref.key }
                    }
                } label: {
                    MenuLabel(tint: app.calendar.defaultCalendar?.tint, text: app.calendar.defaultCalendar?.name ?? "Choose")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Hairline()
            SettingsRow("New mail is sent from", detail: "Replies use the account the thread arrived in") {
                Menu {
                    ForEach(app.accounts) { account in
                        Button(account.email) { app.settings.defaultSendAccount = account.id }
                    }
                } label: {
                    MenuLabel(tint: .accent, text: app.mail.defaultSendAccount.map(domain) ?? "Choose")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Hairline()
            SettingsRow("Week starts on") {
                Menu {
                    Button("Sunday") { app.settings.weekStartsOnMonday = false }
                    Button("Monday") { app.settings.weekStartsOnMonday = true }
                } label: {
                    MenuLabel(tint: nil, text: app.settings.weekStartsOnMonday ? "Monday" : "Sunday")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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

/// The design's select button: 32 pt, line2 border, optional tint dot, up/down chevrons.
private struct MenuLabel: View {
    @Environment(\.thubanTheme) private var theme
    var tint: CalendarTint?
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            if let tint { TintDot(tint: tint) }
            Text(text).font(ThubanFont.body(14)).foregroundStyle(theme.inkColor)
            Icon(.upDown, size: 13).foregroundStyle(theme.inkDimColor)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
    }
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
                    }
                }
                HStack(spacing: 5) {
                    ForEach(Array(card.dots.enumerated()), id: \.offset) { _, hex in
                        // Scheme swatches preview other schemes' raw colours (the one place a hex is drawn).
                        Circle().fill(Color(hex: hex)).frame(width: 11, height: 11)
                    }
                }
                SplitGroundSwatch(lightBg: card.lightBg, lightPanel: card.lightBg, darkBg: card.darkBg, darkPanel: card.darkBg).frame(height: 18)
            }
            .padding(10)
            .background(isSelected ? theme.accentTintColor : theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
                .strokeBorder(isSelected ? theme.accentColor : theme.lineColor, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(card.label) scheme")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
