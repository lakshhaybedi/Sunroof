// Renders the Sunroof app icon (and README logo).
// Usage: swift scripts/make-icon.swift <AppIcon.appiconset dir> [logo.png]
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
let iconset = URL(fileURLWithPath: args.first ?? "AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }

/// Draws the icon artwork into the current context, in a square of side `s`.
func drawIcon(_ s: CGFloat) {
    // macOS grid: 824/1024 squircle-ish rounded square, centred.
    let inset = s * 100 / 1024
    let tile = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

    // Soft drop shadow under the tile.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    rgb(30, 27, 75).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // The roof: deep dusk gradient.
    NSGradient(colors: [rgb(49, 46, 129), rgb(30, 27, 75), rgb(17, 16, 48)])!.draw(in: tilePath, angle: -90)

    // The opening (sunroof) near the top.
    let opening = NSRect(x: tile.minX + tile.width * 0.14, y: tile.maxY - tile.height * 0.46,
                         width: tile.width * 0.72, height: tile.height * 0.32)
    let openingPath = NSBezierPath(roundedRect: opening, xRadius: opening.height * 0.22, yRadius: opening.height * 0.22)

    // Light falling from the opening onto the roof.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    let beam = NSBezierPath()
    beam.move(to: NSPoint(x: opening.minX + opening.width * 0.08, y: opening.minY))
    beam.line(to: NSPoint(x: opening.maxX - opening.width * 0.08, y: opening.minY))
    beam.line(to: NSPoint(x: tile.maxX - tile.width * 0.06, y: tile.minY + tile.height * 0.12))
    beam.line(to: NSPoint(x: tile.minX + tile.width * 0.06, y: tile.minY + tile.height * 0.12))
    beam.close()
    NSGradient(colorsAndLocations: (rgb(255, 205, 140, 0.30), 0), (rgb(255, 160, 150, 0.10), 0.55), (rgb(255, 160, 150, 0), 1))!
        .draw(in: beam, angle: -90)
    // A few dusk stars on the roof.
    NSColor.white.withAlphaComponent(0.75).setFill()
    for (x, y, r) in [(0.10, 0.80, 0.010), (0.90, 0.86, 0.008), (0.84, 0.30, 0.007), (0.13, 0.36, 0.006), (0.93, 0.62, 0.006)] {
        let c = NSPoint(x: tile.minX + tile.width * x, y: tile.minY + tile.height * y)
        let rr = tile.width * r
        NSBezierPath(ovalIn: NSRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    // Sky through the opening: sunrise gradient + sun.
    NSGraphicsContext.saveGraphicsState()
    openingPath.addClip()
    NSGradient(colors: [rgb(255, 214, 120), rgb(255, 150, 110), rgb(236, 92, 140)])!.draw(in: opening, angle: -90)
    let sunR = opening.height * 0.42
    let sunC = NSPoint(x: opening.midX, y: opening.minY + opening.height * 0.18)
    NSGradient(colors: [rgb(255, 250, 220), rgb(255, 226, 140)])!
        .draw(in: NSBezierPath(ovalIn: NSRect(x: sunC.x - sunR, y: sunC.y - sunR, width: sunR * 2, height: sunR * 2)),
              relativeCenterPosition: NSPoint(x: 0, y: 0.3))
    // Glass panel slid back over the top part of the opening.
    let glass = NSRect(x: opening.minX, y: opening.maxY - opening.height * 0.36, width: opening.width, height: opening.height * 0.36)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.55), NSColor.white.withAlphaComponent(0.18)])!.draw(in: glass, angle: -90)
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSRect(x: glass.minX, y: glass.minY, width: glass.width, height: max(1, s * 0.006)).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Rim of the opening.
    NSColor.white.withAlphaComponent(0.55).setStroke()
    openingPath.lineWidth = max(1, s * 0.008)
    openingPath.stroke()

    // Top highlight on the tile edge.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: tile.minX, y: tile.maxY - tile.height * 0.12, width: tile.width, height: tile.height * 0.12), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
}

func png(width: Int, height: Int, draw: (CGFloat, CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(width), CGFloat(height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(width: px, height: px) { s, _ in drawIcon(s) }.write(to: iconset.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
try JSONSerialization.data(withJSONObject: ["images": images, "info": ["version": 1, "author": "xcode"]],
                           options: [.prettyPrinted, .sortedKeys]).write(to: iconset.appendingPathComponent("Contents.json"))

// README logo: icon + "Sunroof" wordmark with a sunrise gradient (readable on light and dark backgrounds).
if args.count > 1 {
    let logo = png(width: 1400, height: 400) { w, h in
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform(); t.translateX(by: 20, yBy: 20); t.concat()
        drawIcon(360)
        NSGraphicsContext.restoreGraphicsState()
        let font = NSFont.systemFont(ofSize: 190, weight: .bold)
        let text = NSAttributedString(string: "Sunroof", attributes: [.font: font])
        let size = text.size()
        let origin = NSPoint(x: 420, y: (h - size.height) / 2 + 10)
        // Gradient-filled text via a clip mask.
        let image = NSImage(size: NSSize(width: size.width, height: size.height), flipped: false) { r in
            text.draw(at: .zero); return true
        }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(origin: origin, size: size), mask: cg)
        NSGradient(colors: [rgb(255, 170, 90), rgb(236, 92, 140), rgb(120, 90, 230)])!
            .draw(in: NSRect(origin: origin, size: size), angle: 0)
        ctx.restoreGState()
        _ = w
    }
    try logo.write(to: URL(fileURLWithPath: args[1]))
}
print("Wrote \(images.count) icons\(args.count > 1 ? " and the logo" : "")")
