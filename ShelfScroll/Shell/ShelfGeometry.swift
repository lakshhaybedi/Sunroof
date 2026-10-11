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

    static func shouldCloseOnScroll(point: CGPoint, panelFrame: CGRect, upAmount: CGFloat) -> Bool {
        upAmount >= EdgeTrigger.scrollThreshold
            && panelFrame.contains(point)
            && point.y <= panelFrame.minY + closeZone
    }

    @MainActor static func displayKey(_ screen: NSScreen) -> String {
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return "display-\(id?.uint32Value ?? 0)"
    }
}
