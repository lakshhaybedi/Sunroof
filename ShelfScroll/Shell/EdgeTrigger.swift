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
    case scroll(downAmount: CGFloat, isMomentum: Bool, at: CGPoint)
    case modifiers(Set<ModifierKey>, at: CGPoint, mouseButtonDown: Bool)
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

    var config: EdgeTriggerConfig
    var screens: [CGRect] // Cocoa global coordinates (origin bottom-left)
    private(set) var waitDeadline: TimeInterval?
    private var scrollAccumulator: CGFloat = 0
    private var lastPoint: CGPoint?

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

        case let .scroll(amount, isMomentum, p):
            lastPoint = p
            guard config.scroll, !isMomentum, let i = edgeScreen(at: p) else { return .none }
            guard amount > 0 else { scrollAccumulator = 0; return .none }
            scrollAccumulator += amount
            guard scrollAccumulator >= Self.scrollThreshold else { return .none }
            reset()
            return .open(screen: i)

        case let .modifiers(mods, p, mouseButtonDown):
            lastPoint = p
            guard let hold = config.hold, mods.contains(hold), !mouseButtonDown,
                  let i = edgeScreen(at: p) else { return .none }
            reset()
            return .open(screen: i)

        case let .drag(p):
            lastPoint = p
            guard let i = edgeScreen(at: p) else { return .none }
            reset()
            return .openFiles(screen: i)
        }
    }

    mutating func reset() {
        waitDeadline = nil
        scrollAccumulator = 0
    }
}
