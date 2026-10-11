import AppKit
import Observation

/// Polls the general pasteboard's changeCount (there is no change notification) and records new clips.
@MainActor
final class ClipboardMonitor {
    private let settings: AppSettings
    private let store: ClipStore
    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount = 0
    private var slow = false
    private var observers: [(NotificationCenter, Any)] = []

    static let interval: TimeInterval = 0.5
    static let slowInterval: TimeInterval = 1.5

    init(settings: AppSettings, store: ClipStore) {
        self.settings = settings
        self.store = store
    }

    func start() {
        lastChangeCount = pasteboard.changeCount // don't record what was already there
        schedule()
        let ws = NSWorkspace.shared.notificationCenter
        let dist = DistributedNotificationCenter.default()
        observe(ws, NSWorkspace.screensDidSleepNotification, slow: true)
        observe(ws, NSWorkspace.screensDidWakeNotification, slow: false)
        observe(dist, .init("com.apple.screenIsLocked"), slow: true)
        observe(dist, .init("com.apple.screenIsUnlocked"), slow: false)
        syncLimit()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, slow: Bool) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.slow = slow
                self?.schedule()
            }
        }
        observers.append((center, token))
    }

    private func schedule() {
        timer?.invalidate()
        let t = Timer(timeInterval: slow ? Self.slowInterval : Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard !settings.clipboardPaused else { return }
        let app = NSWorkspace.shared.frontmostApplication
        let source = ClipSource(bundleID: app?.bundleIdentifier, name: app?.localizedName)
        if let clip = ClipReader.read(pasteboard, source: source, imagesDir: store.historyImagesDir,
                                      sensitiveApps: settings.sensitiveApps) {
            store.ingest(clip)
        }
    }

    private func syncLimit() {
        withObservationTracking {
            store.limit = settings.historyLimit
            store.useFavoritesFolder(settings.favoritesFolder)
        } onChange: { [weak self] in
            Task { @MainActor in self?.syncLimit() }
        }
    }
}
