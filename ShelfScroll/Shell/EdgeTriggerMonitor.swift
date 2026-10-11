import AppKit

/// Converts a scroll event into "pull down" amount (> 0 = fingers/wheel pulling content down).
func normalizedDownAmount(_ event: NSEvent, invert: Bool) -> CGFloat {
    let d = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
    return invert ? -d : d
}
