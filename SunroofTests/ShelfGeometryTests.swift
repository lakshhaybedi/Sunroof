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

    @Test func closeOnSingleLargeScrollUpNearBottom() {
        var c = ScrollCloseTracker()
        do { let r = c.add(upAmount: 8, point: nearBottom, panelFrame: panel, time: 0); #expect(r) }
    }

    @Test func closeIgnoresScrollAwayFromBottom() {
        var c = ScrollCloseTracker()
        do { let r = c.add(upAmount: 8, point: CGPoint(x: 700, y: 700), panelFrame: panel, time: 0); #expect(!r) }
    }

    // Review: slow swipes (1–3 pt per event) must accumulate to a close.
    @Test func closeAccumulatesSmallScrolls() {
        var c = ScrollCloseTracker()
        do { let r = c.add(upAmount: 2, point: nearBottom, panelFrame: panel, time: 0); #expect(!r) }
        do { let r = c.add(upAmount: 2, point: nearBottom, panelFrame: panel, time: 0.05); #expect(!r) }
        do { let r = c.add(upAmount: 2, point: nearBottom, panelFrame: panel, time: 0.1); #expect(r) }
    }

    @Test func closeAccumulatorResetsOnPause() {
        var c = ScrollCloseTracker()
        _ = c.add(upAmount: 4, point: nearBottom, panelFrame: panel, time: 0)
        do { let r = c.add(upAmount: 2, point: nearBottom, panelFrame: panel, time: 5); #expect(!r) }
    }
}
