import SwiftUI
import ThubanDeskCore

/// iOS twin of the Mac `ConfirmWriteSheet`: shown before every irreversible action (send, delete event, delete
/// forever, empty trash, sign out). Only its action button calls `ConfirmRequest.run()` — nothing else can mint the
/// `Confirmed` token the send / delete APIs require. In fixture mode the send is refused (the gate and the fake
/// Google), and the error stays in the sheet.
struct ConfirmSheet: View {
    @Environment(\.thubanTheme) private var theme
    var request: ConfirmRequest
    var dismiss: () -> Void
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(theme.line2Color).frame(width: 36, height: 5).frame(maxWidth: .infinity).padding(.top, 8)
            Text(request.title).font(PhoneFont.display(.title2)).foregroundStyle(theme.inkColor)
                .accessibilityAddTraits(.isHeader)
            Text(request.message).font(PhoneFont.secondary).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error).font(PhoneFont.footnote).foregroundStyle(theme.negTextColor).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(isWorking ? request.workingLabel : request.actionLabel) { Task { await confirm() } }
                .buttonStyle(PhonePrimaryButtonStyle(destructive: request.destructive))
                .disabled(isWorking)
                .accessibilityHint("Confirms: \(request.title)")
            Button("Cancel", action: dismiss)
                .buttonStyle(PhoneSecondaryButtonStyle(height: PhoneMetrics.primaryHeight))
                .disabled(isWorking)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(theme.panelColor.ignoresSafeArea())
        .presentationDetents([.height(340), .medium])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(isWorking)
    }

    private func confirm() async {
        isWorking = true
        error = nil
        do {
            try await request.run()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isWorking = false
    }
}

extension View {
    /// Presents `app.pendingConfirmation` from this view. Apply it at the root (active when no sheet is up) and inside
    /// every sheet that can ask (editor, compose), so the confirmation always shows on top.
    func confirmHost(active: Bool) -> some View {
        modifier(ConfirmHostModifier(active: active))
    }
}

private struct ConfirmHostModifier: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var active: Bool

    func body(content: Content) -> some View {
        content.sheet(item: binding) { request in
            ConfirmSheet(request: request) { app.pendingConfirmation = nil }
                .environment(\.thubanTheme, app.theme)
        }
    }

    private var binding: Binding<ConfirmRequest?> {
        Binding(get: { active ? app.pendingConfirmation : nil }, set: { if $0 == nil, active { app.pendingConfirmation = nil } })
    }
}
