import AppKit
import Observation
import SwiftUI

/// Notes floating above other windows. Frames persist; closing a sticky never deletes its note.
@MainActor
final class StickyManager: NSObject, NSWindowDelegate {
    private let store: NoteStore
    private let settings: AppSettings
    private var panels: [String: NSPanel] = [:] // filename → panel
    private var models: [ObjectIdentifier: StickyModel] = [:] // panel → which note it shows
    static let defaultSize = NSSize(width: 280, height: 320)

    init(store: NoteStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        super.init()
        store.onRename.append { [weak self] old, new in self?.rename(old, to: new) }
        store.onDelete.append { [weak self] name in self?.close(name) }
    }

    func open(_ filename: String) {
        if let p = panels[filename] { p.orderFrontRegardless(); return }
        guard store.note(filename) != nil else { return }
        let frame = settings.stickies[filename].map(NSRectFromString).flatMap { $0.isEmpty ? nil : $0 }
            ?? NSRect(origin: defaultOrigin(), size: Self.defaultSize)
        let panel = NSPanel(contentRect: frame, styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self
        panel.setFrame(frame, display: false)
        panels[filename] = panel
        let model = StickyModel(filename: filename)
        models[ObjectIdentifier(panel)] = model
        panel.title = store.note(filename)?.title ?? filename
        panel.contentView = NSHostingView(rootView: StickyContent(model: model, store: store, settings: settings))
        panel.orderFrontRegardless()
        remember(panel)
    }

    /// Reopens stickies from the last session; drops entries whose note no longer exists.
    func restore() {
        for name in settings.stickies.keys.sorted() {
            if store.note(name) != nil { open(name) } else { settings.stickies[name] = nil }
        }
    }

    private func rename(_ old: String, to new: String) {
        guard let panel = panels.removeValue(forKey: old) else { return }
        panels[new] = panel
        settings.stickies[new] = settings.stickies.removeValue(forKey: old)
        models[ObjectIdentifier(panel)]?.filename = new // the editor switches files without reloading
        panel.title = store.note(new)?.title ?? new
    }

    private func close(_ filename: String) {
        guard let panel = panels[filename] else { return }
        panel.close() // windowWillClose cleans up
    }

    private func name(of window: NSWindow) -> String? { panels.first { $0.value === window }?.key }

    private func remember(_ window: NSWindow) {
        if let name = name(of: window) { settings.stickies[name] = NSStringFromRect(window.frame) }
    }

    private func defaultOrigin() -> NSPoint {
        let v = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let offset = CGFloat(panels.count) * 24
        return NSPoint(x: v.maxX - Self.defaultSize.width - 40 - offset, y: v.maxY - Self.defaultSize.height - 40 - offset)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) { (notification.object as? NSWindow).map(remember) }
    func windowDidResize(_ notification: Notification) { (notification.object as? NSWindow).map(remember) }

    func windowDidResignKey(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, let name = name(of: w) else { return }
        _ = store.finishEditing(name) // saves; a title change renames (and re-keys via onRename)
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, let name = name(of: w) else { return }
        panels[name] = nil
        models[ObjectIdentifier(w)] = nil
        settings.stickies[name] = nil
        if store.note(name) != nil { _ = store.finishEditing(name) }
    }
}

@MainActor @Observable
final class StickyModel {
    var filename: String
    init(filename: String) { self.filename = filename }
}

private struct StickyContent: View {
    let model: StickyModel
    let store: NoteStore
    let settings: AppSettings

    var body: some View {
        NoteEditor(store: store, filename: model.filename, fontSize: settings.noteFontSize,
                   noteFont: settings.noteFont, accent: settings.accent.nsColor)
            .frame(minWidth: 180, minHeight: 120)
    }
}
