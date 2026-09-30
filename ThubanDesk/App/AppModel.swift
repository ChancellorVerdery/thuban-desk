#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import Observation
import ThubanDeskCore
import os

/// Root model: settings + theme, linked Google accounts (token store and one `GoogleClient` each), navigation,
/// the Calendar and Mail stores, sync status, and the confirmation sheet for irreversible writes.
/// Shared by the macOS app and the iOS app (DeskiOS); platform bits are fenced with `#if os(macOS)`.
@MainActor
@Observable
final class AppModel {
    static let logger = Logger(subsystem: "com.thuban.desk", category: "app")

    // MARK: Settings

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            persistSettings()
            if settings.theme != oldValue.theme {
                recomputeTheme()
                #if os(macOS)
                SharedTheme.publish(settings.theme)
                #endif
            }
            if settings.writesEnabled != oldValue.writesEnabled { gateFlags.set(writes: settings.writesEnabled, send: sendAllowed) }
            if settings.refreshMinutes != oldValue.refreshMinutes, isLoaded { startRefreshTimer() }
        }
    }

    // MARK: Navigation

    var area: AppArea = .calendar {
        didSet { if let desk = area.deskArea { settings.lastArea = desk } }
    }
    var settingsPane: SettingsPane = .accounts
    /// Title-bar search text (⌘K focuses the field). Areas read it; Mail searches Gmail, Calendar filters events.
    var searchText = ""
    /// Bumped by ⌘K to focus the title-bar search field.
    var searchFocusRequest = 0
    /// Bumped by ⌘N: the current area creates something new (event / compose).
    var newItemRequest = 0

    func select(_ area: AppArea) { self.area = area }

    func openSettings(_ pane: SettingsPane = .accounts) {
        settingsPane = pane
        area = .settings
    }

    // MARK: Accounts

    /// In-process fake Google (`THUBAN_DESK_FIXTURES=1`): nothing reaches the network and sending is impossible.
    let isFixtureMode: Bool
    @ObservationIgnored private(set) var fixture: FixtureGoogle?
    /// The session every Google request uses (the fixture session in fixture mode).
    @ObservationIgnored let session: URLSession
    @ObservationIgnored private let gateFlags = GateFlags()
    @ObservationIgnored private(set) var tokenStore: AccountTokenStore
    @ObservationIgnored private var clientCache: [String: GoogleClient] = [:]
    /// Mirror of the credentials file (client config + accounts), refreshed after every token-store change.
    private(set) var credentials = CredentialsFile()
    var signIn: SignInState = .idle
    @ObservationIgnored var signInTask: Task<Void, Never>?
    @ObservationIgnored var signInAttempt: UUID?

    enum SignInState: Equatable {
        case idle
        case waitingForBrowser
        case failed(String)
    }

    /// Linked accounts, primary (earliest linked) first.
    var accounts: [GoogleAccount] { smokeHidesAccounts ? [] : credentials.orderedAccounts }
    /// Smoke only (fixture mode): shows the app as if no account were linked, without touching the credentials file.
    private(set) var smokeHidesAccounts = false
    var primaryAccount: GoogleAccount? { credentials.primary }
    /// Accounts that can be used (not signed out by Google).
    var activeAccounts: [GoogleAccount] { accounts.filter { !$0.disconnected } }
    var hasAccounts: Bool { !accounts.isEmpty }
    var clientConfig: GoogleClientConfig? { credentials.client }
    /// Every address the user owns (for reply-all and NeedsReply).
    var ownAddresses: Set<String> { Set(accounts.map(\.id)) }

    /// The API client for an account (nil when unknown or disconnected).
    func client(for accountID: String) -> GoogleClient? {
        let id = accountID.lowercased()
        guard let account = credentials.account(id), !account.disconnected else { return nil }
        if let cached = clientCache[id] { return cached }
        let flags = gateFlags
        let client = GoogleClient(accountID: id, tokens: tokenStore, session: session,
                                  gate: WriteGate(allowWrites: { flags.writes }, allowSend: { flags.send }))
        clientCache[id] = client
        return client
    }

    /// Sending is possible only outside fixture mode and with changes enabled.
    private var sendAllowed: Bool { !isFixtureMode && settings.writesEnabled }

    // MARK: Stores

    @ObservationIgnored let cache: DiskCache
    let calendar: CalendarStore
    let mail: MailStore

    // MARK: Sync

    private(set) var isLoaded = false
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    /// Last refresh failure per account (offline, 403 …).
    private(set) var syncErrors: [String: String] = [:]
    @ObservationIgnored private var refreshTimer: Timer?

    /// "2 accounts synced" / "Syncing…" / "Offline" / "1 account needs sign-in" (the title-bar pill).
    var syncSummary: (text: String, tone: SyncTone) {
        let disconnected = accounts.filter(\.disconnected).count
        if !hasAccounts { return ("No accounts", .idle) }
        if disconnected > 0 { return ("\(disconnected) account\(disconnected == 1 ? "" : "s") need\(disconnected == 1 ? "s" : "") sign-in", .problem) }
        if isSyncing { return ("Syncing…", .busy) }
        if !syncErrors.isEmpty { return ("Offline · showing saved", .problem) }
        let count = activeAccounts.count
        return ("\(count) account\(count == 1 ? "" : "s") synced", .ok)
    }

    enum SyncTone { case ok, busy, problem, idle }

    // MARK: Smoke hooks (fixture mode only)

    func smokeHideAccounts(_ hide: Bool) {
        guard isFixtureMode else { return }
        smokeHidesAccounts = hide
    }

    /// Shows the offline state as a failed refresh would leave it.
    func smokeSetSyncError(_ message: String?, account: String) {
        guard isFixtureMode else { return }
        syncErrors[account.lowercased()] = message
    }

    // MARK: Confirmation

    /// Shown by the shell as a `ConfirmWriteSheet`. Set it with `confirm(_:)`.
    var pendingConfirmation: ConfirmRequest?

    /// Asks before an irreversible action; `request.perform` runs only when the user presses the action button.
    func confirm(_ request: ConfirmRequest) {
        pendingConfirmation = request
    }

    // MARK: Time

    /// "Now" (pinned in smoke via THUBAN_DESK_NOW).
    func now() -> Date { DeskClock.now() }
    /// The zone views lay days out in (New York in fixture mode so screenshots match the design).
    let zone: TimeZone

    // MARK: Theme

    private(set) var systemIsDark = false
    private(set) var theme: ResolvedTheme = ThemeResolver.resolve(.default, systemIsDark: false)
    #if os(macOS)
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    #endif
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?

    var themeSelection: ThemeSelection { settings.theme }

    // MARK: Init

    init() {
        isFixtureMode = FixtureMode.isEnabled
        zone = FixtureMode.isEnabled ? TimeZone(identifier: "America/New_York")! : .current
        try? AppPaths.ensureDirectories()
        var fixture: FixtureGoogle?
        if isFixtureMode {
            let world = SampleData.world(now: DeskClock.now(), zone: zone)
            if (try? CredentialStore.load())?.accounts.isEmpty ?? true { try? FixtureSeeder.seed(world: world) }
            fixture = FixtureGoogle(world: world)
            session = fixture!.makeSession()
        } else {
            session = URLSession(configuration: .default)
        }
        self.fixture = fixture
        var loadedSettings = SettingsStore.load()
        #if os(macOS)
        // One scheme for every Thuban app: the shared selection wins over this app's saved one.
        if let shared = SharedTheme.load() { loadedSettings.theme = shared }
        #endif
        settings = loadedSettings
        var file = (try? CredentialStore.load()) ?? CredentialsFile()
        #if os(iOS)
        // iOS: the Google iOS client from the build (GOOGLE_IOS_CLIENT_ID) unless the user entered one in Settings.
        if file.client == nil, !isFixtureMode, let bundled = MobileGoogleClient.bundledConfig { file.client = bundled }
        #endif
        credentials = file
        tokenStore = AccountTokenStore(file: file, session: session)
        cache = DiskCache()
        calendar = CalendarStore()
        mail = MailStore()
        gateFlags.set(writes: settings.writesEnabled, send: !isFixtureMode && settings.writesEnabled)
        area = AppArea(settings.lastArea)
        systemIsDark = Self.currentSystemIsDark()
        theme = ThemeResolver.resolve(settings.theme, systemIsDark: systemIsDark)
        calendar.app = self
        mail.app = self
        observeTokenStore()
        #if os(macOS)
        let flushNotification = NSApplication.willTerminateNotification
        #else
        let flushNotification = UIApplication.didEnterBackgroundNotification
        #endif
        terminateObserver = NotificationCenter.default.addObserver(forName: flushNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushSettings() }
        }
    }

    /// Called once from the main window's `.task`.
    func load() async {
        guard !isLoaded else { return }
        #if os(macOS)
        if appearanceObservation == nil { observeAppearance() }
        observeSharedTheme()
        // First Thuban app to run with sharing seeds the file with its own scheme.
        if SharedTheme.load() == nil { SharedTheme.publish(settings.theme) }
        #endif
        recomputeTheme()
        isLoaded = true
        await refreshAll()
        startRefreshTimer()
        SmokeHarness.startIfEnabled(app: self)
    }

    /// Refreshes calendars + the visible range and mail labels + the current list, for every active account.
    func refreshAll() async {
        guard hasAccounts, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        async let calendars: Void = calendar.refresh()
        async let mailbox: Void = mail.refresh()
        _ = await (calendars, mailbox)
        syncErrors = calendar.accountErrors.merging(mail.accountErrors) { a, _ in a }
        if syncErrors.isEmpty { lastSync = now() }
        let stamp = now()
        for account in activeAccounts where syncErrors[account.id] == nil {
            try? await tokenStore.markSynced(account.id, at: stamp)
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        guard !SmokeHarness.isEnabled else { return }
        let minutes = max(2, settings.refreshMinutes)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
    }

    // MARK: Account management

    private func observeTokenStore() {
        let store = tokenStore
        Task {
            await store.observe { file in
                Task { @MainActor [weak self] in self?.credentialsChanged(file) }
            }
        }
    }

    private func credentialsChanged(_ file: CredentialsFile) {
        let removed = Set(credentials.accounts.map(\.id)).subtracting(file.accounts.map(\.id))
        let disconnected = file.accounts.filter(\.disconnected).map(\.id)
        credentials = file
        for id in removed.union(disconnected) { clientCache[id] = nil }
    }

    /// Stores the OAuth client the user created (Settings → Accounts). Pass an empty id to clear it.
    func saveClientConfig(clientID: String, clientSecret: String) async throws {
        let config = clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : try GoogleClientConfig.normalized(clientID: clientID, clientSecret: clientSecret)
        try await tokenStore.setClient(config)
        clientCache.removeAll()
    }

    #if os(macOS)
    /// Opens Google sign-in in the browser (loopback + PKCE) and links the account that signs in.
    func addAccount(loginHint: String? = nil) {
        guard !isFixtureMode else {
            signIn = .failed("Sign-in is disabled in fixture mode.")
            return
        }
        guard let config = credentials.client else {
            signIn = .failed(ThubanError.missingClientID.localizedDescription)
            return
        }
        signInTask?.cancel()
        signIn = .waitingForBrowser
        let flow = GoogleSignIn(oauth: GoogleOAuth(config: config, session: session)) { url in
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        let attempt = UUID()
        signInAttempt = attempt
        signInTask = Task { @MainActor in
            // A cancelled or superseded attempt must not overwrite the state set by `cancelSignIn` / a newer attempt
            // (the receiver reports cancellation as ThubanError.oauth, not CancellationError).
            let isCurrent = { !Task.isCancelled && self.signInAttempt == attempt }
            do {
                let account = try await flow.run(loginHint: loginHint, now: Date())
                guard isCurrent() else { return }
                try await tokenStore.upsert(account)
                signIn = .idle
                NSApp.activate(ignoringOtherApps: true)
                await refreshAll()
            } catch {
                guard isCurrent() else { return }
                signIn = error is CancellationError ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    #else
    /// iOS: Google sign-in in an ASWebAuthenticationSession (reversed-client-ID redirect + PKCE, no client secret);
    /// links the account that signs in. Disabled in fixture mode (smoke and development never reach Google).
    func addAccount(loginHint: String? = nil) {
        guard !isFixtureMode else {
            signIn = .failed("Sign-in is disabled in fixture mode.")
            return
        }
        guard let config = credentials.client, GoogleMobileRedirect.scheme(forClientID: config.clientID) != nil else {
            signIn = .failed(MobileGoogleClient.missingMessage)
            return
        }
        signInTask?.cancel()
        signIn = .waitingForBrowser
        let flow = GoogleMobileSignIn(oauth: GoogleOAuth(config: GoogleClientConfig(clientID: config.clientID), session: session))
        let attempt = UUID()
        signInAttempt = attempt
        signInTask = Task { @MainActor in
            let isCurrent = { !Task.isCancelled && self.signInAttempt == attempt }
            do {
                let request = try flow.makeRequest(loginHint: loginHint)
                let callback = try await WebAuthSession.run(url: request.url, callbackScheme: request.scheme)
                let account = try await flow.finish(callback: callback, request: request, now: Date())
                guard isCurrent() else { return }
                try await tokenStore.upsert(account)
                signIn = .idle
                await refreshAll()
            } catch {
                guard isCurrent() else { return }
                signIn = error is CancellationError ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    #endif

    func cancelSignIn() {
        signInAttempt = nil
        signInTask?.cancel()
        signInTask = nil
        signIn = .idle
    }

    /// Signs an account out: revokes its token and forgets its cached data. Confirmed first (see Settings).
    func removeAccount(_ accountID: String, confirmed: Confirmed) async throws {
        try await tokenStore.remove(accountID, revoke: !isFixtureMode)
        clientCache[accountID.lowercased()] = nil
        calendar.forget(account: accountID)
        mail.forget(account: accountID)
    }

    // MARK: Settings persistence

    private func persistSettings() {
        saveTask?.cancel()
        let snapshot = settings
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do { try SettingsStore.save(snapshot) } catch { Self.logger.error("settings save failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func flushSettings() {
        guard let pending = saveTask else { return }
        pending.cancel()
        saveTask = nil
        try? SettingsStore.save(settings)
    }

    // MARK: Theme

    func setThemeSelection(_ selection: ThemeSelection) { settings.theme = selection }

    func setAppearanceMode(_ mode: AppearanceMode) {
        var selection = themeSelection
        selection.mode = mode
        setThemeSelection(selection)
    }

    func selectScheme(id: String) {
        var selection = themeSelection
        selection.schemeId = id
        if id == ThubanScheme.customId, selection.custom == nil { selection.custom = SchemePresets.default.asCustom() }
        setThemeSelection(selection)
    }

    func setCustomScheme(_ scheme: ThubanScheme) {
        var selection = themeSelection
        selection.custom = scheme.asCustom(label: scheme.label)
        selection.schemeId = ThubanScheme.customId
        setThemeSelection(selection)
    }

    #if os(macOS)
    @ObservationIgnored private var sharedThemeObserver: NSObjectProtocol?

    /// Another Thuban app changed the scheme: adopt it (publishing again is a no-op once the file matches).
    private func observeSharedTheme() {
        guard sharedThemeObserver == nil else { return }
        sharedThemeObserver = SharedTheme.observe { [weak self] selection in
            guard let self, self.settings.theme != selection else { return }
            self.settings.theme = selection
        }
    }

    private func observeAppearance() {
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let dark = Self.currentSystemIsDark()
                if dark != self.systemIsDark {
                    self.systemIsDark = dark
                    self.recomputeTheme()
                }
            }
        }
    }

    static func currentSystemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }
    #else
    /// iOS: the root view reports the system appearance (`colorScheme` while the mode is Automatic).
    func setSystemIsDark(_ dark: Bool) {
        guard dark != systemIsDark else { return }
        systemIsDark = dark
        recomputeTheme()
    }

    static func currentSystemIsDark() -> Bool {
        UITraitCollection.current.userInterfaceStyle == .dark
    }
    #endif

    private func recomputeTheme() {
        let resolved = ThemeResolver.resolve(themeSelection, systemIsDark: systemIsDark)
        if resolved != theme { theme = resolved }
        #if os(macOS)
        switch themeSelection.mode {
        case .auto: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        AppIconRenderer.apply(theme: resolved)
        #endif
    }
}

/// Thread-safe copy of the write/send switches for the `WriteGate` closures (called off the main actor).
final class GateFlags: @unchecked Sendable {
    private let lock = NSLock()
    private var _writes = false
    private var _send = false

    var writes: Bool { lock.withLock { _writes } }
    var send: Bool { lock.withLock { _send } }

    func set(writes: Bool, send: Bool) {
        lock.withLock {
            _writes = writes
            _send = send
        }
    }
}
