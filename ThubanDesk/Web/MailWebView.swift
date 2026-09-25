import AppKit
import SwiftUI
import ThubanDeskCore
import WebKit

/// A message body in a sandboxed WKWebView: page JavaScript off, a non-persistent data store (no cookies, no
/// cache shared with anything), no network at all except remote images when the user allows them (the CSP from
/// `MailHTML.prepare` decides), every link opened in the default browser. The view sizes itself to its content and
/// passes scrolling to the reader around it. While `frozen` (a sheet or the Compose window covers the reader) it
/// shows a still image of itself, so overlays always draw above the message.
struct MailWebView: NSViewRepresentable {
    /// The full document from `MailHTML.prepare`.
    var document: String
    @Binding var height: CGFloat
    var frozen: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeNSView(context: Context) -> ReaderWebContainer {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.suppressesIncrementalRendering = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let view = ReaderWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.allowsBackForwardNavigationGestures = false
        view.allowsMagnification = false
        view.setAccessibilityLabel("Message body")
        view.onWidthChange = { [weak coordinator = context.coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.remeasure(view)
        }
        context.coordinator.load(document, in: view)
        let container = ReaderWebContainer(web: view)
        context.coordinator.container = container
        container.setFrozen(frozen)
        return container
    }

    func updateNSView(_ container: ReaderWebContainer, context: Context) {
        context.coordinator.height = $height
        context.coordinator.load(document, in: container.web)
        container.setFrozen(frozen)
    }

    static func dismantleNSView(_ container: ReaderWebContainer, coordinator: Coordinator) {
        container.web.stopLoading()
        container.web.navigationDelegate = nil
        container.web.uiDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var height: Binding<CGFloat>
        weak var container: ReaderWebContainer?
        private var loaded: String?

        init(height: Binding<CGFloat>) { self.height = height }

        func load(_ document: String, in view: WKWebView) {
            guard document != loaded else { return }
            loaded = document
            // about:blank base: relative URLs resolve to nothing; no file access.
            view.loadHTMLString(document, baseURL: URL(string: "about:blank"))
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let url = action.request.url
            if action.navigationType == .linkActivated || action.targetFrame == nil {
                if let url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
                return
            }
            // Only our own document (loadHTMLString) may load in the frame.
            let scheme = url?.scheme?.lowercased()
            decisionHandler(scheme == "about" || scheme == nil ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measure(webView)
            // Late layout (images, fonts): measure again shortly after.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.measure(webView)
            }
        }

        private var pendingMeasure: DispatchWorkItem?

        func remeasure(_ webView: WKWebView) {
            pendingMeasure?.cancel()
            let work = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView, !webView.isLoading else { return }
                self.measure(webView)
            }
            pendingMeasure = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        private func measure(_ webView: WKWebView) {
            // Native-side script in the client world (page scripts stay disabled; the page's CSP does not apply here).
            webView.evaluateJavaScript("Math.ceil(document.body.getBoundingClientRect().height) + 2",
                                       in: nil, in: .defaultClient) { [weak self] result in
                guard let self, case .success(let value) = result, let number = value as? NSNumber else { return }
                let measured = max(20, CGFloat(truncating: number))
                if abs(measured - self.height.wrappedValue) > 1 { self.height.wrappedValue = measured }
                self.container?.refreshStill()
            }
        }
    }
}

/// Hands scroll-wheel events to the enclosing scroll view (the web view is sized to its content and never scrolls).
final class ReaderWebView: WKWebView {
    /// Called when the width changes (text reflows, so the height must be measured again).
    var onWidthChange: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if changed { onWidthChange?() }
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

/// The web view plus a still image of it (shown while frozen).
final class ReaderWebContainer: NSView {
    let web: ReaderWebView
    private let still = NSImageView()
    private var frozen = false

    init(web: ReaderWebView) {
        self.web = web
        super.init(frame: .zero)
        web.frame = bounds
        web.autoresizingMask = [.width, .height]
        addSubview(web)
        still.frame = bounds
        still.autoresizingMask = [.width, .height]
        still.imageScaling = .scaleAxesIndependently
        still.isHidden = true
        still.setAccessibilityElement(false)
        addSubview(still)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }

    /// Retakes the still image (the page finished loading or resized while frozen).
    func refreshStill() {
        guard frozen else { return }
        web.isHidden = false
        web.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self, self.frozen, let image else { return }
            self.still.image = image
            self.still.isHidden = false
            self.web.isHidden = true
        }
    }

    func setFrozen(_ value: Bool) {
        guard value != frozen else { return }
        frozen = value
        if value {
            web.takeSnapshot(with: nil) { [weak self] image, _ in
                guard let self, self.frozen, let image else { return }
                self.still.image = image
                self.still.isHidden = false
                self.web.isHidden = true
            }
        } else {
            web.isHidden = false
            still.isHidden = true
            still.image = nil
        }
    }
}
