import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private(set) var shelf: ShelfController!
    private var edgeMonitor: EdgeTriggerMonitor!
    private var statusItem: StatusItemController!
    private(set) var settingsWindow: SettingsWindowController!
    private let onboarding = OnboardingWindowController()
    private let onboardingState = OnboardingState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests use the app as host; don't show windows or install monitors there.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        shelf = ShelfController(settings: settings)
        edgeMonitor = EdgeTriggerMonitor(settings: settings) { [weak self] decision in
            self?.handle(decision)
        }
        edgeMonitor.isSuspended = { [weak self] in self?.shelf.isVisible ?? false }
        shelf.onVisibilityChange = { [weak self] visible in
            self?.edgeMonitor.reset()
            if visible { self?.onboardingState.shelfOpened = true }
        }
        edgeMonitor.start()

        settingsWindow = SettingsWindowController(settings: settings)
        statusItem = StatusItemController(settings: settings,
                                          onToggle: { [weak self] in self?.toggleShelf() },
                                          onOpenSettings: { [weak self] in self?.settingsWindow.show() })

        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.toggleShelf()
        }

        if !settings.hasCompletedOnboarding {
            onboarding.show(pages: OnboardingView.shellPages(state: onboardingState)) { [weak self] in
                self?.settings.hasCompletedOnboarding = true
            }
        } else if settings.openOnLaunch, let screen = Self.screenUnderMouse() {
            shelf.show(on: screen, focus: nil)
        }
    }

    func toggleShelf() {
        guard let screen = Self.screenUnderMouse() else { return }
        shelf.toggle(on: screen)
    }

    private func handle(_ decision: EdgeDecision) {
        switch decision {
        case .none: break
        case let .open(i): if NSScreen.screens.indices.contains(i) { shelf.show(on: NSScreen.screens[i], focus: nil) }
        case let .openFiles(i): if NSScreen.screens.indices.contains(i) { shelf.show(on: NSScreen.screens[i], focus: .files) }
        }
    }

    static func screenUnderMouse() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
    }
}
