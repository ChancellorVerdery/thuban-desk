// Renders Assets.xcassets/AppIcon.appiconset from AppArt (Brass, dark plate) — the Finder/Dock icon before launch.
// Usage: scripts/make_app_icon.sh (compiles this with the app's AppArt.swift and AppArtSource.swift).
// `--ios` (scripts/make_ios_icon.sh): one opaque full-bleed 1024 px icon for the iOS app (iOS masks the corners).
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iOSMode = CommandLine.arguments.contains("--ios")
func hex(_ s: String) -> CGColor {
    var v: UInt64 = 0; Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
    return CGColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let bg = hex("#090b11"), panel = hex("#0e1219"), accent = hex("#e0b15c"), signal = hex("#74d6c4"), rim = hex("#2a2e36")

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let s = CGFloat(px) / 1024
    cg.translateBy(x: 0, y: CGFloat(px)); cg.scaleBy(x: 1, y: -1)
    let plate = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 824 * 0.2237 * s, cornerHeight: 824 * 0.2237 * s, transform: nil)
    cg.addPath(platePath); cg.setFillColor(bg); cg.fillPath()
    cg.addPath(platePath); cg.setStrokeColor(rim); cg.setLineWidth(6 * s); cg.strokePath()
    let mark = plate.width * 0.62
    AppArt.draw(in: cg, rect: CGRect(x: plate.midX - mark / 2, y: plate.midY - mark / 2, width: mark, height: mark)) { role in
        switch role {
        case .accentStroke, .accentFill: return accent
        case .signalStroke, .signalFill: return signal
        case .panelFill: return panel
        case .bgFill: return bg
        }
    }
    return rep.representation(using: .png, properties: [:])!
}

/// iOS: the whole square is the plate (no rim, no transparency); the mark keeps the Mac icon's proportion to the plate.
func renderIOS(_ px: Int) -> Data {
    let cg = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let size = CGFloat(px)
    cg.translateBy(x: 0, y: size); cg.scaleBy(x: 1, y: -1)
    cg.setFillColor(bg); cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let mark = size * 0.6
    AppArt.draw(in: cg, rect: CGRect(x: (size - mark) / 2, y: (size - mark) / 2, width: mark, height: mark)) { role in
        switch role {
        case .accentStroke, .accentFill: return accent
        case .signalStroke, .signalFill: return signal
        case .panelFill: return panel
        case .bgFill: return bg
        }
    }
    return NSBitmapImageRep(cgImage: cg.makeImage()!).representation(using: .png, properties: [:])!
}

if iOSMode {
    try! renderIOS(1024).write(to: out.appendingPathComponent("AppIcon-1024.png"))
    let contents: [String: Any] = [
        "images": [["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "AppIcon-1024.png"]],
        "info": ["author": "xcode", "version": 1],
    ]
    try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("Contents.json"))
    print("wrote the iOS icon to \(out.path)")
    exit(0)
}

var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try! render(pt * scale).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
    }
}
let json = try! JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys])
try! json.write(to: out.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icons to \(out.path)")
