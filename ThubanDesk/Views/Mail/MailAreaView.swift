import SwiftUI
import ThubanDeskCore

/// PLACEHOLDER — owned by the Mail engineer (see ARCHITECTURE.md). Replace with the design's folder sidebar, thread
/// list (filters, bulk bar, resizable split), reader (sandboxed HTML), compose / reply sheet.
/// It currently lists the current mailbox so the data path is visible in smoke.
struct MailAreaView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(title: app.mail.scope.title,
                          subtitle: "\(app.mail.unreadCount) unread · \(app.accounts.count) accounts · the sidebar, list and reader land here.")
                ForEach(app.mail.visibleThreads) { summary in
                    HStack(spacing: 10) {
                        Circle().fill(summary.isUnread ? theme.accentColor : .clear).frame(width: 7, height: 7)
                        Text(summary.from?.displayName ?? "").font(ThubanFont.body(14, weight: summary.isUnread ? .semibold : .regular))
                            .foregroundStyle(theme.inkColor).frame(width: 200, alignment: .leading)
                        Text(summary.subject).font(ThubanFont.body(14)).foregroundStyle(theme.inkColor).lineLimit(1)
                        Spacer()
                        Text(summary.accountDomain).font(ThubanFont.small).foregroundStyle(theme.inkFaintColor)
                        Text(DeskFormat.listDate(summary.date, now: app.now(), zone: app.zone)).font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { if app.mail.threads.isEmpty { await app.mail.loadList() } }
    }
}
