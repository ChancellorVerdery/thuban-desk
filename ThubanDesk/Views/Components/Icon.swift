import SwiftUI

/// The design's line icons (24×24, stroked 1.75, round caps — copied verbatim from the Desk artboards). Drawn in
/// the current foreground style; use `Icon(.mail, size: 16)`. Add new ones here (one case + its SVG elements).
enum IconName: String, CaseIterable {
    /// Calendar
    case calendar
    /// Mail
    case mail
    /// Today (sun)
    case today
    /// Search
    case search
    /// Settings (sliders)
    case settings
    /// Account (person)
    case account
    /// Guests (people)
    case guests
    /// Filters (funnel)
    case filter
    /// Notifications
    case bell
    /// Appearance (drop)
    case appearance
    /// About
    case info
    /// Add
    case plus
    /// Close
    case close
    /// Check
    case check
    /// Select (up/down chevrons)
    case upDown
    /// Chevron down
    case chevronDown
    /// Previous
    case chevronLeft
    /// Next
    case chevronRight
    /// Archive
    case archive
    /// Spam
    case spam
    /// Trash
    case trash
    /// Mark unread (open envelope)
    case markUnread
    /// Label (tag)
    case label
    /// Star
    case star
    /// Pin
    case pin
    /// More
    case more
    /// All inboxes (tray)
    case inbox
    /// Sent (paper plane)
    case sent
    /// Drafts (document)
    case drafts
    /// Reply
    case reply
    /// Reply all
    case replyAll
    /// Forward
    case forward
    /// Bulleted list
    case bulletList
    /// Numbered list
    case numberedList
    /// Quote
    case quote
    /// Link
    case link
    /// Clear formatting
    case clearFormat
    /// Attach (paperclip)
    case attach
    /// Repeats
    case repeats
    /// Time
    case clock
    /// Location
    case location
    /// Sync (Mail toolbar "Synced 2:38 PM")
    case sync
    /// Eye (Mail reader "Load images")
    case eye

    /// The SVG elements (paths, circles, rects) inside the 24×24 viewBox.
    var svg: String {
        switch self {
        case .calendar: return #"<rect x="3.5" y="5" width="17" height="15.5" rx="2"/><path d="M3.5 9.5h17"/><path d="M8 3v4"/><path d="M16 3v4"/>"#
        case .mail: return #"<rect x="3" y="5.5" width="18" height="13" rx="2"/><path d="M3.5 7l8.5 6 8.5-6"/>"#
        case .today: return #"<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2"/><path d="M12 19.5v2"/><path d="M2.5 12h2"/><path d="M19.5 12h2"/><path d="M5.3 5.3l1.4 1.4"/><path d="M17.3 17.3l1.4 1.4"/><path d="M5.3 18.7l1.4-1.4"/><path d="M17.3 6.7l1.4-1.4"/>"#
        case .search: return #"<circle cx="11" cy="11" r="6"/><path d="M20 20l-4.5-4.5"/>"#
        case .settings: return #"<path d="M4 7h9"/><path d="M17 7h3"/><circle cx="15" cy="7" r="2"/><path d="M4 17h3"/><path d="M11 17h9"/><circle cx="9" cy="17" r="2"/>"#
        case .account: return #"<circle cx="12" cy="8.5" r="3.5"/><path d="M5 20a7 7 0 0 1 14 0"/>"#
        case .guests: return #"<circle cx="9" cy="8.5" r="3.2"/><path d="M3 19.5a6 6 0 0 1 12 0"/><path d="M16 5.5a3 3 0 0 1 0 6"/><path d="M17.5 14a5.5 5.5 0 0 1 3.5 5.5"/>"#
        case .filter: return #"<path d="M4 5h16l-6 7.5v6l-4 2v-8z"/>"#
        case .bell: return #"<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>"#
        case .appearance: return #"<path d="M12 3.5s6 6.2 6 10.5a6 6 0 0 1-12 0c0-4.3 6-10.5 6-10.5z"/>"#
        case .info: return #"<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5"/><path d="M12 7.8v.2"/>"#
        case .plus: return #"<path d="M12 5v14"/><path d="M5 12h14"/>"#
        case .close: return #"<path d="M6.5 6.5l11 11"/><path d="M17.5 6.5l-11 11"/>"#
        case .check: return #"<path d="M5 12.5l4.5 4.5L19 7.5"/>"#
        case .upDown: return #"<path d="M8 9.5l4-4 4 4"/><path d="M8 14.5l4 4 4-4"/>"#
        case .chevronDown: return #"<path d="M6.5 9.5l5.5 5.5 5.5-5.5"/>"#
        case .chevronLeft: return #"<path d="M14.5 6l-6 6 6 6"/>"#
        case .chevronRight: return #"<path d="M9.5 6l6 6-6 6"/>"#
        case .archive: return #"<rect x="3.5" y="4.5" width="17" height="4" rx="1"/><path d="M5 8.5v10a1.5 1.5 0 0 0 1.5 1.5h11a1.5 1.5 0 0 0 1.5-1.5v-10"/><path d="M10 12.5h4"/>"#
        case .spam: return #"<path d="M8.5 3.5h7l5 5v7l-5 5h-7l-5-5v-7z"/><path d="M12 8v5"/><path d="M12 16.2v.3"/>"#
        case .trash: return #"<path d="M4.5 7h15"/><path d="M9.5 7V4.5h5V7"/><path d="M6.5 7l1 12.5a1.5 1.5 0 0 0 1.5 1.5h6a1.5 1.5 0 0 0 1.5-1.5l1-12.5"/><path d="M10 11v6"/><path d="M14 11v6"/>"#
        case .markUnread: return #"<path d="M3.5 10l8.5-6 8.5 6v9a1.5 1.5 0 0 1-1.5 1.5h-14A1.5 1.5 0 0 1 3.5 19z"/><path d="M3.5 10l8.5 6 8.5-6"/>"#
        case .label: return #"<path d="M3.5 12.5V4.5a1 1 0 0 1 1-1h8l8 8-9 9z"/><circle cx="8" cy="8" r="1.4"/>"#
        case .star: return #"<path d="M12 3.8l2.5 5.2 5.7.8-4.1 4 1 5.7L12 16.8l-5.1 2.7 1-5.7-4.1-4 5.7-.8z"/>"#
        case .pin: return #"<path d="M9 3.5h6l-1 6 3.5 3.5v1.5h-11V13L10 9.5z"/><path d="M12 14.5V21"/>"#
        case .more: return #"<path d="M6 12h.01"/><path d="M12 12h.01"/><path d="M18 12h.01"/>"#
        case .inbox: return #"<path d="M3.5 14l2.5-7h12l2.5 7v4.5a1.5 1.5 0 0 1-1.5 1.5h-14A1.5 1.5 0 0 1 3.5 18.5z"/><path d="M3.5 14h5l1 2h5l1-2h5"/><path d="M7.5 3.5h9"/>"#
        case .sent: return #"<path d="M20.5 3.5L10 14"/><path d="M20.5 3.5l-6.5 17-4-6.5-6.5-4z"/>"#
        case .drafts: return #"<path d="M14 3.5H6.5A1.5 1.5 0 0 0 5 5v14a1.5 1.5 0 0 0 1.5 1.5h11A1.5 1.5 0 0 0 19 19V8.5z"/><path d="M14 3.5v5h5"/><path d="M9 13h6"/><path d="M9 16.5h4"/>"#
        case .reply: return #"<path d="M9.5 7.5L4.5 12.5l5 5"/><path d="M4.5 12.5h9a6 6 0 0 1 6 6v1"/>"#
        case .replyAll: return #"<path d="M7.5 7.5L2.5 12.5l5 5"/><path d="M12 7.5L7 12.5l5 5"/><path d="M7 12.5h7.5a6 6 0 0 1 6 6v1"/>"#
        case .forward: return #"<path d="M14.5 7.5l5 5-5 5"/><path d="M19.5 12.5h-9a6 6 0 0 0-6 6v1"/>"#
        case .bulletList: return #"<path d="M9.5 6.5h10"/><path d="M9.5 12h10"/><path d="M9.5 17.5h10"/><path d="M5 6.5v.01"/><path d="M5 12v.01"/><path d="M5 17.5v.01"/>"#
        case .numberedList: return #"<path d="M10 6.5h9.5"/><path d="M10 12h9.5"/><path d="M10 17.5h9.5"/><path d="M4.5 5l1.5-1v5"/><path d="M4.5 14.5a1.5 1.5 0 0 1 3 0c0 1-3 2.5-3 3.5h3"/>"#
        case .quote: return #"<path d="M5 18.5V13a5.5 5.5 0 0 1 4-5.3"/><path d="M5 13h4v5.5H5"/><path d="M14 18.5V13a5.5 5.5 0 0 1 4-5.3"/><path d="M14 13h4v5.5h-4"/>"#
        case .link: return #"<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>"#
        case .clearFormat: return #"<path d="M6 5.5h12"/><path d="M12 5.5l-3 13"/><path d="M14.5 14.5l5 5"/><path d="M19.5 14.5l-5 5"/>"#
        case .attach: return #"<path d="M20 11.5l-8 8a5 5 0 0 1-7-7l8.5-8.5a3.3 3.3 0 0 1 4.7 4.7l-8.5 8.5a1.7 1.7 0 0 1-2.4-2.4l7.8-7.8"/>"#
        case .repeats: return #"<path d="M4.5 11V9.5a3 3 0 0 1 3-3h11"/><path d="M15.5 3.5l3 3-3 3"/><path d="M19.5 13v1.5a3 3 0 0 1-3 3h-11"/><path d="M8.5 20.5l-3-3 3-3"/>"#
        case .clock: return #"<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>"#
        case .location: return #"<path d="M12 21s-6.5-6-6.5-11a6.5 6.5 0 0 1 13 0c0 5-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.3"/>"#
        case .sync: return #"<path d="M19.5 11a7.5 7.5 0 0 0-13.6-3.5"/><path d="M4.5 13a7.5 7.5 0 0 0 13.6 3.5"/><path d="M5.5 3.5v4h4"/><path d="M18.5 20.5v-4h-4"/>"#
        case .eye: return #"<path d="M2.5 12s3.5-6.5 9.5-6.5 9.5 6.5 9.5 6.5-3.5 6.5-9.5 6.5S2.5 12 2.5 12z"/><circle cx="12" cy="12" r="2.8"/>"#
        }
    }

    /// Parsed once per icon.
    var path: CGPath { IconPaths.shared.path(for: self) }
}

/// Caches parsed icon paths.
final class IconPaths: @unchecked Sendable {
    static let shared = IconPaths()
    private var cache: [IconName: CGPath] = [:]
    private let lock = NSLock()

    func path(for icon: IconName) -> CGPath {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[icon] { return hit }
        let layers = SVGArtParser.parse("<svg viewBox=\"0 0 24 24\"><g class=\"a\" stroke-width=\"1.75\">\(icon.svg)</g></svg>")
        let combined = CGMutablePath()
        for layer in layers { combined.addPath(layer.path) }
        cache[icon] = combined
        return combined
    }
}

/// A design icon at 13–20 pt, stroked in the current foreground style.
struct Icon: View {
    var name: IconName
    var size: CGFloat = 18
    var lineWidth: CGFloat = 1.75

    init(_ name: IconName, size: CGFloat = 18, lineWidth: CGFloat = 1.75) {
        self.name = name
        self.size = size
        self.lineWidth = lineWidth
    }

    /// Looks an icon up by its name ("mail"); unknown names draw nothing.
    init?(name: String, size: CGFloat = 18) {
        guard let icon = IconName(rawValue: name) else { return nil }
        self.name = icon
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 24
            let path = Path(name.path).applying(CGAffineTransform(scaleX: scale, y: scale))
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Minimal stroke glyphs the icon set does not include (plus, close, check, chevron, search, send, lock, drag, reset).
struct Glyph: View {
    enum Kind { case plus, close, check, chevronDown, chevronRight, chevronLeft, search, send, lock, dragHandle, dot, reset }
    var kind: Kind
    var size: CGFloat = 16

    init(_ kind: Kind, size: CGFloat = 16) {
        self.kind = kind
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var path = Path()
            switch kind {
            case .plus:
                path.move(to: p(12, 5)); path.addLine(to: p(12, 19))
                path.move(to: p(5, 12)); path.addLine(to: p(19, 12))
            case .close:
                path.move(to: p(6, 6)); path.addLine(to: p(18, 18))
                path.move(to: p(18, 6)); path.addLine(to: p(6, 18))
            case .check:
                path.move(to: p(5, 12.5)); path.addLine(to: p(10, 17.5)); path.addLine(to: p(19, 7))
            case .chevronDown:
                path.move(to: p(6, 9.5)); path.addLine(to: p(12, 15.5)); path.addLine(to: p(18, 9.5))
            case .chevronRight:
                path.move(to: p(9.5, 6)); path.addLine(to: p(15.5, 12)); path.addLine(to: p(9.5, 18))
            case .chevronLeft:
                path.move(to: p(14.5, 6)); path.addLine(to: p(8.5, 12)); path.addLine(to: p(14.5, 18))
            case .search:
                path.addEllipse(in: CGRect(x: 4 * s, y: 4 * s, width: 11 * s, height: 11 * s))
                path.move(to: p(13.5, 13.5)); path.addLine(to: p(20, 20))
            case .send:
                path.move(to: p(4, 12)); path.addLine(to: p(20, 4)); path.addLine(to: p(14, 20)); path.addLine(to: p(11.5, 12.5)); path.closeSubpath()
            case .lock:
                path.addRoundedRect(in: CGRect(x: 5 * s, y: 11 * s, width: 14 * s, height: 9.5 * s), cornerSize: CGSize(width: 2 * s, height: 2 * s))
                path.move(to: p(8, 11)); path.addLine(to: p(8, 8))
                path.addArc(center: p(12, 8), radius: 4 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                path.addLine(to: p(16, 11))
            case .dragHandle:
                for y: CGFloat in [7, 12, 17] {
                    path.move(to: p(9, y)); path.addLine(to: p(9.01, y))
                    path.move(to: p(15, y)); path.addLine(to: p(15.01, y))
                }
            case .dot:
                path.addEllipse(in: CGRect(x: 8 * s, y: 8 * s, width: 8 * s, height: 8 * s))
            case .reset:
                // Counter-clockwise arc with an arrowhead at its start (the "reset view" convention).
                path.addArc(center: p(12, 12.5), radius: 7 * s, startAngle: .degrees(-150), endAngle: .degrees(120), clockwise: false)
                path.move(to: p(3.4, 4.5)); path.addLine(to: p(5.9, 9)); path.addLine(to: p(10.4, 7.2))
            }
            let style = StrokeStyle(lineWidth: (kind == .dragHandle ? 2.5 : 1.75) * s, lineCap: .round, lineJoin: .round)
            if kind == .dot {
                context.fill(path, with: .foreground)
            } else {
                context.stroke(path, with: .foreground, style: style)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
