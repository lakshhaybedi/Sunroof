import SwiftUI

@main
struct ShelfScrollApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { Text("Settings") }
    }
}
