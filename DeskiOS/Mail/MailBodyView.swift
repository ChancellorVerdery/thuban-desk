import SwiftUI
import ThubanDeskCore
import UIKit
import WebKit

/// A message body in a sandboxed WKWebView (same rules as the Mac reader): the document comes from the core
/// `MailHTML.prepare` sanitizer (scripts, frames, forms, handlers removed; remote images blocked by CSP until "Load
/// images"), page JavaScript is off, the data store is non-persistent, only our own document may load, and links open
/// in Safari / Mail. The view is as tall as its content and never scrolls itself.
struct MailBodyView: UIViewRepresentable {
    var document: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.suppressesIncrementalRendering = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.dataDetectorTypes = [.phoneNumber, .link]
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.allowsLinkPreview = true
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.accessibilityLabel = "Message body"
        context.coordinator.load(document, in: view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.height = $height
        context.coordinator.load(document, in: view)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var height: Binding<CGFloat>
        private var loaded: String?
        private var lastWidth: CGFloat = 0

        init(height: Binding<CGFloat>) { self.height = height }

        func load(_ document: String, in view: WKWebView) {
            if abs(view.bounds.width - lastWidth) > 0.5, loaded != nil {
                lastWidth = view.bounds.width
                measure(view)
            }
            guard document != loaded else { return }
            loaded = document
            view.loadHTMLString(document, baseURL: URL(string: "about:blank"))
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let url = action.request.url
            if action.navigationType == .linkActivated || action.targetFrame == nil {
                if let url, ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") { UIApplication.shared.open(url) }
                decisionHandler(.cancel)
                return
            }
            let scheme = url?.scheme?.lowercased()
            decisionHandler(scheme == "about" || scheme == nil ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { UIApplication.shared.open(url) }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            lastWidth = webView.bounds.width
            measure(webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.measure(webView)
            }
        }

        private func measure(_ webView: WKWebView) {
            // Client-world script (page scripts stay disabled; the page CSP does not apply here).
            webView.evaluateJavaScript("Math.ceil(document.body.getBoundingClientRect().height) + 4", in: nil, in: .defaultClient) { [weak self] result in
                guard let self, case .success(let value) = result, let number = value as? NSNumber else { return }
                let measured = max(24, CGFloat(truncating: number))
                if abs(measured - self.height.wrappedValue) > 1 { self.height.wrappedValue = measured }
            }
        }
    }
}
