import AppKit
import Observation

/// Converts a scroll event into "pull down" amount (> 0 = fingers/wheel pulling content down).
func normalizedDownAmount(_ event: NSEvent, invert: Bool) -> CGFloat {
    let d = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
    return invert ? -d : d
}

extension ModifierKey {
    static func set(from flags: NSEvent.ModifierFlags) -> Set<ModifierKey> {
        var s = Set<ModifierKey>()
        if flags.contains(.command) { s.insert(.command) }
        if flags.contains(.option) { s.insert(.option) }
        if flags.contains(.control) { s.insert(.control) }
        if flags.contains(.shift) { s.insert(.shift) }
        return s
    }
}

/// Feeds real NSEvents into `EdgeTrigger`. Installs only the monitors the enabled triggers need.
@MainActor
final class EdgeTriggerMonitor {
    private let settings: AppSettings
    private let onDecision: (EdgeDecision) -> Void
    private var trigger: EdgeTrigger
    private var monitors: [Any] = []
    private var waitItem: DispatchWorkItem?
    private var holdTimer: Timer?
    private var dragPasteboardCount = 0
    private var screenObserver: Any?

    /// Decisions are dropped while this returns true (e.g. shelf already open).
    var isSuspended: () -> Bool = { false }

    init(settings: AppSettings, onDecision: @escaping (EdgeDecision) -> Void) {
        self.settings = settings
        self.onDecision = onDecision
        trigger = EdgeTrigger(config: settings.edgeConfig, screens: NSScreen.screens.map(\.frame))
    }

    func start() {
        install()
        observeConfig()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.trigger.screens = NSScreen.screens.map(\.frame) }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        stopHoldTimer()
        waitItem?.cancel()
    }

    func reset() {
        trigger.reset()
        waitItem?.cancel()
        stopHoldTimer()
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func install() {
        stop()
        let config = settings.edgeConfig
        trigger.config = config
        if config.scroll { add(.scrollWheel) { [weak self] e in
            guard let self else { return }
            self.feed(.scroll(downAmount: normalizedDownAmount(e, invert: self.settings.invertScroll),
                              isMomentum: e.momentumPhase != [], at: NSEvent.mouseLocation))
        } }
        if config.hold != nil || config.wait != nil { add(.mouseMoved) { [weak self] _ in
            self?.mouseMoved()
        } }
        add(.leftMouseDown) { [weak self] _ in
            self?.dragPasteboardCount = NSPasteboard(name: .drag).changeCount
        }
        add(.leftMouseDragged) { [weak self] _ in
            guard let self, NSPasteboard(name: .drag).changeCount != self.dragPasteboardCount else { return }
            self.feed(.drag(NSEvent.mouseLocation)) // only real drag-and-drop sessions, not window drags
        }
    }

    private func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping @MainActor (NSEvent) -> Void) {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { e in
            MainActor.assumeIsolated { handler(e) }
        }) { monitors.append(m) }
    }

    private func mouseMoved() {
        let p = NSEvent.mouseLocation
        feed(.moved(p, time: now))
        scheduleWait()
        // Global flagsChanged needs Accessibility, so poll modifiers only while parked at the edge.
        if trigger.config.hold != nil, trigger.edgeScreen(at: p) != nil {
            if holdTimer == nil {
                let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.checkHold() }
                }
                t.tolerance = 0.05
                RunLoop.main.add(t, forMode: .common)
                holdTimer = t
            }
        } else {
            stopHoldTimer()
        }
    }

    private func checkHold() {
        let p = NSEvent.mouseLocation
        guard trigger.edgeScreen(at: p) != nil else { stopHoldTimer(); return }
        feed(.modifiers(ModifierKey.set(from: NSEvent.modifierFlags), at: p,
                        mouseButtonDown: NSEvent.pressedMouseButtons != 0))
    }

    private func stopHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func scheduleWait() {
        waitItem?.cancel()
        guard let deadline = trigger.waitDeadline else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.feed(.tick(self.now))
            }
        }
        waitItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - now), execute: item)
    }

    private func feed(_ input: EdgeInput) {
        guard !isSuspended() else { return }
        let decision = trigger.handle(input)
        guard decision != .none else { return }
        reset()
        onDecision(decision)
    }

    private func observeConfig() {
        withObservationTracking { _ = settings.edgeConfig } onChange: { [weak self] in
            Task { @MainActor in
                self?.install()
                self?.observeConfig()
            }
        }
    }
}
