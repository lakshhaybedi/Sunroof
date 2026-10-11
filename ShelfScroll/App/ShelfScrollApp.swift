import SwiftUI

@main
struct ShelfScrollApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings live in SettingsWindowController; an App needs at least one scene.
        Settings { EmptyView() }
    }
}
