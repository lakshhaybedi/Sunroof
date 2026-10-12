import CoreGraphics
import Testing
@testable import Sunroof

@Suite struct EdgeTriggerTests {
    let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let top = CGPoint(x: 700, y: 981)

    func trigger(_ config: EdgeTriggerConfig = .init(scroll: true, hold: nil, wait: nil), screens: [CGRect]? = nil) -> EdgeTrigger {
        EdgeTrigger(config: config, screens: screens ?? [main])
    }

    @Test func scrollAtTopOpens() {
        var t = trigger()
        #expect(t.handle(.scroll(downAmount: 3.5, isMomentum: false, at: top, time: 0)) == .none)
        #expect(t.handle(.scroll(downAmount: 3.5, isMomentum: false, at: top, time: 0)) == .open(screen: 0))
    }

    @Test func scrollAwayFromTopIgnored() {
        var t = trigger()
        #expect(t.handle(.scroll(downAmount: 10, isMomentum: false, at: CGPoint(x: 700, y: 900), time: 0)) == .none)
    }

    @Test func scrollUpResetsAccumulator() {
        var t = trigger()
        #expect(t.handle(.scroll(downAmount: 4, isMomentum: false, at: top, time: 0)) == .none)
        #expect(t.handle(.scroll(downAmount: -1, isMomentum: false, at: top, time: 0)) == .none)
        #expect(t.handle(.scroll(downAmount: 4, isMomentum: false, at: top, time: 0)) == .none)
    }

    @Test func momentumNeverOpens() {
        var t = trigger()
        #expect(t.handle(.scroll(downAmount: 50, isMomentum: true, at: top, time: 0)) == .none)
    }

    @Test func scrollDisabled() {
        var t = trigger(.init(scroll: false, hold: nil, wait: nil))
        #expect(t.handle(.scroll(downAmount: 50, isMomentum: false, at: top, time: 0)) == .none)
    }

    @Test func holdOpensAfterHoldDelay() {
        var t = trigger(.init(scroll: true, hold: .command, wait: nil))
        #expect(t.handle(.modifiers([.option], at: top, mouseButtonDown: false, time: 0)) == .none)
        #expect(t.handle(.modifiers([.command], at: top, mouseButtonDown: false, time: 1)) == .none)
        #expect(t.handle(.modifiers([.command], at: top, mouseButtonDown: false, time: 1.1)) == .none)
        #expect(t.handle(.modifiers([.command], at: top, mouseButtonDown: false, time: 1.2)) == .open(screen: 0))
    }

    @Test func holdWithMouseDownIgnored() {
        var t = trigger(.init(scroll: true, hold: .command, wait: nil))
        #expect(t.handle(.modifiers([.command], at: top, mouseButtonDown: true, time: 0)) == .none)
        #expect(t.handle(.modifiers([.command], at: top, mouseButtonDown: true, time: 1)) == .none)
    }

    // Review: ⌘ pressed, then mouse down within the hold delay (⌘-drag starting) must not open.
    @Test func holdCancelledByMouseDownBeforeDelay() {
        var t = trigger(.init(scroll: true, hold: .command, wait: nil))
        _ = t.handle(.modifiers([.command], at: top, mouseButtonDown: false, time: 0))
        _ = t.handle(.modifiers([.command], at: top, mouseButtonDown: true, time: 0.1))
        #expect(t.handle(.modifiers([.command], at: top, mouseButtonDown: false, time: 0.5)) == .none)
    }

    // Review: after a ⌘-drag ends with ⌘ still held, ⌘ must be released and pressed again.
    @Test func holdRearmsOnlyAfterRelease() {
        var t = trigger(.init(scroll: true, hold: .command, wait: nil))
        _ = t.handle(.modifiers([.command], at: top, mouseButtonDown: true, time: 0))
        #expect(t.handle(.modifiers([.command], at: top, mouseButtonDown: false, time: 1)) == .none)
        #expect(t.handle(.modifiers([.command], at: top, mouseButtonDown: false, time: 2)) == .none)
        _ = t.handle(.modifiers([], at: top, mouseButtonDown: false, time: 3))
        _ = t.handle(.modifiers([.command], at: top, mouseButtonDown: false, time: 4))
        #expect(t.handle(.modifiers([.command], at: top, mouseButtonDown: false, time: 4.2)) == .open(screen: 0))
    }

    // Review: modifier polling must stop when the cursor is parked (wake-up budget).
    @Test func pollModifiersOnlyWhileRecentlyMovedAtEdge() {
        var t = trigger(.init(scroll: true, hold: .command, wait: nil))
        _ = t.handle(.moved(top, time: 10))
        #expect(t.shouldPollModifiers(now: 11))
        #expect(!t.shouldPollModifiers(now: 12.5))
        _ = t.handle(.moved(CGPoint(x: 700, y: 500), time: 13))
        #expect(!t.shouldPollModifiers(now: 13))
        var noHold = trigger()
        _ = noHold.handle(.moved(top, time: 10))
        #expect(!noHold.shouldPollModifiers(now: 10))
    }

    // Review: a partial scroll must not linger and let a later tiny scroll open the shelf.
    @Test func scrollAccumulatorResetsAfterPause() {
        var t = trigger()
        _ = t.handle(.scroll(downAmount: 5, isMomentum: false, at: top, time: 0))
        #expect(t.handle(.scroll(downAmount: 1, isMomentum: false, at: top, time: 5)) == .none)
    }

    @Test func scrollAccumulatorResetsOffEdge() {
        var t = trigger()
        _ = t.handle(.scroll(downAmount: 5, isMomentum: false, at: top, time: 0))
        _ = t.handle(.scroll(downAmount: 5, isMomentum: false, at: CGPoint(x: 700, y: 500), time: 0.1))
        #expect(t.handle(.scroll(downAmount: 1, isMomentum: false, at: top, time: 0.2)) == .none)
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

    // A drag opens the shelf as soon as it reaches the menu bar, before the top edge where Mission Control takes over.
    @Test func dragOpensInMenuBarZone() {
        var t = trigger()
        #expect(t.handle(.drag(CGPoint(x: 700, y: 982 - 20))) == .openFiles(screen: 0))
        var u = trigger()
        #expect(u.handle(.drag(CGPoint(x: 700, y: 982 - 40))) == .none)
    }

    @Test func dragOpensFiles() {
        var t = trigger()
        #expect(t.handle(.drag(top)) == .openFiles(screen: 0))
    }

    @Test func secondScreenIndex() {
        var t = trigger(screens: [main, CGRect(x: 1512, y: 0, width: 1920, height: 1080)])
        let p = CGPoint(x: 2000, y: 1079)
        _ = t.handle(.scroll(downAmount: 3.5, isMomentum: false, at: p, time: 0))
        #expect(t.handle(.scroll(downAmount: 3.5, isMomentum: false, at: p, time: 0)) == .open(screen: 1))
    }

    @Test func stackedDisplayIsNotAnEdge() {
        let t = trigger(screens: [main, CGRect(x: 0, y: 982, width: 1920, height: 1080)])
        #expect(t.edgeScreen(at: top) == nil)
        #expect(t.edgeScreen(at: CGPoint(x: 700, y: 2061)) == 1)
    }
}

@Suite struct ScrollNormalizationTests {
    @Test func trackpadNaturalPullDownIsPositive() {
        #expect(normalizedDownAmount(deltaY: 5, invertedFromDevice: true, precise: true, invert: false) == 5)
    }
    @Test func wheelNotchIsScaledFromLines() {
        #expect(normalizedDownAmount(deltaY: -1, invertedFromDevice: false, precise: false, invert: false) == 10)
    }
    @Test func invertSettingFlips() {
        #expect(normalizedDownAmount(deltaY: 5, invertedFromDevice: true, precise: true, invert: true) == -5)
    }
}
