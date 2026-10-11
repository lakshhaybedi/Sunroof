import AppKit
import Observation

/// Owns the shelf panel: showing, hiding, vertical resizing and the close gestures.
@MainActor
final class ShelfController {
    private let settings: AppSettings
    private let panel = ShelfPanel()
    private let root = NSView()
    private let columns = NSView()
    private var materialView: NSView?
    private var monitors: [Any] = []
    private var screen: NSScreen?
    private var hideGeneration = 0
    private var closeTracker = ScrollCloseTracker()
    private var split: PanelSplitController?
    var descriptors: [PanelDescriptor] = PanelDescriptor.placeholders

    var onVisibilityChange: ((Bool) -> Void)?
    /// Called when hiding starts (e.g. purge caches).
    var onHide: [() -> Void] = []
    /// Called after the panel is shown and key.
    var onShow: [() -> Void] = []
    /// ⌘⇧F inside the shelf.
    var onGlobalSearch: (() -> Void)?
    /// Asked in order on Esc; the first that returns true consumes it (e.g. closing the search overlay).
    var escapeHandlers: [() -> Bool] = []
    private var overlay: NSView?
    var overlayView: NSView? { overlay }
    /// The column `show` was asked to focus (nil = default).
    private(set) var requestedFocus: PanelID?
    /// Frontmost app when the shelf opened — the paste target.
    private(set) var previousApp: NSRunningApplication?
    var isVisible: Bool { panel.isVisible && hideGeneration == 0 }
    var visibleFrame: CGRect? { isVisible ? panel.frame : nil }
    var displayKey: String? { screen.map(ShelfGeometry.displayKey) }

    init(settings: AppSettings) {
        self.settings = settings
        panel.contentView = root
        columns.translatesAutoresizingMaskIntoConstraints = false
        let handle = ResizeHandleView { [weak self] in self?.resize(by: $0, ended: $1) }
        handle.translatesAutoresizingMaskIntoConstraints = false
        applyAppearance()
        let body = NSView()
        body.addSubview(columns)
        body.addSubview(handle)
        NSLayoutConstraint.activate([
            columns.topAnchor.constraint(equalTo: body.topAnchor),
            columns.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            columns.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            columns.bottomAnchor.constraint(equalTo: handle.topAnchor),
            handle.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            handle.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            handle.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            handle.heightAnchor.constraint(equalToConstant: 8),
        ])
        self.body = body
        applyMaterial()
        observeSettings()
    }

    private var body: NSView!

    /// A view pinned over the top of the columns (the search overlay); nil removes it.
    func setOverlay(_ view: NSView?) {
        overlay?.removeFromSuperview()
        overlay = view
        guard let view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: body.topAnchor, constant: 32),
            view.centerXAnchor.constraint(equalTo: body.centerXAnchor),
            view.widthAnchor.constraint(lessThanOrEqualTo: body.widthAnchor),
            view.bottomAnchor.constraint(lessThanOrEqualTo: body.bottomAnchor),
        ])
    }

    /// Replace the column content (Task 5's split view).
    func setColumns(_ view: NSView) {
        columns.subviews.forEach { $0.removeFromSuperview() }
        view.frame = columns.bounds
        view.autoresizingMask = [.width, .height]
        columns.addSubview(view)
    }

    func show(on screen: NSScreen, focus: PanelID?) {
        hideGeneration = 0
        self.screen = screen
        requestedFocus = focus
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        rebuildColumnsIfNeeded()
        let saved = settings.height(forDisplay: ShelfGeometry.displayKey(screen))
            ?? screen.visibleFrame.height * ShelfGeometry.defaultFraction
        let final = ShelfGeometry.frame(height: saved, screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let start = reduceMotion ? final : final.offsetBy(dx: 0, dy: final.height)
        panel.setFrame(start, display: false)
        panel.alphaValue = reduceMotion ? 0 : 1
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if reduceMotion { panel.animator().alphaValue = 1 } else { panel.animator().setFrame(final, display: true) }
        }
        installMonitors()
        if let focus { split?.focus(focus) }
        onVisibilityChange?(true)
        onShow.forEach { $0() }
    }

    private func rebuildColumnsIfNeeded(force: Bool = false) {
        guard let key = displayKey else { return }
        let ids = visiblePanels(order: settings.panelOrder, enabled: settings.enabledPanels)
        let name = "ShelfSplit-\(key)-\(ids.map(\.rawValue).joined(separator: "-"))"
        guard force || split?.splitView.autosaveName != name else { return }
        let chosen = ids.compactMap { id in descriptors.first { $0.id == id } }
        let vc = PanelSplitController(descriptors: chosen, displayKey: key)
        split = vc
        setColumns(vc.view)
    }

    /// `completion` runs once the panel is off screen and has given up keyboard focus.
    func hide(completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard panel.isVisible, hideGeneration == 0 else { completion?(); return }
        removeMonitors()
        hideGeneration += 1
        let generation = hideGeneration
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let frame = panel.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if reduceMotion { panel.animator().alphaValue = 0 }
            else { panel.animator().setFrame(frame.offsetBy(dx: 0, dy: frame.height), display: true) }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideGeneration == generation else { completion?(); return }
                self.panel.orderOut(nil)
                self.hideGeneration = 0
                completion?()
            }
        })
        onVisibilityChange?(false)
        onHide.forEach { $0() }
    }

    func toggle(on screen: NSScreen) {
        isVisible ? hide() : show(on: screen, focus: nil)
    }

    // MARK: - Resizing

    private var resizeStart: CGRect?

    private func resize(by dy: CGFloat?, ended: Bool) {
        guard let screen else { return }
        guard let dy else { resizeStart = panel.frame; return } // drag began
        let start = resizeStart ?? panel.frame
        let f = ShelfGeometry.frame(height: start.height + dy, screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
        panel.setFrame(f, display: true)
        if ended {
            settings.setHeight(f.height, forDisplay: ShelfGeometry.displayKey(screen))
            resizeStart = nil
        }
    }

    // MARK: - Close gestures (installed only while visible)

    private func installMonitors() {
        removeMonitors()
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] e in
            guard let self, e.window === self.panel else { return e } // keys in Settings/onboarding aren't ours
            let flags = e.modifierFlags.intersection([.command, .shift, .option, .control])
            if flags == [.command, .shift], e.charactersIgnoringModifiers?.lowercased() == "f" { // ⌘⇧F (any layout)
                MainActor.assumeIsolated { self.onGlobalSearch?() }
                return nil
            }
            guard e.keyCode == 53 else { return e } // Esc
            MainActor.assumeIsolated {
                if self.escapeHandlers.contains(where: { $0() }) {
                    // handled (e.g. search overlay closed)
                } else if self.panel.firstResponder is NSTextView { // end text editing first
                    self.panel.makeFirstResponder(nil)
                } else {
                    self.hide()
                }
            }
            return nil
        }) { monitors.append(m) }
        // Scroll up closes: in the menu bar strip (a global event — not our window) or at the shelf's edges (local).
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] e in
            MainActor.assumeIsolated { self?.scrollToClose(e) }
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] e in
            MainActor.assumeIsolated { self?.scrollToClose(e) }
        }) { monitors.append(m) }
    }

    private func scrollToClose(_ e: NSEvent) {
        guard e.momentumPhase == [], let screen else { return }
        let up = -normalizedDownAmount(e, invert: settings.invertScroll)
        let inZone = ShelfGeometry.isInCloseZone(NSEvent.mouseLocation, panelFrame: panel.frame, screenFrame: screen.frame)
        if closeTracker.add(upAmount: up, inZone: inZone, time: ProcessInfo.processInfo.systemUptime) { hide() }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    // MARK: - Appearance

    private func applyAppearance() {
        switch settings.theme {
        case .auto: panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func applyMaterial() {
        body.removeFromSuperview()
        materialView?.removeFromSuperview()
        let container: NSView
        switch settings.material {
        case .glass:
            let glass = NSGlassEffectView()
            glass.contentView = body
            container = glass
        case .solid:
            let solid = SolidBackgroundView()
            body.frame = solid.bounds
            body.autoresizingMask = [.width, .height]
            solid.addSubview(body)
            container = solid
        }
        container.frame = root.bounds
        container.autoresizingMask = [.width, .height]
        root.addSubview(container)
        materialView = container
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.theme
            _ = settings.material
            _ = settings.panelOrder
            _ = settings.enabledPanels
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyAppearance()
                self.applyMaterial()
                self.rebuildColumnsIfNeeded()
                self.observeSettings()
            }
        }
    }
}

private final class SolidBackgroundView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
}

/// 8 pt strip at the bottom of the shelf; drag to change the shelf height.
/// Reports (nil, false) on mouse down, then (dy, ended) where dy > 0 means taller.
private final class ResizeHandleView: NSView {
    private let onDrag: (CGFloat?, Bool) -> Void
    private var startY: CGFloat = 0

    init(onDrag: @escaping (CGFloat?, Bool) -> Void) {
        self.onDrag = onDrag
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }

    override func mouseDown(with event: NSEvent) {
        startY = NSEvent.mouseLocation.y
        onDrag(nil, false)
    }

    override func mouseDragged(with event: NSEvent) { onDrag(startY - NSEvent.mouseLocation.y, false) }
    override func mouseUp(with event: NSEvent) { onDrag(startY - NSEvent.mouseLocation.y, true) }
}
