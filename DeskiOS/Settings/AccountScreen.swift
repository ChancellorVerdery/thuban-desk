import SwiftUI
import ThubanDeskCore

/// One linked account: status, its calendars (visibility + default), sign in again, and Sign out (confirmed first:
/// revokes the token and forgets the account's cached mail and events).
struct AccountScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    var accountID: String

    var body: some View {
        let account = app.accounts.first { $0.id == accountID }
        let calendars = app.calendar.calendars.filter { $0.account == accountID }
        PhoneScreen(title: account?.domain ?? "Account", subtitle: account?.email) {
            BackButton(title: "Settings") { if !router.todayPath.isEmpty { router.todayPath.removeLast() } }
        } content: {
            VStack(alignment: .leading, spacing: 22) {
                if let account {
                    InsetCard {
                        PhoneRow {
                            Text("Status").font(PhoneFont.body).foregroundStyle(theme.inkColor)
                        } trailing: {
                            Text(account.disconnected ? "Needs sign-in" : "Connected").font(PhoneFont.body)
                                .foregroundStyle(account.disconnected ? theme.negTextColor : theme.inkDimColor)
                        }
                        RowDivider()
                        PhoneRow {
                            Text("Role").font(PhoneFont.body).foregroundStyle(theme.inkColor)
                        } trailing: {
                            Text(account.id == app.primaryAccount?.id ? "Primary" : "Linked").font(PhoneFont.body).foregroundStyle(theme.inkDimColor)
                        }
                        if let synced = account.lastSynced {
                            RowDivider()
                            PhoneRow {
                                Text("Last synced").font(PhoneFont.body).foregroundStyle(theme.inkColor)
                            } trailing: {
                                Text(CalendarText.clock(synced, zone: app.zone)).font(PhoneFont.body).foregroundStyle(theme.inkDimColor)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow("Calendars · \(calendars.count)").padding(.horizontal, 16)
                        InsetCard {
                            ForEach(Array(calendars.enumerated()), id: \.element.id) { index, ref in
                                if index > 0 { RowDivider(inset: 44) }
                                PhoneRow {
                                    HStack(spacing: 12) {
                                        Circle().fill(theme.color(for: ref.tint)).frame(width: 12, height: 12)
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(ref.name).font(PhoneFont.body).foregroundStyle(theme.inkColor).lineLimit(1)
                                            if !ref.canWrite { Text("Read only").font(.caption).foregroundStyle(theme.inkDimColor) }
                                        }
                                    }
                                } trailing: {
                                    Toggle(ref.name, isOn: Binding(get: { !ref.isHidden }, set: { app.calendar.setHidden(!$0, ref.key) }))
                                        .labelsHidden().tint(theme.accentColor)
                                }
                            }
                        }
                    }
                    VStack(spacing: 10) {
                        if account.disconnected {
                            Button("Sign in again") { app.addAccount(loginHint: account.email) }
                                .buttonStyle(PhonePrimaryButtonStyle())
                        }
                        Button("Sign out…") { signOut(account) }
                            .buttonStyle(PhoneSecondaryButtonStyle(height: PhoneMetrics.primaryHeight, tint: theme.negTextColor))
                    }
                } else {
                    PhoneEmptyState(icon: .account, text: "This account is no longer linked.")
                }
            }
            .padding(.horizontal, PhoneMetrics.gutter)
            .padding(.bottom, 32)
        }
    }

    private func signOut(_ account: GoogleAccount) {
        let router = router
        app.confirm(ConfirmRequest(
            title: "Sign out of \(account.email)?",
            message: "Thuban Desk forgets this account’s tokens, mail and events on this device. Nothing changes in Google.",
            actionLabel: "Sign out", destructive: true, workingLabel: "Signing out…"
        ) { [app] confirmed in
            try await app.removeAccount(account.id, confirmed: confirmed)
            if !router.todayPath.isEmpty { router.todayPath.removeLast() }
        })
    }
}

/// Local notifications only (no push): event reminders, new invitations, new "needs a reply" mail.
struct NotificationsScreen: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var notifications = LocalNotifications.shared

    var body: some View {
        @Bindable var notifications = notifications
        PhoneScreen(title: "Notifications") {
            BackButton(title: "Settings") { dismiss() }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                InsetCard {
                    toggle("Event reminders", detail: "10 minutes before, on this iPhone", isOn: $notifications.eventReminders)
                    RowDivider()
                    toggle("Invitations", detail: "When a new invitation arrives", isOn: $notifications.invitations)
                    RowDivider()
                    toggle("Replies", detail: "When someone is waiting on your answer", isOn: $notifications.replies)
                }
                Text("Local notifications, scheduled by the app while it runs. No push server, no widgets.")
                    .font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor).padding(.horizontal, 16)
                if notifications.denied {
                    PhoneBanner(text: "Notifications are off for Thuban Desk in the iOS Settings app.")
                }
            }
            .padding(.horizontal, PhoneMetrics.gutter)
        }
    }

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        PhoneRow {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(PhoneFont.body).foregroundStyle(theme.inkColor)
                Text(detail).font(PhoneFont.footnote).foregroundStyle(theme.inkDimColor)
            }
            .padding(.vertical, 6)
        } trailing: {
            Toggle(title, isOn: isOn).labelsHidden().tint(theme.accentColor)
        }
    }
}
