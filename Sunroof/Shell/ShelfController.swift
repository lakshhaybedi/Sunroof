import AppKit
import Observation

/// Owns the shelf panel: showing, hiding, vertical resizing and the close gestures.
@MainActor
final class ShelfController {
    private let settings: AppSettings
    private let panel = ShelfPanel()
    private let root = NSView()
    private let columns = NSView()
    /// Shelf body (material + columns) on top; the widgets float in the transparent strip under it, in the same
    /// window (one key window: no dimming when you click a widget, and the glass samples the desktop).
    private let shelfArea = NSView()
    private let tray = NSView()
    private var trayHeight: NSLayoutConstraint!
    static let widgetCell: CGFloat = 158 // 150 pt tile + 8 pt gap
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
        for v in [shelfArea, tray] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        trayHeight = tray.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            shelfArea.topAnchor.constraint(equalTo: root.topAnchor),
            shelfArea.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            shelfArea.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            shelfArea.bottomAnchor.constraint(equalTo: tray.topAnchor),
            tray.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tray.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tray.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            trayHeight,
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

    /// The widget band's content (SwiftUI host), shown in the strip under the shelf.
    func setWidgetBand(_ view: NSView) {
        tray.subviews.forEach { $0.removeFromSuperview() }
        applyTrayBackground()
        view.frame = tray.bounds
        view.autoresizingMask = [.width, .height]
        tray.addSubview(view)
        // The pill above the widgets resizes the shelf (one handle, where people reach for it).
        let grip = ResizeHandleView { [weak self] in self?.resize(by: $0, ended: $1) }
        grip.translatesAutoresizingMaskIntoConstraints = false
        tray.addSubview(grip)
        NSLayoutConstraint.activate([
            grip.topAnchor.constraint(equalTo: tray.topAnchor),
            grip.leadingAnchor.constraint(equalTo: tray.leadingAnchor),
            grip.trailingAnchor.constraint(equalTo: tray.trailingAnchor),
            grip.heightAnchor.constraint(equalToConstant: 12),
        ])
        updateTray()
    }

    /// Rows the widgets fill (reported by the band); the strip is never taller than that.
    var widgetRowsInUse = 4 { didSet { if widgetRowsInUse != oldValue { updateTray() } } }

    /// Behind the widgets: a frosted blur (Liquid Glass style) or a plain solid strip ("Reduce effects").
    private func applyTrayBackground() {
        trayBackground?.removeFromSuperview()
        let bg: NSView
        if settings.material == .glass {
            let frost = NSVisualEffectView()
            frost.material = .fullScreenUI
            frost.blendingMode = .behindWindow
            frost.state = .active
            bg = frost
        } else {
            let solid = SolidBackgroundView()
            solid.tint = settings.shelfTint?.nsColor
            bg = solid
        }
        bg.frame = tray.bounds
        bg.autoresizingMask = [.width, .height]
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 18
        bg.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        tray.addSubview(bg, positioned: .below, relativeTo: nil)
        trayBackground = bg
    }
    private var trayBackground: NSView?

    /// Height of the widget strip (0 when widgets are off).
    private var wantedTrayHeight: CGFloat {
        guard settings.showWidgets, !tray.subviews.isEmpty else { return 0 }
        let rows = min(max(1, min(settings.widgetRows, 4)), max(1, widgetRowsInUse))
        return CGFloat(rows) * Self.widgetCell + 10 // 10 pt grip above; each cell's 8 pt gap is the margin below
    }

    /// The shelf part of the window (the window also holds the widget strip below it).
    private var shelfFrame: CGRect {
        var f = panel.frame
        f.origin.y += trayHeight.constant
        f.size.height -= trayHeight.constant
        return f
    }

    /// The shelf's frame for `height` on the current screen, leaving room for the widgets; plus the window frame.
    private func frames(shelfHeight: CGFloat) -> (shelf: CGRect, window: CGRect)? {
        guard let screen else { return nil }
        let tray = wantedTrayHeight
        let shelf = ShelfGeometry.frame(height: shelfHeight, screenFrame: screen.frame, visibleFrame: screen.visibleFrame, reserve: tray)
        return (shelf, CGRect(x: shelf.minX, y: shelf.minY - tray, width: shelf.width, height: shelf.height + tray))
    }

    /// Re-applies the widget strip after a settings change while the shelf is open.
    private func updateTray() {
        guard isVisible, let f = frames(shelfHeight: shelfFrame.height) else { trayHeight.constant = wantedTrayHeight; return }
        trayHeight.constant = wantedTrayHeight
        panel.setFrame(f.window, display: true)
        panel.invalidateShadow()
    }

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
        trayHeight.constant = wantedTrayHeight
        let final = frames(shelfHeight: saved)!.window
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
        panel.invalidateShadow()
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
        let settings = settings
        let vc = PanelSplitController(descriptors: chosen, displayKey: key, settings: settings) { moved, target in
            let new = movingPanel(moved, onto: target, in: visiblePanels(order: settings.panelOrder, enabled: Set(PanelID.allCases)))
            if new != settings.panelOrder { settings.panelOrder = new } // dropping on itself: no rebuild
        }
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

    /// When a click outside last closed the shelf. The menu bar icon is drawn by the system, so clicking it
    /// arrives as a click outside first; its toggle must not reopen what that same click just closed.
    private var clickedAwayAt: TimeInterval = -.infinity

    func toggle(on screen: NSScreen) {
        if isVisible { hide(); return }
        guard ProcessInfo.processInfo.systemUptime - clickedAwayAt > 0.6 else { return }
        show(on: screen, focus: nil)
    }

    // MARK: - Resizing

    private var resizeStart: CGRect?

    private func resize(by dy: CGFloat?, ended: Bool) {
        guard let screen else { return }
        guard let dy else { resizeStart = shelfFrame; return } // drag began
        let start = resizeStart ?? shelfFrame
        guard let f = frames(shelfHeight: start.height + dy) else { return }
        panel.setFrame(f.window, display: true)
        if ended {
            panel.invalidateShadow()
            settings.setHeight(f.shelf.height, forDisplay: ShelfGeometry.displayKey(screen))
            resizeStart = nil
        }
    }

    // MARK: - Close gestures (installed only while visible)

    private func installMonitors() {
        removeMonitors()
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clickedAwayAt = ProcessInfo.processInfo.systemUptime
                self?.hide()
            }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] e in
            guard let self, let window = e.window, window === self.panel else { return e } // keys in Settings/onboarding aren't ours
            let flags = e.modifierFlags.intersection([.command, .shift, .option, .control])
            if flags == [.command, .shift], e.charactersIgnoringModifiers?.lowercased() == "f" { // ⌘⇧F (any layout)
                MainActor.assumeIsolated { self.onGlobalSearch?() }
                return nil
            }
            guard e.keyCode == 53 else { return e } // Esc
            MainActor.assumeIsolated {
                if self.escapeHandlers.contains(where: { $0() }) {
                    // handled (e.g. search overlay closed)
                } else if window.firstResponder is NSTextView { // end text editing first
                    window.makeFirstResponder(nil)
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
        let inZone = ShelfGeometry.isInCloseZone(NSEvent.mouseLocation, panelFrame: shelfFrame, screenFrame: screen.frame)
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
            glass.tintColor = settings.shelfTint?.nsColor.withAlphaComponent(0.25)
            container = glass
        case .solid:
            let solid = SolidBackgroundView()
            solid.tint = settings.shelfTint?.nsColor
            body.frame = solid.bounds
            body.autoresizingMask = [.width, .height]
            solid.addSubview(body)
            container = solid
        }
        container.frame = shelfArea.bounds
        container.autoresizingMask = [.width, .height]
        shelfArea.addSubview(container)
        materialView = container
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.theme
            _ = settings.material
            _ = settings.shelfTint
            _ = settings.panelOrder
            _ = settings.enabledPanels
            _ = settings.showWidgets
            _ = settings.widgetRows
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyAppearance()
                self.updateTray()
                self.applyMaterial()
                if !self.tray.subviews.isEmpty { self.applyTrayBackground() }
                self.rebuildColumnsIfNeeded()
                self.observeSettings()
            }
        }
    }
}

private final class SolidBackgroundView: NSView {
    var tint: NSColor? { didSet { needsDisplay = true } }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        let base = NSColor.windowBackgroundColor
        layer?.backgroundColor = (tint.flatMap { base.blended(withFraction: 0.15, of: $0) } ?? base).cgColor
    }
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
