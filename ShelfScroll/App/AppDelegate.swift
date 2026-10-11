import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shelf: ShelfController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let shelf = ShelfController(settings: AppSettings())
        self.shelf = shelf
    }
}
