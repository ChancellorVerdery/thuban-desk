import SwiftUI
import ThubanDeskCore

/// The confirmation shown before every irreversible action (send, delete event, delete forever, empty trash,
/// sign out). Presented by the shell for `app.pendingConfirmation`. The action is deliberately NOT the default
/// button: Return cannot confirm; Escape cancels.
struct ConfirmWriteSheet: View {
    @Environment(\.thubanTheme) private var theme
    var request: ConfirmRequest
    var dismiss: () -> Void
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.title).font(ThubanFont.display(20)).foregroundStyle(theme.inkColor)
            Text(request.message).font(ThubanFont.body(14)).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(ThubanFont.small).foregroundStyle(theme.negTextColor).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel", action: dismiss).buttonStyle(.thubanSecondary).keyboardShortcut(.cancelAction).disabled(isWorking)
                Button(isWorking ? request.workingLabel : request.actionLabel) {
                    Task { await confirm() }
                }
                .buttonStyle(PrimaryButtonStyle(destructive: request.destructive))
                .disabled(isWorking)
                .accessibilityHint("Confirms: \(request.title)")
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(theme.panelColor)
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
