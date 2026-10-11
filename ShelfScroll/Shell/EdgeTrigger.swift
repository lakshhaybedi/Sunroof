import CoreGraphics
import Foundation

struct EdgeTriggerConfig: Equatable {
    var scroll: Bool
    var hold: ModifierKey?
    var wait: TimeInterval?
}

enum EdgeInput {
    case moved(CGPoint, time: TimeInterval)
    /// `downAmount` > 0 means "pull down", already normalized for device direction.
    case scroll(downAmount: CGFloat, isMomentum: Bool, at: CGPoint, time: TimeInterval)
    case modifiers(Set<ModifierKey>, at: CGPoint, mouseButtonDown: Bool, time: TimeInterval)
    case drag(CGPoint)
    case tick(TimeInterval)
}

enum EdgeDecision: Equatable {
    case none
    case open(screen: Int)
    case openFiles(screen: Int)
}

/// Decides when the cursor at a screen's top edge should open the shelf.
/// Pure value type; `EdgeTriggerMonitor` feeds it real events.
struct EdgeTrigger {
    static let edgeTolerance: CGFloat = 2
    static let scrollThreshold: CGFloat = 6 // ponytail: calibration knob — tune on real trackpads/mice
    static let scrollGap: TimeInterval = 0.3   // pause that starts a new scroll gesture
    static let holdDelay: TimeInterval = 0.2   // modifier must be held this long with no mouse button
    static let pollWindow: TimeInterval = 2    // stop polling modifiers this long after the last move

    var config: EdgeTriggerConfig
    var screens: [CGRect] // Cocoa global coordinates (origin bottom-left)
    private(set) var waitDeadline: TimeInterval?
    private var scrollAccumulator: CGFloat = 0
    private var lastPoint: CGPoint?
    private var lastScrollTime: TimeInterval = -.infinity
    private var lastMoveTime: TimeInterval = -.infinity
    private var holdStart: TimeInterval?
    private var holdDisarmed = false

    init(config: EdgeTriggerConfig, screens: [CGRect]) {
        self.config = config
        self.screens = screens
    }

    /// Index of the screen whose top edge `p` is on, or nil. A top edge covered by
    /// another display stacked above it is not an edge — the cursor passes through.
    func edgeScreen(at p: CGPoint) -> Int? {
        guard let i = screens.firstIndex(where: {
            p.x >= $0.minX && p.x < $0.maxX && p.y >= $0.maxY - Self.edgeTolerance && p.y <= $0.maxY + 1
        }) else { return nil }
        let above = CGPoint(x: p.x, y: screens[i].maxY + 1)
        return screens.contains { $0.contains(above) } ? nil : i
    }

    mutating func handle(_ input: EdgeInput) -> EdgeDecision {
        switch input {
        case let .moved(p, time):
            let wasAtEdge = lastPoint.flatMap(edgeScreen) != nil
            lastPoint = p
            lastMoveTime = time
            if edgeScreen(at: p) == nil {
                reset()
            } else if !wasAtEdge, let wait = config.wait {
                waitDeadline = time + wait
            }
            return .none

        case let .tick(now):
            guard let deadline = waitDeadline, now >= deadline,
                  let p = lastPoint, let i = edgeScreen(at: p) else { return .none }
            reset()
            return .open(screen: i)

        case let .scroll(amount, isMomentum, p, time):
            lastPoint = p
            defer { lastScrollTime = time }
            guard config.scroll, !isMomentum else { return .none }
            guard let i = edgeScreen(at: p), amount > 0 else { scrollAccumulator = 0; return .none }
            if time - lastScrollTime > Self.scrollGap { scrollAccumulator = 0 }
            scrollAccumulator += amount
            guard scrollAccumulator >= Self.scrollThreshold else { return .none }
            reset()
            return .open(screen: i)

        case let .modifiers(mods, p, mouseButtonDown, time):
            lastPoint = p
            guard let hold = config.hold, let i = edgeScreen(at: p), mods.contains(hold) else {
                holdStart = nil
                holdDisarmed = false // released (or left the edge): re-arm
                return .none
            }
            // A mouse button while holding means ⌘-drag etc.: ignore until the key is released.
            if mouseButtonDown { holdDisarmed = true; holdStart = nil }
            guard !holdDisarmed else { return .none }
            let start = holdStart ?? time
            holdStart = start
            guard time - start >= Self.holdDelay - 1e-9 else { return .none }
            reset()
            return .open(screen: i)

        case let .drag(p):
            lastPoint = p
            guard let i = edgeScreen(at: p) else { return .none }
            reset()
            return .openFiles(screen: i)
        }
    }

    /// Whether the monitor should poll modifier keys: Hold enabled, cursor at an edge, moved recently.
    func shouldPollModifiers(now: TimeInterval) -> Bool {
        config.hold != nil && lastPoint.flatMap(edgeScreen) != nil && now - lastMoveTime <= Self.pollWindow
    }

    mutating func reset() {
        waitDeadline = nil
        scrollAccumulator = 0
        holdStart = nil
    }
}
