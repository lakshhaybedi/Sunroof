import Foundation
import Observation

enum Cleanup {
    /// Top-level items whose added AND modified dates are both older than the cutoff. 0 days = off.
    /// For folders, "modified" is the newest modification of anything inside (`newestInside`).
    static func itemsToClean(_ topLevel: [DrawerItem], olderThanDays days: Int, now: Date,
                             newestInside: (URL) -> Date? = { _ in nil }) -> [URL] {
        guard days > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return topLevel.filter { item in
            let modified = item.isDirectory ? max(item.dateModified, newestInside(item.url) ?? .distantPast) : item.dateModified
            return item.dateAdded < cutoff && modified < cutoff
        }.map(\.url)
    }

    /// Newest content modification date anywhere inside `folder` (missing dates count as now). Bounded scan.
    static func newestModification(in folder: URL, limit: Int = 5_000) -> Date? {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var newest: Date?
        var count = 0
        for case let url as URL in e {
            count += 1
            if count > limit { return .now } // ponytail: huge folder — treat as active rather than scan forever
            let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
            newest = max(newest ?? d, d)
        }
        return newest
    }
}

/// Runs auto-cleanup about once a day at a moment macOS picks; always moves to the Trash.
@MainActor
final class CleanupScheduler {
    private let settings: AppSettings
    private let model: DrawerModel
    private let scheduler = NSBackgroundActivityScheduler(identifier: "com.lakshhaybedi.ShelfScroll.cleanup")

    init(settings: AppSettings, model: DrawerModel) {
        self.settings = settings
        self.model = model
    }

    func start() {
        scheduler.interval = 24 * 3600
        scheduler.tolerance = 3600
        scheduler.repeats = true
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                self?.run()
                completion(.finished)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            MainActor.assumeIsolated { self?.run() }
        }
    }

    func run() {
        let root = settings.filesFolder
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(DrawerItem.keys),
                                                                 options: .skipsHiddenFiles)) ?? []
        let doomed = Cleanup.itemsToClean(urls.compactMap(DrawerItem.load), olderThanDays: settings.cleanupDays, now: .now,
                                          newestInside: { Cleanup.newestModification(in: $0) })
        guard !doomed.isEmpty else { return }
        let moved = doomed.filter { (try? FileManager.default.trashItem(at: $0, resultingItemURL: nil)) != nil }.count
        model.reload()
        if moved > 0 { Toast.show("Moved \(moved) old item\(moved == 1 ? "" : "s") to the Trash") }
    }
}
