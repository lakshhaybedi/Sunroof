import AppKit

/// Pure frame/height math for the shelf panel.
enum ShelfGeometry {
    static let minHeight: CGFloat = 200
    static let maxFraction: CGFloat = 0.85
    static let defaultFraction: CGFloat = 0.5
    static let closeZone: CGFloat = 24 // pt above the panel's bottom edge where scroll-up closes

    static func clampHeight(_ h: CGFloat, visibleFrame: CGRect) -> CGFloat {
        min(max(h, minHeight), visibleFrame.height * maxFraction)
    }

    /// Full screen width, top flush with the bottom of the menu bar (or the screen top when it's hidden).
    static func frame(height: CGFloat, screenFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let h = clampHeight(height, visibleFrame: visibleFrame)
        return CGRect(x: screenFrame.minX, y: visibleFrame.maxY - h, width: screenFrame.width, height: h)
    }


    /// Where scrolling up closes the shelf: the strip above it (menu bar — where scroll-down opened it),
    /// the screen's top 2 pt when the menu bar is hidden, or the bottom `closeZone` of the shelf.
    static func isInCloseZone(_ p: CGPoint, panelFrame: CGRect, screenFrame: CGRect) -> Bool {
        guard p.x >= screenFrame.minX, p.x < screenFrame.maxX, p.y <= screenFrame.maxY + 1 else { return false }
        if p.y >= panelFrame.maxY || p.y >= screenFrame.maxY - EdgeTrigger.edgeTolerance { return true }
        return panelFrame.contains(p) && p.y <= panelFrame.minY + closeZone
    }

    @MainActor static func displayKey(_ screen: NSScreen) -> String {
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return "display-\(id?.uint32Value ?? 0)"
    }
}

/// Accumulates scroll-up inside a close zone; true once it adds up to a close.
struct ScrollCloseTracker {
    private var total: CGFloat = 0
    private var lastTime: TimeInterval = -.infinity

    mutating func add(upAmount: CGFloat, inZone: Bool, time: TimeInterval) -> Bool {
        defer { lastTime = time }
        guard inZone, upAmount > 0 else { total = 0; return false }
        if time - lastTime > EdgeTrigger.scrollGap { total = 0 }
        total += upAmount
        guard total >= EdgeTrigger.scrollThreshold else { return false }
        total = 0
        return true
    }
}
