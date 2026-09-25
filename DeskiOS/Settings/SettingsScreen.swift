import SwiftUI
import ThubanDeskCore

/// Board "Settings · Accounts and theme": Google accounts (+ Add Google account), Appearance (Auto / Light / Dark and the
/// eight Atlas schemes), Defaults (new events, notifications, remote images), then Google sign-in (the iOS client
/// ID) and About.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    /// iPad shows Settings in the detail column (no back button).
    var showsBack = true

    var body: some View {
        PhoneScreen(title: "Settings") {
            if showsBack {
                BackButton(title: "Today") { if !router.todayPath.isEmpty { router.todayPath.removeLast() } }
            }
        } content: {
            VStack(alignment: .leading, spacing: 22) {
                AccountsSection()
                AppearanceSection()
                DefaultsSection()
                GoogleClientSection()
                AboutSection()
            }
            .padding(.horizontal, PhoneMetrics.gutter)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Accounts

private struct AccountsSection: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Google accounts · \(app.accounts.count)").padding(.horizontal, 16)
            InsetCard {
                ForEach(Array(app.accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { RowDivider(inset: 64) }
                    Button { open(account.id) } label: {
                        PhoneRow(chevron: true) {
                            HStack(spacing: 12) {
                                PhoneAvatar(name: account.displayName ?? account.email, tint: app.mail.accountTint(account.id), size: 36, ringed: true)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(account.email).font(PhoneFont.body).foregroundStyle(theme.inkColor).lineLimit(1).minimumScaleFactor(0.8)
                                    Text(subtitle(account)).font(PhoneFont.footnote)
                                        .foregroundStyle(account.disconnected ? theme.negTextColor : theme.inkDimColor).lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                if !app.accounts.isEmpty { RowDivider(inset: 16) }
                Button { app.addAccount() } label: {
                    HStack(spacing: 12) {
                        Icon(.plus, size: 20)
                        Text(app.signIn == .waitingForBrowser ? "Waiting for Google…" : "Add Google account").font(PhoneFont.bodySemibold)
                        Spacer()
                    }
                    .foregroundStyle(theme.brassInkColor)
                    .padding(.horizontal, 16)
                    .frame(minHeight: PhoneMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(app.signIn == .waitingForBrowser)
            }
            if case .failed(let message) = app.signIn {
                PhoneBanner(text: message) { app.cancelSignIn() }
            }
            Text("Opens Google sign-in. Thuban Desk never sees your password.")
                .font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor).padding(.horizontal, 16)
        }
    }

    private func open(_ id: String) {
        router.todayPath.append(.account(id))
    }

    private func subtitle(_ account: GoogleAccount) -> String {
        if account.disconnected { return "Signed out by Google · sign in again" }
        let calendars = app.calendar.calendars.filter { $0.account == account.id }.count
        var parts: [String] = []
        if account.id == app.primaryAccount?.id { parts.append("Primary") }
        parts.append("\(calendars) calendar\(calendars == 1 ? "" : "s")")
        parts.append("Gmail")
        if account.id != app.primaryAccount?.id, let synced = account.lastSynced {
            parts.append("synced \(CalendarText.clock(synced, zone: app.zone, suffix: false))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Appearance

private struct AppearanceSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Appearance").padding(.horizontal, 16)
            InsetCard {
                VStack(alignment: .leading, spacing: 12) {
                    PhoneSegmented(options: AppearanceMode.allCases.map { ($0, $0.label) },
                                   selection: Binding(get: { app.themeSelection.mode }, set: { app.setAppearanceMode($0) }),
                                   accessibilityName: "Mode")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(SchemePresets.all) { scheme in
                            SchemeSwatch(scheme: scheme, selected: app.themeSelection.schemeId == scheme.id) { app.selectScheme(id: scheme.id) }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Color scheme")
                    Text("The same schemes as Thuban Study and Atlas. Calendar and label colors follow the scheme.")
                        .font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor)
                }
                .padding(12)
            }
        }
    }
}

private struct SchemeSwatch: View {
    @Environment(\.thubanTheme) private var theme
    var scheme: ThubanDeskCore.ColorScheme
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(scheme.label).font(.footnote.weight(.semibold)).foregroundStyle(selected ? theme.brassInkColor : theme.inkColor).lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 3) {
                    // Scheme swatches are the one place literal scheme colours are drawn (as in the Mac Appearance pane).
                    ForEach([scheme.accent, scheme.signal, scheme.pos, scheme.neg], id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 9, height: 9)
                    }
                }
                HStack(spacing: 0) {
                    Color(hex: scheme.lightPanel)
                    Color(hex: scheme.darkBg)
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? theme.accentTintColor : theme.panelColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? theme.accentColor : theme.lineColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scheme.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Defaults

private struct DefaultsSection: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    @State private var notifications = LocalNotifications.shared

    var body: some View {
        @Bindable var app = app
        let writable = app.calendar.calendars.filter(\.canWrite)
        let current = app.calendar.defaultCalendar
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Defaults").padding(.horizontal, 16)
            InsetCard {
                Menu {
                    ForEach(writable) { ref in
                        Button("\(ref.name) · \(ref.account.split(separator: "@").last.map(String.init) ?? "")") { app.settings.defaultCalendar = ref.key }
                    }
                } label: {
                    PhoneRow {
                        Text("New events go to").font(PhoneFont.body).foregroundStyle(theme.inkColor)
                    } trailing: {
                        HStack(spacing: 6) {
                            if let current { Circle().fill(theme.color(for: current.tint)).frame(width: 9, height: 9) }
                            Text(current?.name ?? "None").font(PhoneFont.body).foregroundStyle(theme.inkDimColor).lineLimit(1)
                            Icon(.upDown, size: 14).foregroundStyle(theme.chevronColor)
                        }
                    }
                }
                .accessibilityLabel("New events go to, \(current?.name ?? "none")")
                RowDivider()
                Menu {
                    ForEach(app.activeAccounts) { account in
                        Button(account.email) { app.settings.defaultSendAccount = account.id }
                    }
                } label: {
                    PhoneRow {
                        Text("Send new mail from").font(PhoneFont.body).foregroundStyle(theme.inkColor)
                    } trailing: {
                        HStack(spacing: 6) {
                            Text(app.mail.defaultSendAccount.map { $0.split(separator: "@").last.map(String.init) ?? $0 } ?? "None")
                                .font(PhoneFont.body).foregroundStyle(theme.inkDimColor)
                            Icon(.upDown, size: 14).foregroundStyle(theme.chevronColor)
                        }
                    }
                }
                RowDivider()
                NavigationLink {
                    NotificationsScreen()
                } label: {
                    PhoneRow(chevron: true) {
                        Text("Notifications").font(PhoneFont.body).foregroundStyle(theme.inkColor)
                    } trailing: {
                        Text(notifications.summary).font(PhoneFont.body).foregroundStyle(theme.inkDimColor)
                    }
                }
                .buttonStyle(.plain)
                RowDivider()
                toggleRow("Load remote images", isOn: $app.settings.loadRemoteImages)
                RowDivider()
                toggleRow("Week starts on Monday", isOn: $app.settings.weekStartsOnMonday)
                RowDivider()
                toggleRow("Show declined events", isOn: $app.settings.showDeclinedEvents)
            }
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        PhoneRow {
            Text(title).font(PhoneFont.body).foregroundStyle(theme.inkColor)
        } trailing: {
            Toggle(title, isOn: isOn).labelsHidden().tint(theme.accentColor)
        }
    }
}

// MARK: - Google iOS client

/// The iOS OAuth client: what the build carries (GOOGLE_IOS_CLIENT_ID → Info.plist + URL scheme) or one pasted here.
private struct GoogleClientSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var clientID = ""
    @State private var message: String?

    var body: some View {
        let configured = app.clientConfig?.clientID
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Google sign-in").padding(.horizontal, 16)
            InsetCard {
                VStack(alignment: .leading, spacing: 10) {
                    if app.isFixtureMode {
                        Text("Sample data: the app is talking to its built-in fake Google, so sign-in is off.")
                            .font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor)
                    } else if let configured {
                        Text("iOS client").font(PhoneFont.footnoteSemibold).foregroundStyle(theme.inkDimColor)
                        Text(configured).font(PhoneFont.mono).foregroundStyle(theme.inkColor).lineLimit(2).textSelection(.enabled)
                        if !MobileGoogleClient.isRegistered(configured) {
                            Text("This build does not register \(GoogleMobileRedirect.scheme(forClientID: configured) ?? "its redirect scheme"). Put the ID in DeskiOS/Config/Secrets.xcconfig (GOOGLE_IOS_CLIENT_ID) and rebuild.")
                                .font(PhoneFont.footnote).foregroundStyle(theme.negTextColor)
                        }
                    } else {
                        Text(MobileGoogleClient.missingMessage).font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor)
                    }
                    TextField("", text: $clientID, prompt: Text("…apps.googleusercontent.com").foregroundStyle(theme.inkFaintColor))
                        .font(PhoneFont.secondary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 10)
                        .frame(minHeight: 40)
                        .background(theme.fillColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityLabel("Google iOS client ID")
                    HStack {
                        Button("Save client ID") { save() }
                            .buttonStyle(PhoneSecondaryButtonStyle(height: 40, tint: theme.brassInkColor))
                            .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let message { Text(message).font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor) }
                    Text("PKCE, no client secret. Tokens stay in this app’s own folder, locked with the device.")
                        .font(.caption).foregroundStyle(theme.inkFaintColor)
                }
                .padding(14)
            }
        }
    }

    private func save() {
        Task {
            do {
                try await app.saveClientConfig(clientID: clientID, clientSecret: "")
                message = "Saved."
                clientID = ""
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

// MARK: - About

private struct AboutSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("About").padding(.horizontal, 16)
            InsetCard {
                HStack(spacing: 12) {
                    AppArtView(size: 36, theme: app.theme)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Thuban Desk").font(PhoneFont.display(.headline)).foregroundStyle(theme.inkColor)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")\(app.isFixtureMode ? " · sample data" : "")")
                            .font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor)
                    }
                    Spacer()
                }
                .padding(14)
                RowDivider()
                Text("Google Calendar and Gmail for your accounts. Sending mail, deleting events and signing out always ask first. No widgets, no push — reminders are local notifications.")
                    .font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor)
                    .padding(14)
            }
        }
    }
}
