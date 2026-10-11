import CoreGraphics
import Testing
@testable import ShelfScroll

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

    @Test func closeOnScrollUpNearBottom() {
        let panel = CGRect(x: 0, y: 549, width: 1512, height: 400)
        #expect(ShelfGeometry.shouldCloseOnScroll(point: CGPoint(x: 700, y: 560), panelFrame: panel, upAmount: 8))
        #expect(!ShelfGeometry.shouldCloseOnScroll(point: CGPoint(x: 700, y: 700), panelFrame: panel, upAmount: 8))
        #expect(!ShelfGeometry.shouldCloseOnScroll(point: CGPoint(x: 700, y: 560), panelFrame: panel, upAmount: 2))
    }
}
