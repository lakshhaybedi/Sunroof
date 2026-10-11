import AppKit
import Observation

/// Menu bar icon: left click toggles the shelf, right click shows the menu.
@MainActor
final class StatusItemController: NSObject {
    private let settings: AppSettings
    private let onToggle: () -> Void
    private let onOpenSettings: () -> Void
    private var item: NSStatusItem?

    init(settings: AppSettings, onToggle: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.settings = settings
        self.onToggle = onToggle
        self.onOpenSettings = onOpenSettings
        super.init()
        sync()
    }

    private func sync() {
        withObservationTracking {
            if settings.showMenuBarIcon { install() } else { remove() }
        } onChange: { [weak self] in
            Task { @MainActor in self?.sync() }
        }
    }

    private func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "ShelfScroll")
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.item = item
    }

    private func remove() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }

    @objc private func clicked() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            onToggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let pause = NSMenuItem(title: "Pause Clipboard", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = settings.clipboardPaused ? .on : .off
        menu.addItem(pause)
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(NSMenuItem(title: "Quit ShelfScroll", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item?.menu = menu
        item?.button?.performClick(nil) // opens the menu
        item?.menu = nil                // restore click handling
    }

    @objc private func togglePause() { settings.clipboardPaused.toggle() }
    @objc private func openSettings() { onOpenSettings() }
}
