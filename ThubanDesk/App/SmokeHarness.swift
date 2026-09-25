import AppKit
import Foundation
import ThubanDeskCore
import WebKit
import os

/// One screen of the smoke walk: `prepare` puts the app in a state; the harness waits `settle` seconds and writes
/// `<name>.png`. Each area registers its scenes in its own `…SmokeScenes.swift` (see `SmokeScenes.all`).
struct SmokeScene {
    enum Capture { case window, sheet }

    var name: String
    var capture: Capture
    var settle: Double
    var prepare: @MainActor (AppModel) async -> Void

    init(_ name: String, capture: Capture = .window, settle: Double = 1.5, prepare: @escaping @MainActor (AppModel) async -> Void) {
        self.name = name
        self.capture = capture
        self.settle = settle
        self.prepare = prepare
    }
}

/// The scene registry, in walk order. Each area owns its list; add scenes there, not here.
enum SmokeScenes {
    @MainActor
    static var all: [SmokeScene] {
        ShellSmokeScenes.first + CalendarSmokeScenes.scenes + MailSmokeScenes.scenes + TodaySmokeScenes.scenes
            + SettingsSmokeScenes.scenes + IntegrationSmokeScenes.scenes + ShellSmokeScenes.last
    }
}

/// Visual smoke test driven by `THUBAN_DESK_SMOKE=<output dir>` (scripts/smoke.sh): with the fixture backend
/// (`THUBAN_DESK_FIXTURES=1`) and a pinned clock, walks every registered scene at the design's 1440 × 900, writes
/// PNGs (native content + any WKWebView snapshots composited) and quits. Never confirms anything: a scene that
/// opens a ConfirmWriteSheet is captured and dismissed.
@MainActor
enum SmokeHarness {
    static let variable = "THUBAN_DESK_SMOKE"
    private static let logger = Logger(subsystem: "com.thuban.desk", category: "smoke")

    static var outputDirectory: URL? {
        guard let raw = ProcessInfo.processInfo.environment[variable]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    static var isEnabled: Bool { outputDirectory != nil }

    /// `THUBAN_DESK_SMOKE_SCENES=calendar,mail` keeps scenes whose name contains any of the words.
    static var filter: [String] {
        (ProcessInfo.processInfo.environment["THUBAN_DESK_SMOKE_SCENES"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    static func startIfEnabled(app: AppModel) {
        guard let directory = outputDirectory else { return }
        Task { await run(app: app, directory: directory) }
    }

    private static func run(app: AppModel, directory: URL) async {
        var status: Int32 = 0
        do {
            guard app.isFixtureMode else { throw ThubanError.store("smoke requires THUBAN_DESK_FIXTURES=1 (never runs against real accounts)") }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let window = try await waitForWindow(timeout: 10) { $0.isVisible && $0.contentView != nil }
            window.setContentSize(NSSize(width: 1440, height: 900))
            app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            await sleep(1.0)
            let words = filter
            for scene in SmokeScenes.all where words.isEmpty || words.contains(where: { scene.name.lowercased().contains($0) }) {
                await scene.prepare(app)
                await sleep(scene.settle)
                switch scene.capture {
                case .window:
                    _ = try await capture(window: window, name: scene.name, in: directory)
                case .sheet:
                    let sheet = try await waitForSheet(of: window)
                    await sleep(0.5)
                    _ = try await capture(window: sheet, name: scene.name, in: directory)
                    app.pendingConfirmation = nil
                    await sleep(0.5)
                }
            }
            if let fixture = app.fixture {
                let unexpected = fixture.log.filter { $0.hasSuffix("/messages/send") || $0.hasSuffix("/drafts/send") }
                if !unexpected.isEmpty { throw ThubanError.store("smoke: a send endpoint was called: \(unexpected)") }
            }
        } catch {
            logger.error("smoke failed: \(error.localizedDescription, privacy: .public)")
            fputs("smoke: FAILED: \(error.localizedDescription)\n", stderr)
            status = 1
        }
        print("smoke: done")
        app.flushSettings()
        exit(status)
    }

    private static func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func waitForWindow(timeout: Double, _ predicate: (NSWindow) -> Bool) async throws -> NSWindow {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let window = NSApp.windows.first(where: predicate) { return window }
            await sleep(0.1)
        }
        throw ThubanError.store("smoke: window did not appear within \(Int(timeout)) s")
    }

    private static func waitForSheet(of window: NSWindow) async throws -> NSWindow {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let sheet = window.attachedSheet { return sheet }
            await sleep(0.1)
        }
        throw ThubanError.store("smoke: sheet did not appear")
    }

    /// Renders the window's native content (`cacheDisplay`) and composites every visible `WKWebView` snapshot at its
    /// window position. No screen-recording permission involved.
    private static func capture(window: NSWindow, name: String, in directory: URL) async throws -> URL {
        guard let content = window.contentView else { throw ThubanError.store("smoke: window has no content view") }
        let bounds = content.bounds
        guard let nativeRep = content.bitmapImageRepForCachingDisplay(in: bounds) else { throw ThubanError.store("smoke: no bitmap for \(name)") }
        content.cacheDisplay(in: bounds, to: nativeRep)
        let native = NSImage(size: bounds.size)
        native.addRepresentation(nativeRep)

        let contentOrigin = content.convert(content.bounds, to: nil).origin
        var overlays: [(rect: NSRect, image: NSImage, source: NSRect)] = []
        for webView in subviews(of: content).compactMap({ $0 as? WKWebView }) {
            let visible = webView.visibleRect
            guard !webView.isHiddenOrHasHiddenAncestor, webView.window === window, visible.width > 1, visible.height > 1 else { continue }
            var rect = webView.convert(visible, to: nil)
            rect.origin.x -= contentOrigin.x
            rect.origin.y -= contentOrigin.y
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = true
            if let image = try? await webView.takeSnapshot(configuration: configuration) {
                let sourceY = webView.isFlipped ? webView.bounds.height - visible.maxY : visible.minY
                overlays.append((rect, image, NSRect(x: visible.minX, y: sourceY, width: visible.width, height: visible.height)))
            }
        }

        let scale = window.backingScaleFactor
        guard let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw ThubanError.store("smoke: could not allocate the output bitmap")
        }
        output.size = bounds.size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: output) else { throw ThubanError.store("smoke: no graphics context") }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        native.draw(in: NSRect(origin: .zero, size: bounds.size))
        for overlay in overlays { overlay.image.draw(in: overlay.rect, from: overlay.source, operation: .sourceOver, fraction: 1) }
        context.flushGraphics()
        guard let png = output.representation(using: .png, properties: [:]) else { throw ThubanError.store("smoke: PNG encoding failed for \(name)") }
        let url = directory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("smoke: \(name)")
        return url
    }

    private static func subviews(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + subviews(of: $0) }
    }
}
