import AppKit

/// The menu bar glyph: a roof with its sunroof open and the sun peeking through. Template image, so macOS tints it.
enum MenuBarIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let s = r.width
            NSColor.black.set()
            let line = max(1.3, s * 0.085)
            // The roof: a rounded square outline.
            let roof = NSBezierPath(roundedRect: r.insetBy(dx: line / 2 + s * 0.04, dy: line / 2 + s * 0.04),
                                    xRadius: s * 0.24, yRadius: s * 0.24)
            roof.lineWidth = line
            roof.stroke()
            // The opening near the top, filled.
            let opening = NSRect(x: s * 0.22, y: s * 0.46, width: s * 0.56, height: s * 0.30)
            NSBezierPath(roundedRect: opening, xRadius: s * 0.06, yRadius: s * 0.06).fill()
            // Sun rising in the opening (cut out), with rays falling below it.
            NSGraphicsContext.current?.compositingOperation = .clear
            let sun = NSRect(x: s * 0.36, y: s * 0.33, width: s * 0.28, height: s * 0.28)
            NSBezierPath(ovalIn: sun).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.set()
            let rays = NSBezierPath()
            rays.lineWidth = max(1, s * 0.07)
            rays.lineCapStyle = .round
            for (x0, x1) in [(0.36, 0.28), (0.50, 0.50), (0.64, 0.72)] {
                rays.move(to: NSPoint(x: s * x0, y: s * 0.36))
                rays.line(to: NSPoint(x: s * x1, y: s * 0.22))
            }
            rays.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Sunroof"
        return image
    }
}
