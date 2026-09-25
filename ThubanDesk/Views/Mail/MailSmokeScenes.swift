import AppKit
import Foundation
import ThubanDeskCore

/// Mail screens for the smoke walk (owned by the Mail engineer). Names sort the PNGs: 30–39.
/// Nothing here sends: scene 33 only opens the Send confirmation, which the harness captures and cancels.
@MainActor
enum MailSmokeScenes {
    static let scenes: [SmokeScene] = [
        // Mail.dc.html: All inboxes, Priya's thread open (previewed, still unread), two threads checked → bulk bar.
        SmokeScene("30-mail-inbox", settle: 2.5) { app in
            await inbox(app, theme: .light)
        },
        // MailDark.dc.html.
        SmokeScene("31-mail-inbox-dark", settle: 2.5) { app in
            await inbox(app, theme: .dark)
        },
        // Compose.dc.html: reply to Priya from the account the thread arrived in; the draft autosaves (fixture).
        SmokeScene("32-mail-compose-reply", settle: 3.2) { app in
            await inbox(app, theme: .light)
            guard let message = await lastMessage(app, primary("t1")) else { return }
            ComposeModel.openReply(to: message, in: primary("t1"), all: false, app: app)
            try? await Task.sleep(nanoseconds: 400_000_000)
            app.mail.compose?.replaceBody(designReplyBody(theme: app.theme))
        },
        // Send asks first (captured, then cancelled by the harness — never confirmed).
        SmokeScene("33-mail-send-confirm", capture: .sheet) { app in
            app.mail.compose?.requestSend()
        },
        // One account's inbox (charlotte.edu), Maya's thread open.
        SmokeScene("34-mail-account-inbox", settle: 2.0) { app in
            app.mail.compose?.closeKeepingDraft()
            app.mail.compose = nil
            app.mail.checked = []
            app.mail.filter = .all
            app.mail.scope = MailScope(folder: .inbox, account: SampleData.schoolEmail)
            await app.mail.loadList(force: true)
            await app.mail.open(school("t2"), markRead: false)
        },
        // Needs reply filter across both inboxes, Mom's thread open.
        SmokeScene("35-mail-needs-reply", settle: 2.0) { app in
            app.mail.scope = MailScope()
            await app.mail.loadList(force: true)
            app.mail.filter = .needsReply
            await app.mail.open(primary("t8"), markRead: false)
        },
        // Trash: Delete forever confirms (captured, then cancelled).
        SmokeScene("36-mail-trash-delete-forever", capture: .sheet, settle: 1.5) { app in
            app.mail.filter = .all
            app.mail.scope = MailScope(folder: .trash)
            await app.mail.loadList(force: true)
            await app.mail.open(primary("t12"), markRead: false)
            MailActions.deleteForever([primary("t12")], app: app)
        },
        // A label merged across accounts, and a new message in dark mode.
        SmokeScene("37-mail-label-compose-dark", settle: 2.0) { app in
            app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
            app.mail.scope = MailScope(folder: .label("Recruiting"))
            await app.mail.loadList(force: true)
            await app.mail.open(primary("t6"), markRead: false)
            ComposeModel.openNew(app: app, to: [EmailAddress("maya.chen@students.example.edu", name: "Maya Chen")])
            app.mail.compose?.showCc = true
        },
        // Search (Gmail q=) in light mode; restores the default state for the scenes that follow.
        SmokeScene("38-mail-search", settle: 2.0) { app in
            app.mail.compose = nil
            app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            app.mail.scope = MailScope()
            app.searchText = "interview"
            try? await Task.sleep(nanoseconds: 900_000_000)
            await app.mail.open(primary("t1"), markRead: false)
        },
        // Drafts folder (light); leaves Mail in its default state for the scenes that follow.
        SmokeScene("39-mail-drafts", settle: 2.0) { app in
            app.searchText = ""
            try? await Task.sleep(nanoseconds: 700_000_000)
            app.mail.scope = MailScope(folder: .drafts)
            await app.mail.loadList(force: true)
            await app.mail.open(primary("t1"), markRead: false)
        },
    ]

    private static func primary(_ id: String) -> ThreadKey { ThreadKey(account: SampleData.primaryEmail, threadID: id) }
    private static func school(_ id: String) -> ThreadKey { ThreadKey(account: SampleData.schoolEmail, threadID: id) }

    private static func inbox(_ app: AppModel, theme mode: AppearanceMode) async {
        app.mail.compose = nil
        app.setThemeSelection(ThemeSelection(mode: mode, schemeId: SchemePresets.defaultId, custom: nil))
        app.settings.mailListWidth = 468
        app.select(.mail)
        app.mail.filter = .all
        if app.mail.scope != MailScope() { app.mail.scope = MailScope() }
        await app.mail.loadList(force: true)
        await app.mail.open(primary("t1"), markRead: false)
        app.mail.checked = [school("t5"), school("t7")]
    }

    private static func lastMessage(_ app: AppModel, _ key: ThreadKey) async -> MailMessage? {
        (try? await app.mail.thread(key))?.messages.last { !$0.isDraft }
    }

    /// The design's reply text (bold "accepted the invite", italic "Python", dim last signature line).
    private static func designReplyBody(theme: ResolvedTheme) -> NSAttributedString {
        let base = RichTextFormat.baseAttributes(theme: theme)
        let out = NSMutableAttributedString()
        func add(_ text: String, _ traits: NSFontTraitMask = [], dim: Bool = false) {
            var attrs = base
            if !traits.isEmpty { attrs[.font] = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 15), toHaveTrait: traits) }
            if dim {
                attrs[.foregroundColor] = NSColor(hex: theme.inkDim)
                attrs[.deskDim] = true
            }
            out.append(NSAttributedString(string: text, attributes: attrs))
        }
        add("Hi Priya,\n\nThanks for setting this up — I’ve ")
        add("accepted the invite", .boldFontMask)
        add(" and will join from the Zoom link on Friday at 3:00 PM.\n\nOne quick question: is it fine to use ")
        add("Python", .italicFontMask)
        add(" for the coding portion, or does the team prefer Java?\n\nBest,\nAlex Morgan\n")
        add("UNC Charlotte · B.S. Computer Science, 2028", dim: true)
        return out
    }
}
