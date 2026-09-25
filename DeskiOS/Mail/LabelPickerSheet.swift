import SwiftUI
import ThubanDeskCore

/// Label threads: every label (merged by name across accounts) with a check when all targets carry it; a new label
/// is created in each account that lacks it. Reversible, so it runs at once (like Gmail).
struct LabelPickerSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneRouter.self) private var router
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var targets: [ThreadKey]
    @State private var newLabel = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Label").font(PhoneFont.inlineTitle).foregroundStyle(theme.inkColor)
                Spacer()
            }
            .overlay(alignment: .trailing) { NavTextButton("Done", bold: true) { dismiss() }.padding(.trailing, 8) }
            .padding(.top, 12)
            .frame(minHeight: 56)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error { PhoneBanner(text: error) { self.error = nil } }
                    InsetCard(fill: theme.bgColor) {
                        ForEach(Array(app.mail.mergedLabels.enumerated()), id: \.element.id) { index, label in
                            if index > 0 { RowDivider(inset: 50) }
                            let on = hasLabel(label.name)
                            Button { toggle(label.name, on: on) } label: {
                                PhoneRow {
                                    HStack(spacing: 12) {
                                        Icon(.label, size: 20).foregroundStyle(theme.textColor(for: label.tint))
                                        Text(label.name).font(PhoneFont.body).foregroundStyle(theme.inkColor)
                                    }
                                } trailing: {
                                    if on { Icon(.check, size: 18, lineWidth: 2.2).foregroundStyle(theme.brassInkColor) }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                        RowDivider(inset: 16)
                        HStack(spacing: 10) {
                            Icon(.plus, size: 18).foregroundStyle(theme.inkFaintColor)
                            TextField("", text: $newLabel, prompt: Text("New label").foregroundStyle(theme.inkFaintColor))
                                .font(PhoneFont.body)
                                .submitLabel(.done)
                                .onSubmit { create() }
                                .accessibilityLabel("New label")
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: PhoneMetrics.rowHeight)
                    }
                }
                .padding(PhoneMetrics.gutter)
            }
        }
        .background(theme.panelColor.ignoresSafeArea())
        .presentationBackground(theme.panelColor)
        .presentationDetents([.medium, .large])
    }

    private func hasLabel(_ name: String) -> Bool {
        targets.allSatisfy { key in
            guard let summary = app.mail.summary(key) ?? app.mail.detail(key)?.summary else { return false }
            return app.mail.labelNames(for: summary).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

    private func toggle(_ name: String, on: Bool) {
        Task {
            if on {
                await app.mail.removeLabel(named: name, from: targets)
            } else {
                do { try await app.mail.applyLabel(named: name, to: targets) } catch { self.error = error.localizedDescription }
            }
        }
    }

    private func create() {
        let name = newLabel.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newLabel = ""
        Task {
            do { try await app.mail.applyLabel(named: name, to: targets) } catch { self.error = error.localizedDescription }
        }
    }
}
