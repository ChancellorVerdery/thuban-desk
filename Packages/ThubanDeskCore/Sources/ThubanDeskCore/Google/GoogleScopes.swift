import Foundation

/// OAuth scopes requested at sign-in (one consent covers Calendar and Mail).
///
/// Note: `gmail.modify` covers trash/untrash but NOT permanent deletion — `threads.delete` ("Delete forever") and
/// emptying Trash need `https://mail.google.com/`. Add `GoogleScopes.fullMail` to `all` if that feature must work;
/// until then Google answers 403 `insufficientPermissions` and the UI should say so.
public enum GoogleScopes {
    public static let gmailModify = "https://www.googleapis.com/auth/gmail.modify"
    public static let gmailSend = "https://www.googleapis.com/auth/gmail.send"
    public static let gmailSettingsBasic = "https://www.googleapis.com/auth/gmail.settings.basic"
    public static let calendar = "https://www.googleapis.com/auth/calendar"
    public static let fullMail = "https://mail.google.com/"
    public static let openID = "openid"
    public static let email = "email"

    public static let all: [String] = [gmailModify, gmailSend, gmailSettingsBasic, calendar, openID, email]
}

/// Google endpoints (overridable in tests only through the URLSession stub, never by configuration).
public enum GoogleEndpoints {
    public static let authorize = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let token = URL(string: "https://oauth2.googleapis.com/token")!
    public static let revoke = URL(string: "https://oauth2.googleapis.com/revoke")!
    public static let calendar = URL(string: "https://www.googleapis.com/calendar/v3")!
    public static let gmail = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!
}
