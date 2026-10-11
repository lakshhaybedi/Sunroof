// Renders the Sunroof app icon into an .appiconset.
// Usage: swift scripts/make-icon.swift Sunroof/Assets.xcassets/AppIcon.appiconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.appiconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // macOS icon grid: 824/1024 rounded square, centred.
    let inset = s * 100 / 1024
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(srgbRed: 0.30, green: 0.36, blue: 0.98, alpha: 1),
                        NSColor(srgbRed: 0.55, green: 0.30, blue: 0.95, alpha: 1)])!.draw(in: path, angle: -90)
    // A "shelf" strip across the top, like the panel sliding down.
    NSColor.white.withAlphaComponent(0.22).setFill()
    NSBezierPath(roundedRect: NSRect(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.30,
                                     width: rect.width * 0.76, height: rect.height * 0.12),
                 xRadius: rect.height * 0.04, yRadius: rect.height * 0.04).fill()
    let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let glyph = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let g = glyph.size
        glyph.draw(in: NSRect(x: rect.midX - g.width / 2, y: rect.minY + rect.height * 0.16, width: g.width, height: g.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(points * scale).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(out.path)")
