import Foundation
import SwiftSoup

/// Prepares a message body for the sandboxed WKWebView reader: scripts, frames, forms, embeds, event handlers,
/// `javascript:` URLs, `<base>`, meta refresh and remote stylesheets are removed; remote images are blocked by a
/// Content-Security-Policy unless `allowRemoteImages` (the "Load images" button); `cid:` images can be replaced
/// with data URLs. The web view should also have JavaScript disabled and open links in the browser.
public enum MailHTML {
    public struct Prepared: Hashable, Sendable {
        /// A full HTML document.
        public var document: String
        /// The body references remote images (show the "Load images" button when they are blocked).
        public var hasRemoteImages: Bool
    }

    /// `css` is the theme stylesheet the app injects (colours, font, link style).
    public static func prepare(html: String?, text: String?, allowRemoteImages: Bool, css: String = "",
                               inlineImages: [String: Data] = [:], inlineTypes: [String: String] = [:]) -> Prepared {
        let source = html ?? HTMLSanitizer.plainTextToHTML(text ?? "")
        var hasRemote = false
        var body = source
        if let document = try? SwiftSoup.parse(source) {
            clean(document)
            hasRemote = containsRemoteImages(document)
            replaceCIDs(document, images: inlineImages, types: inlineTypes)
            body = (try? document.body()?.html()) ?? source
        }
        let imageSources = allowRemoteImages ? "data: https: http:" : "data:"
        let csp = "default-src 'none'; img-src \(imageSources); style-src 'unsafe-inline'; font-src data:; media-src 'none'; frame-src 'none'; form-action 'none'"
        let document = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style></head><body>\(body)</body></html>
        """
        return Prepared(document: document, hasRemoteImages: hasRemote)
    }

    static let removedTags = ["script", "iframe", "frame", "frameset", "object", "embed", "applet", "form", "input", "button", "textarea",
                              "select", "base", "link", "meta", "noscript", "audio", "video", "source", "svg", "math", "portal"]

    static func clean(_ document: Document) {
        for tag in removedTags { _ = try? document.select(tag).remove() }
        guard let all = try? document.getAllElements() else { return }
        for element in all.array() {
            guard let attributes = element.getAttributes() else { continue }
            for attribute in attributes.asList() {
                let key = attribute.getKey().lowercased()
                let value = attribute.getValue().trimmingCharacters(in: .whitespaces).lowercased()
                if key.hasPrefix("on") || key == "srcdoc" || key == "formaction" {
                    _ = try? element.removeAttr(attribute.getKey())
                } else if ["href", "src", "action", "background", "lowsrc", "dynsrc", "xlink:href"].contains(key),
                          value.hasPrefix("javascript:") || value.hasPrefix("vbscript:") || (value.hasPrefix("data:") && !value.hasPrefix("data:image/")) {
                    _ = try? element.removeAttr(attribute.getKey())
                } else if key == "style", value.contains("expression(") || value.contains("javascript:") {
                    _ = try? element.removeAttr(attribute.getKey())
                }
            }
        }
        // Links open in the browser.
        if let links = try? document.select("a[href]") {
            for link in links.array() { _ = try? link.attr("target", "_blank"); _ = try? link.attr("rel", "noopener noreferrer") }
        }
    }

    static func containsRemoteImages(_ document: Document) -> Bool {
        if let images = try? document.select("img[src]") {
            for image in images.array() {
                let src = ((try? image.attr("src")) ?? "").lowercased()
                if src.hasPrefix("http:") || src.hasPrefix("https:") || src.hasPrefix("//") { return true }
            }
        }
        if let styled = try? document.select("[style], [background]") {
            for element in styled.array() {
                let style = (((try? element.attr("style")) ?? "") + " " + ((try? element.attr("background")) ?? "")).lowercased()
                if style.contains("url(http") || style.contains("url('http") || style.contains("url(\"http") || style.hasPrefix(" http") { return true }
            }
        }
        return false
    }

    static func replaceCIDs(_ document: Document, images: [String: Data], types: [String: String]) {
        guard !images.isEmpty, let tags = try? document.select("img[src^=cid:]") else { return }
        for tag in tags.array() {
            let cid = String(((try? tag.attr("src")) ?? "").dropFirst(4))
            guard let data = images[cid] else { continue }
            let type = types[cid] ?? "image/png"
            _ = try? tag.attr("src", "data:\(type);base64,\(data.base64EncodedString())")
        }
    }
}
