import Foundation
import Observation

enum ScreenshotCatcher {
    private static let xattrName = "com.apple.metadata:kMDItemIsScreenCapture"

    /// Where macOS saves screenshots (Screenshot app ▸ Options ▸ Save to), default ~/Desktop.
    static func screenshotFolder() -> URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    static func isScreenshot(_ url: URL) -> Bool {
        !url.lastPathComponent.hasPrefix(".") && getxattr(url.path, xattrName, nil, 0, 0, 0) >= 0
    }

    /// Moves screenshots created since `since` from `source` into `drawer/Screenshots`, with unique names.
    static func collect(from source: URL, into drawer: URL, since: Date) -> [URL] {
        let fm = FileManager.default
        let dest = drawer.appendingPathComponent("Screenshots")
        // Screenshots already saved straight into the drawer stay put (moving them would loop forever).
        guard comparablePath(source) != comparablePath(dest) else { return [] }
        let urls = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let shots = urls.filter { url in
            guard isScreenshot(url), let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
            else { return false }
            return created >= since
        }
        guard !shots.isEmpty else { return [] }
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        return shots.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            let target = uniqueDestination(for: url.lastPathComponent, in: dest)
            return (try? fm.moveItem(at: url, to: target)) != nil ? target : nil
        }
    }
}

/// Watches the screenshot folder while "Catch Screenshots" is on.
@MainActor
final class ScreenshotWatcher {
    private let settings: AppSettings
    private var watcher: FolderWatcher?

    init(settings: AppSettings) { self.settings = settings }

    func start() {
        withObservationTracking {
            sync(enabled: settings.catchScreenshots)
        } onChange: { [weak self] in
            Task { @MainActor in self?.start() }
        }
    }

    private func sync(enabled: Bool) {
        guard enabled else { watcher = nil; return }
        guard watcher == nil else { return }
        let since = Date.now
        let folder = ScreenshotCatcher.screenshotFolder()
        watcher = FolderWatcher(url: folder) { [weak self] in
            guard let self else { return }
            let drawer = self.settings.filesFolder
            // Don't recreate an offline custom folder (it would hide "Folder not found").
            guard self.settings.isDefaultFilesFolder || FileManager.default.fileExists(atPath: drawer.path) else { return }
            _ = ScreenshotCatcher.collect(from: folder, into: drawer, since: since)
        }
    }
}
