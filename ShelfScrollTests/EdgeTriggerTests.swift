import CoreGraphics
import Testing
@testable import ShelfScroll

@Suite struct EdgeTriggerTests {
    let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let top = CGPoint(x: 700, y: 981)

    func trigger(_ config: EdgeTriggerConfig = .init(scroll: true, hold: nil, wait: nil), screens: [CGRect]? = nil) -> EdgeTrigger {
        EdgeTrigger(config: config, screens: screens ?? [main])
    }

    @Test func scrollAtTopOpens() {
        var t = trigger()
        #expect(t.handle(.scroll(downAmount: 3.5, isMomentum: false, at: top)) == .none)
        #expect(t.handle(.scroll(downAmount: 3.5, isMomentum: false, at: top)) == .open(screen: 0))
    }

    @Test func scrollAwayFromTopIgnored() {
        var t = trigger()
        #expect(t.handle(.scroll(downAmount: 10, isMomentum: false, at: CGPoint(x: 700, y: 900))) == .none)
    }

    @Test func scrollUpResetsAccumulator() {
        var t = trigger()
        #expect(t.handle(.scroll(downAmount: 4, isMomentum: false, at: top)) == .none)
        #expect(t.handle(.scroll(downAmount: -1, isMomentum: false, at: top)) == .none)
        #expect(t.handle(.scroll(downAmount: 4, isMomentum: false, at: top)) == .none)
    }

    @Test func momentumNeverOpens() {
        var t = trigger()
        #expect(t.handle(.scroll(downAmount: 50, isMomentum: true, at: top)) == .none)
    }

    @Test func scrollDisabled() {
        var t = trigger(.init(scroll: false, hold: nil, wait: nil))
        #expect(t.handle(.scroll(downAmount: 50, isMomentum: false, at: top)) == .none)
    }

    @Test func holdOpens() {
        var t = trigger(.init(scroll: true, hold: .command, wait: nil))
        #expect(t.handle(.modifiers([.option], at: top, mouseButtonDown: false)) == .none)
        #expect(t.handle(.modifiers([.command], at: top, mouseButtonDown: false)) == .open(screen: 0))
    }

    @Test func holdWithMouseDownIgnored() {
        var t = trigger(.init(scroll: true, hold: .command, wait: nil))
        #expect(t.handle(.modifiers([.command], at: top, mouseButtonDown: true)) == .none)
    }

    @Test func waitOpensAfterDelay() {
        var t = trigger(.init(scroll: true, hold: nil, wait: 0.5))
        #expect(t.handle(.moved(top, time: 10)) == .none)
        #expect(t.waitDeadline == 10.5)
        #expect(t.handle(.tick(10.4)) == .none)
        #expect(t.handle(.tick(10.5)) == .open(screen: 0))
    }

    @Test func waitCancelledOnLeave() {
        var t = trigger(.init(scroll: true, hold: nil, wait: 0.5))
        _ = t.handle(.moved(top, time: 10))
        _ = t.handle(.moved(CGPoint(x: 700, y: 500), time: 10.2))
        #expect(t.waitDeadline == nil)
        #expect(t.handle(.tick(10.6)) == .none)
    }

    @Test func dragOpensFiles() {
        var t = trigger()
        #expect(t.handle(.drag(top)) == .openFiles(screen: 0))
    }

    @Test func secondScreenIndex() {
        var t = trigger(screens: [main, CGRect(x: 1512, y: 0, width: 1920, height: 1080)])
        let p = CGPoint(x: 2000, y: 1079)
        _ = t.handle(.scroll(downAmount: 3.5, isMomentum: false, at: p))
        #expect(t.handle(.scroll(downAmount: 3.5, isMomentum: false, at: p)) == .open(screen: 1))
    }

    @Test func stackedDisplayIsNotAnEdge() {
        let t = trigger(screens: [main, CGRect(x: 0, y: 982, width: 1920, height: 1080)])
        #expect(t.edgeScreen(at: top) == nil)
        #expect(t.edgeScreen(at: CGPoint(x: 700, y: 2061)) == 1)
    }
}
