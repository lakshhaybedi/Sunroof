import CoreGraphics
import Testing
@testable import Sunroof

@Suite struct ShelfGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)

    @Test func clampsToMin() {
        #expect(ShelfGeometry.clampHeight(50, visibleFrame: visible) == 200)
    }

    @Test func clampsToMax() {
        #expect(ShelfGeometry.clampHeight(5000, visibleFrame: visible) == 949 * 0.85)
    }

    @Test func oversizedSavedHeightClamped() {
        let small = CGRect(x: 0, y: 0, width: 1512, height: 700)
        #expect(ShelfGeometry.clampHeight(1200, visibleFrame: small) == 595)
    }

    @Test func frameUnderMenuBar() {
        #expect(ShelfGeometry.frame(height: 400, screenFrame: screen, visibleFrame: visible)
                == CGRect(x: 0, y: 549, width: 1512, height: 400))
    }

    @Test func frameWithHiddenMenuBar() {
        #expect(ShelfGeometry.frame(height: 400, screenFrame: screen, visibleFrame: screen)
                == CGRect(x: 0, y: 582, width: 1512, height: 400))
    }

    @Test func frameOnOffsetScreen() {
        let s = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let v = CGRect(x: 1512, y: -200, width: 1920, height: 1055)
        #expect(ShelfGeometry.frame(height: 400, screenFrame: s, visibleFrame: v)
                == CGRect(x: 1512, y: 455, width: 1920, height: 400))
    }

    let panel = CGRect(x: 0, y: 549, width: 1512, height: 400)
    let nearBottom = CGPoint(x: 700, y: 560)
    let inMenuBar = CGPoint(x: 700, y: 970)

    // Scroll up closes where scroll down opened (the menu bar strip at the top of the screen) and at the bottom edge.
    @Test func closeZones() {
        #expect(ShelfGeometry.isInCloseZone(inMenuBar, panelFrame: panel, screenFrame: screen))
        #expect(ShelfGeometry.isInCloseZone(CGPoint(x: 700, y: 981), panelFrame: panel, screenFrame: screen))
        #expect(ShelfGeometry.isInCloseZone(nearBottom, panelFrame: panel, screenFrame: screen))
        #expect(!ShelfGeometry.isInCloseZone(CGPoint(x: 700, y: 700), panelFrame: panel, screenFrame: screen))
        #expect(!ShelfGeometry.isInCloseZone(CGPoint(x: 2000, y: 970), panelFrame: panel, screenFrame: screen))
    }

    // Hidden menu bar (full screen): the panel reaches the screen top; its top 2 pt is the edge.
    @Test func closeZoneWithHiddenMenuBar() {
        let full = CGRect(x: 0, y: 582, width: 1512, height: 400)
        #expect(ShelfGeometry.isInCloseZone(CGPoint(x: 700, y: 981), panelFrame: full, screenFrame: screen))
        #expect(!ShelfGeometry.isInCloseZone(CGPoint(x: 700, y: 900), panelFrame: full, screenFrame: screen))
    }

    @Test func closeOnSingleLargeScrollUp() {
        var c = ScrollCloseTracker()
        do { let r = c.add(upAmount: 8, inZone: true, time: 0); #expect(r) }
    }

    @Test func closeIgnoresScrollOutsideZone() {
        var c = ScrollCloseTracker()
        do { let r = c.add(upAmount: 8, inZone: false, time: 0); #expect(!r) }
    }

    // Slow swipes (1–3 pt per event) accumulate to a close.
    @Test func closeAccumulatesSmallScrolls() {
        var c = ScrollCloseTracker()
        do { let r = c.add(upAmount: 2, inZone: true, time: 0); #expect(!r) }
        do { let r = c.add(upAmount: 2, inZone: true, time: 0.05); #expect(!r) }
        do { let r = c.add(upAmount: 2, inZone: true, time: 0.1); #expect(r) }
    }

    @Test func closeAccumulatorResetsOnPause() {
        var c = ScrollCloseTracker()
        _ = c.add(upAmount: 4, inZone: true, time: 0)
        do { let r = c.add(upAmount: 2, inZone: true, time: 5); #expect(!r) }
    }
}
