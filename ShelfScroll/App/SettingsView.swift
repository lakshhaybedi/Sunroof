import AppKit
import SwiftUI

/// Hosts SettingsView in a plain window (SwiftUI's Settings scene can't be opened reliably from an agent app).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings

    init(settings: AppSettings) { self.settings = settings }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environment(settings)))
            w.title = "ShelfScroll Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    var body: some View { Text("Settings").padding(40) }
}
