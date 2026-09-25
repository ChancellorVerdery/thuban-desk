import Foundation

/// How the reader styles a message body in its sandboxed web view. Plain mail (paragraphs, a signature) takes the
/// theme's ink on the reader card; designed mail (newsletters with tables, backgrounds, fixed colours) is shown on
/// a light "paper" card in dark mode so its own colours stay readable.
public enum MailReaderStyle {
    /// True when the HTML brings its own layout or colours (tables, bgcolor, background colours).
    public static func isDesigned(_ html: String?) -> Bool {
        guard let html = html?.lowercased(), !html.isEmpty else { return false }
        if html.contains("bgcolor") || html.contains("<table") { return true }
        if html.range(of: #"background(-color)?\s*:\s*(#|rgb|[a-z])"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// The stylesheet injected into `MailHTML.prepare(css:)`.
    /// - Parameters:
    ///   - paper: render on a light card regardless of the theme (designed mail in dark mode).
    public static func css(theme: ResolvedTheme, fontSize: Double = 15, paper: Bool = false) -> String {
        let ink = paper ? "#1d1a14" : theme.ink
        let dim = paper ? "#6b6456" : theme.inkDim
        let link = paper ? "#8a6420" : (theme.isDark ? theme.accent : theme.accentText)
        let line = paper ? "#d9d3c4" : theme.line2
        let background = paper ? "#ffffff" : "transparent"
        return """
        :root { color-scheme: \(paper || !theme.isDark ? "light" : "dark"); }
        html, body { margin: 0; padding: 0; background: \(background); }
        body { font: \(fontSize)px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; color: \(ink);
               -webkit-font-smoothing: antialiased; overflow-wrap: anywhere; word-break: normal; \(paper ? "padding: 16px;" : "") }
        p { margin: 0 0 12px; }
        body > :last-child, p:last-of-type { margin-bottom: 0; }
        a { color: \(link); text-decoration: none; }
        a:hover { text-decoration: underline; }
        img { max-width: 100%; height: auto; }
        img[width="0"], img[height="0"], img[width="1"], img[height="1"] { display: none !important; }
        blockquote { margin: 8px 0; padding-left: 14px; border-left: 2px solid \(line); color: \(dim); }
        .gmail_quote { color: \(dim); }
        pre, code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.9em; white-space: pre-wrap; }
        table { max-width: 100%; }
        hr { border: none; border-top: 1px solid \(line); }
        """
    }
}
