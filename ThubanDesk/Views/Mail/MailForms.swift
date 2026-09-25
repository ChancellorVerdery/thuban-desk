import SwiftUI
import ThubanDeskCore

/// "Label" (toolbar, bulk bar, reader): check or uncheck labels on threads; labels are merged by name across
/// accounts and created in an account that lacks one. A search field doubles as "create a new label".
struct LabelPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var targets: [ThreadKey]
    var dismiss: () -> Void
    @State private var query = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        let mail = app.mail
        let names = mail.mergedLabels.map(\.name)
        let filtered = query.isEmpty ? names : names.filter { $0.localizedCaseInsensitiveContains(query) }
        let exact = names.contains { $0.caseInsensitiveCompare(query.trimmingCharacters(in: .whitespaces)) == .orderedSame }
        VStack(alignment: .leading, spacing: 8) {
            Text(targets.count > 1 ? "Label \(targets.count) conversations" : "Label conversation")
                .font(ThubanFont.micro).kerning(0.96).textCase(.uppercase).foregroundStyle(theme.inkDimColor)
            SearchField(text: $query, placeholder: "Find or create a label")
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(filtered, id: \.self) { name in
                        let state = labelState(name)
                        LabelPickerRow(name: name, tint: mail.labelTint(name), state: state) { toggle(name, currentlyOn: state == .all) }
                    }
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty, !exact {
                        Button { create() } label: {
                            HStack(spacing: 8) {
                                Icon(.plus, size: 14)
                                Text("Create “\(query.trimmingCharacters(in: .whitespaces))”").font(ThubanFont.body(13.5, weight: .semibold))
                                Spacer()
                            }
                            .foregroundStyle(theme.brassInkColor)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 240)
            if let error { Text(error).font(ThubanFont.small).foregroundStyle(theme.negTextColor).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(12)
        .frame(width: 280)
        .background(theme.panelColor)
        .disabled(working)
    }

    enum Applied { case none, some, all }

    private func labelState(_ name: String) -> Applied {
        let with = targets.filter { key in
            guard let summary = app.mail.summary(key) else { return false }
            return app.mail.labelNames(for: summary).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }.count
        if with == 0 { return .none }
        return with == targets.count ? .all : .some
    }

    private func toggle(_ name: String, currentlyOn: Bool) {
        working = true
        Task {
            defer { working = false }
            if currentlyOn {
                await app.mail.removeLabel(named: name, from: targets)
            } else {
                do { try await app.mail.applyLabel(named: name, to: targets) } catch { self.error = error.localizedDescription }
            }
        }
    }

    private func create() {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        working = true
        Task {
            defer { working = false }
            do {
                if targets.isEmpty {
                    for account in app.activeAccounts.map(\.id) { _ = try await app.mail.labelID(named: name, account: account) }
                } else {
                    try await app.mail.applyLabel(named: name, to: targets)
                }
                query = ""
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct LabelPickerRow: View {
    @Environment(\.thubanTheme) private var theme
    var name: String
    var tint: CalendarTint
    var state: LabelPicker.Applied
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                MailCheckbox(isOn: state == .all)
                    .overlay { if state == .some { Rectangle().fill(theme.brassInkColor).frame(width: 8, height: 2) } }
                TintDot(tint: tint, size: 8)
                Text(name).font(ThubanFont.body(13.5, weight: .medium)).foregroundStyle(theme.inkColor)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(hovering ? theme.panel2Color : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(name)
        .accessibilityValue(state == .all ? "applied" : state == .some ? "applied to some" : "not applied")
    }
}

/// Sidebar "New label": a name, created in every linked account (so the merged folder exists everywhere).
struct NewLabelForm: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var targets: [ThreadKey]
    var dismiss: () -> Void
    @State private var name = ""
    @State private var error: String?
    @State private var working = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New label").font(ThubanFont.display(17)).foregroundStyle(theme.inkColor)
            TextField("Label name", text: $name)
                .textFieldStyle(.plain)
                .font(ThubanFont.body(14))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(theme.fieldColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                .focused($focused)
                .onSubmit(create)
            Text("Created in \(app.activeAccounts.count == 1 ? "your account" : "all \(app.activeAccounts.count) accounts"); labels with the same name show as one.")
                .font(ThubanFont.small).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
            if !app.settings.writesEnabled {
                Text("Changes are turned off in Settings.").font(ThubanFont.small).foregroundStyle(theme.negTextColor)
            }
            if let error { Text(error).font(ThubanFont.small).foregroundStyle(theme.negTextColor).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel", action: dismiss).buttonStyle(SecondaryButtonStyle(height: 32))
                Button(working ? "Creating…" : "Create", action: create).buttonStyle(PrimaryButtonStyle(height: 32))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(theme.panelColor)
        .onAppear { focused = true }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        working = true
        Task {
            defer { working = false }
            do {
                for account in app.activeAccounts.map(\.id) { _ = try await app.mail.labelID(named: trimmed, account: account) }
                if !targets.isEmpty { try await app.mail.applyLabel(named: trimmed, to: targets) }
                await app.mail.loadLabels()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// "Filter sender": a Gmail filter for future mail from this address (skip the inbox and/or add a label).
struct FilterSenderForm: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var sender: EmailAddress
    var account: String
    var dismiss: () -> Void
    @State private var skipInbox = true
    @State private var label: String = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Filter mail from \(sender.displayName)").font(ThubanFont.display(17)).foregroundStyle(theme.inkColor)
                Text("Future mail from \(sender.email) in \(app.mail.accountDomain(account)).")
                    .font(ThubanFont.small).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                ThubanToggle(isOn: $skipInbox, label: "Skip the inbox")
                Text("Skip the inbox (archive it)").font(ThubanFont.body(14)).foregroundStyle(theme.inkColor)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Apply label").font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    labelChoice("None", selected: label.isEmpty) { label = "" }
                    ForEach(app.mail.mergedLabels) { merged in
                        labelChoice(merged.name, selected: label == merged.name, tint: merged.tint) { label = merged.name }
                    }
                }
            }
            if let error { Text(error).font(ThubanFont.small).foregroundStyle(theme.negTextColor).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel", action: dismiss).buttonStyle(SecondaryButtonStyle(height: 32))
                Button(working ? "Creating…" : "Create filter", action: create).buttonStyle(PrimaryButtonStyle(height: 32))
                    .disabled(working || (!skipInbox && label.isEmpty))
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(theme.panelColor)
    }

    private func labelChoice(_ title: String, selected: Bool, tint: CalendarTint? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let tint { TintDot(tint: tint, size: 7) }
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(selected ? theme.inkColor : theme.inkDimColor)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(selected ? theme.accentTintColor : theme.panel2Color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(selected ? theme.accentColor : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func create() {
        working = true
        Task {
            defer { working = false }
            do {
                try await app.mail.filterSender(sender.email, account: account, labelName: label.isEmpty ? nil : label, skipInbox: skipInbox)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
