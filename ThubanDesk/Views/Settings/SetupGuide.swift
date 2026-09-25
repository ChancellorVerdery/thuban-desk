import AppKit
import SwiftUI
import ThubanDeskCore
import UniformTypeIdentifiers

// MARK: - Steps

/// The Google Cloud setup, one numbered step each. Thuban Desk talks to Google with the user's own OAuth client
/// (a "Desktop app" client in their own Cloud project), so nothing is shared with anyone else.
enum SetupGuide {
    struct Step: Identifiable {
        var id: Int { number }
        var number: Int
        var title: String
        var detail: String
        var link: (label: String, url: URL)?
    }

    static let steps: [Step] = [
        Step(number: 1, title: "Create a Google Cloud project",
             detail: "Sign in to Google Cloud Console with the Google account you want to use, then choose “Select a project” → “New project”. Name it “Thuban Desk”. No billing is needed.",
             link: ("Open Cloud Console", URL(string: "https://console.cloud.google.com/projectcreate")!)),
        Step(number: 2, title: "Turn on the Gmail and Calendar APIs",
             detail: "With the new project selected, open APIs & Services → Library, search for “Gmail API” and press Enable, then do the same for “Google Calendar API”.",
             link: ("Open API Library", URL(string: "https://console.cloud.google.com/apis/library")!)),
        Step(number: 3, title: "Set up the consent screen",
             detail: "Open Google Auth Platform → Get started. App name “Thuban Desk”, your address as support and contact email, Audience “External”. Under Audience, add every Google address you will link as a test user.",
             link: ("Open Google Auth Platform", URL(string: "https://console.cloud.google.com/auth/overview")!)),
        Step(number: 4, title: "Create a Desktop OAuth client",
             detail: "Google Auth Platform → Clients → Create client. Application type “Desktop app”, name “Thuban Desk”, then Create. Keep the dialog open: it shows the Client ID and Client secret (or use Download JSON).",
             link: ("Open Clients", URL(string: "https://console.cloud.google.com/auth/clients")!)),
        Step(number: 5, title: "Paste the client here and sign in",
             detail: "Paste the Client ID and secret below (or import the downloaded JSON) and press Save. Then press Add Google account: your browser opens Google’s sign-in. Google warns that it hasn’t verified the app — it is your own project, so choose Continue and allow Calendar and Gmail.",
             link: nil),
        Step(number: 6, title: "Keep sign-ins from expiring",
             detail: "While the app is in “Testing”, Google signs you out every 7 days. Under Audience, press Publish app (no review is needed for your own use) so the sign-in lasts.",
             link: ("Open Audience", URL(string: "https://console.cloud.google.com/auth/audience")!)),
    ]

    /// What Thuban Desk asks for at sign-in, in words.
    static let scopesSummary = "Thuban Desk asks for: read and organize your mail (gmail.modify), send mail you confirm (gmail.send), read and create filters (gmail.settings.basic), and your calendars (calendar)."
}

/// Numbered steps: a 24 pt accent-tint disc with the number, a semibold title, a dim paragraph and an optional
/// link that opens in the browser.
struct SetupStepsView: View {
    @Environment(\.thubanTheme) private var theme
    var steps: [SetupGuide.Step] = SetupGuide.steps
    /// Steps already done (checked instead of numbered).
    var completed: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(completed.contains(step.number) ? theme.posSoftColor : theme.accentTintColor)
                        if completed.contains(step.number) {
                            Icon(.check, size: 13, lineWidth: 2.2).foregroundStyle(theme.posTextColor)
                        } else {
                            Text(String(step.number)).font(.system(size: 12.5, weight: .bold)).foregroundStyle(theme.brassInkColor)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title).font(ThubanFont.body(14.5, weight: .semibold)).foregroundStyle(theme.inkColor)
                        Text(step.detail)
                            .font(ThubanFont.body(13))
                            .foregroundStyle(theme.inkDimColor)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let link = step.link {
                            Button { NSWorkspace.shared.open(link.url) } label: {
                                HStack(spacing: 5) {
                                    Text(link.label)
                                    ExternalGlyph(size: 12)
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.brassInkColor)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                            .help(link.url.absoluteString)
                            .accessibilityLabel("\(link.label) in your browser")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(step.number): \(step.title). \(step.detail)")
            }
        }
    }
}

/// The design's "external" line icon (a box with an arrow out of its corner).
struct ExternalGlyph: View {
    var size: CGFloat = 13

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var path = Path()
            path.move(to: p(13, 5)); path.addLine(to: p(6.5, 5))
            path.addQuadCurve(to: p(5, 6.5), control: p(5, 5))
            path.addLine(to: p(5, 17.5))
            path.addQuadCurve(to: p(6.5, 19), control: p(5, 19))
            path.addLine(to: p(17.5, 19))
            path.addQuadCurve(to: p(19, 17.5), control: p(19, 19))
            path.addLine(to: p(19, 11))
            path.move(to: p(15, 4.5)); path.addLine(to: p(19.5, 4.5)); path.addLine(to: p(19.5, 9))
            path.move(to: p(19.5, 4.5)); path.addLine(to: p(11.5, 12.5))
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.75 * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Client form

/// Client ID + secret fields, Save, and "Import JSON…" (the file Cloud Console downloads). Stored only in the private
/// credentials file. Disabled in fixture mode (the fake Google has its own client).
struct OAuthClientForm: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var compact = false
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var message: (text: String, tone: SettingsNote.Tone)?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            fields
            HStack(spacing: 10) {
                Button(isSaving ? "Saving…" : "Save") { Task { await save(id: clientID, secret: clientSecret) } }
                    .buttonStyle(PrimaryButtonStyle(height: 32))
                    .disabled(isSaving || app.isFixtureMode || clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
                Button("Import JSON…") { importFile() }
                    .buttonStyle(SecondaryButtonStyle(height: 32))
                    .disabled(isSaving || app.isFixtureMode)
                    .help("Choose the client_secret_….json file from Cloud Console")
                if app.clientConfig != nil, !compact {
                    Button("Remove") { Task { await save(id: "", secret: "") } }
                        .buttonStyle(GhostButtonStyle(height: 32))
                        .disabled(isSaving || app.isFixtureMode)
                        .help("Forget the client. Linked accounts stop syncing until a client is saved again.")
                }
                Spacer(minLength: 0)
            }
            if let message {
                SettingsNote(text: message.text, tone: message.tone)
            } else if app.isFixtureMode {
                SettingsNote(text: "Fixture mode uses the fake Google's own client; these fields are read-only.")
            }
        }
        .onAppear(perform: load)
        .onChange(of: app.clientConfig) { _, _ in load() }
    }

    @ViewBuilder
    private var fields: some View {
        let id = LabeledField("Client ID") {
            TextField("1234567890-abc123.apps.googleusercontent.com", text: $clientID)
                .thubanField(mono: true, height: 32)
                .accessibilityLabel("Client ID")
        }
        let secret = LabeledField("Client secret") {
            SecureField("GOCSPX-…", text: $clientSecret)
                .thubanField(mono: true, height: 32)
                .accessibilityLabel("Client secret")
        }
        if compact {
            VStack(alignment: .leading, spacing: 10) { id; secret }
        } else {
            HStack(alignment: .bottom, spacing: 12) {
                id
                secret.frame(width: 260)
            }
        }
    }

    private func load() {
        clientID = app.clientConfig?.clientID ?? ""
        clientSecret = app.clientConfig?.clientSecret ?? ""
    }

    private func save(id: String, secret: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await app.saveClientConfig(clientID: id, clientSecret: secret)
            message = app.clientConfig == nil ? ("Client removed.", .neutral) : ("Saved. Now add your Google account.", .positive)
        } catch {
            message = (error.localizedDescription, .negative)
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the client_secret_….json file you downloaded from Google Cloud Console."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let config = try ClientSecretFile.parse(try Data(contentsOf: url))
            clientID = config.clientID
            clientSecret = config.clientSecret ?? ""
            Task { await save(id: config.clientID, secret: config.clientSecret ?? "") }
        } catch {
            message = (error.localizedDescription, .negative)
        }
    }
}

// MARK: - Sheet

/// Settings → Accounts → "Setup guide": the steps beside the form, in a sheet.
struct SetupGuideSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Connect Google").font(ThubanFont.display(26)).foregroundStyle(theme.inkColor)
                    Text("About ten minutes, once. Thuban Desk uses an OAuth client in your own Google Cloud project, so your mail and calendar go straight from Google to this Mac.")
                        .font(ThubanFont.body(14))
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                IconButton(.close, label: "Close", action: dismiss)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 18)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SetupStepsView(completed: completedSteps)
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Your OAuth client")
                        OAuthClientForm()
                    }
                    .padding(16)
                    .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
                    HStack(alignment: .top, spacing: 6) {
                        Glyph(.lock, size: 13).padding(.top, 1)
                        Text(SetupGuide.scopesSummary).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(ThubanFont.body(12.5))
                    .foregroundStyle(theme.inkFaintColor)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }
            Hairline()
            HStack(spacing: 10) {
                Spacer()
                Button("Done", action: dismiss).buttonStyle(SecondaryButtonStyle(height: 32))
                Button {
                    app.addAccount()
                    dismiss()
                } label: {
                    HStack(spacing: 7) { Icon(.plus, size: 15); Text("Add Google account") }
                }
                .buttonStyle(PrimaryButtonStyle(height: 32))
                .disabled(app.clientConfig == nil)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
        }
        .frame(width: 720, height: 760)
        .background(theme.panelColor)
    }

    private var completedSteps: Set<Int> {
        var done: Set<Int> = []
        if app.clientConfig != nil { done.formUnion([1, 2, 3, 4]) }
        if app.clientConfig != nil && app.hasAccounts { done.insert(5) }
        return done
    }
}

// MARK: - First run

/// Shown in Calendar / Mail / Today until an account is linked: a short welcome on the left, the steps and the
/// client form on the right, then "Add Google account".
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 44) {
                VStack(alignment: .leading, spacing: 18) {
                    AppArtView(size: 64, theme: theme)
                    Text("Welcome to Thuban Desk").font(ThubanFont.display(34)).foregroundStyle(theme.inkColor)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your Google Calendar and Gmail — every account in one calm window, with Today showing what needs you now.")
                        .font(ThubanFont.body(16))
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 12) {
                        promise(.account, "Several Google accounts; the first you link is your primary.")
                        promise(.today, "Today: your agenda, free time, and who is waiting on a reply.")
                        promise(.mail, "Nothing is sent or deleted without you confirming it first.")
                        promise(.info, "Tokens stay in a private file on this Mac. No Thuban server exists.")
                    }
                    .padding(.top, 6)
                    signInBlock.padding(.top, 10)
                }
                .frame(width: 360, alignment: .leading)

                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader("Set up in Google Cloud · about 10 minutes")
                    SetupStepsView(completed: app.clientConfig != nil ? [1, 2, 3, 4] : [])
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Your OAuth client")
                        OAuthClientForm()
                    }
                    .padding(16)
                    .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
                }
                .padding(22)
                .frame(maxWidth: 640, alignment: .leading)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
    }

    private func promise(_ icon: IconName, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(icon, size: 16).foregroundStyle(theme.brassInkColor).padding(.top, 1)
            Text(text).font(ThubanFont.body(14)).foregroundStyle(theme.inkColor).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var signInBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch app.signIn {
            case .waitingForBrowser:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Finish signing in in your browser…").font(ThubanFont.body(14)).foregroundStyle(theme.inkColor)
                    Button("Cancel") { app.cancelSignIn() }.buttonStyle(SecondaryButtonStyle(height: 32))
                }
            case .idle, .failed:
                Button { app.addAccount() } label: {
                    HStack(spacing: 7) { Icon(.plus, size: 15); Text("Add Google account") }
                }
                .buttonStyle(PrimaryButtonStyle(height: 36))
                .disabled(app.clientConfig == nil)
                Text(app.clientConfig == nil ? "Save your OAuth client first (steps 1–5)." : "Opens Google sign-in in your browser. Thuban Desk never sees your password.")
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkDimColor)
                    .fixedSize(horizontal: false, vertical: true)
                if case .failed(let message) = app.signIn { SettingsNote(text: message, tone: .negative) }
            }
        }
    }
}
