import Foundation
import Observation

/// The drawer folder: what's in the current folder, navigation, and every file operation.
@MainActor @Observable
final class DrawerModel {
    private(set) var root: URL
    private(set) var isDefaultRoot: Bool
    private(set) var current: URL
    private(set) var items: [DrawerItem] = []
    private(set) var rootMissing = false
    var arrangeBy: ArrangeBy = .kind { didSet { items = sortItems(items, by: arrangeBy, foldersOnTop: foldersOnTop) } }
    var foldersOnTop = true { didSet { items = sortItems(items, by: arrangeBy, foldersOnTop: foldersOnTop) } }
    var query = "" { didSet { if query != oldValue { query.isEmpty ? reload() : scheduleSearch() } } }
    private(set) var downloads: [UUID: String] = [:] // id → file name being downloaded

    @ObservationIgnored private let trashItem: (URL) throws -> Void
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    nonisolated static let maxSearchResults = 500

    init(root: URL, isDefaultRoot: Bool,
         trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.root = canonical(root)
        self.isDefaultRoot = isDefaultRoot
        self.current = canonical(root)
        self.trashItem = trash
        reload()
    }

    /// Points the drawer at a new folder. (A method, not a didSet: re-assigning inside didSet recurses under @Observable.)
    func changeRoot(_ url: URL, isDefault: Bool) {
        root = canonical(url)
        isDefaultRoot = isDefault
        current = root
        watcher = nil
        reload()
    }

    /// root … current, built from path components so URLs compare equal (no trailing-slash variants).
    var breadcrumbs: [URL] {
        let rootParts = root.standardizedFileURL.pathComponents
        let parts = current.standardizedFileURL.pathComponents
        guard parts.starts(with: rootParts) else { return [root] }
        var url = root
        return [root] + parts.dropFirst(rootParts.count).map { url = url.appendingPathComponent($0); return url }
    }

    func open(_ folder: URL) {
        current = canonical(folder)
        reload()
    }

    func goUp() {
        let crumbs = breadcrumbs
        guard crumbs.count > 1 else { return }
        open(crumbs[crumbs.count - 2])
    }

    func reload() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: root.path) {
            watcher = nil // it may be following the old folder into the Trash
            if isDefaultRoot { try? fm.createDirectory(at: root, withIntermediateDirectories: true) }
        }
        guard fm.fileExists(atPath: root.path) else {
            rootMissing = true
            items = []
            return
        }
        rootMissing = false
        if !fm.fileExists(atPath: current.path) { current = root }
        if !query.isEmpty { scheduleSearch(); return }
        items = sortItems(list(current).compactMap(DrawerItem.load), by: arrangeBy, foldersOnTop: foldersOnTop)
        if watcher?.url.path != current.path {
            watcher = FolderWatcher(url: current) { [weak self] in self?.reload() }
        }
    }

    // MARK: - Operations

    @discardableResult func newFolder() throws -> URL {
        let url = canonical(uniqueDestination(for: "untitled folder", in: current))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        reload()
        return url
    }

    @discardableResult func rename(_ item: DrawerItem, to name: String) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name, !trimmed.contains("/") else { return item.url }
        let parent = item.url.deletingLastPathComponent()
        // Case-only rename on a case-insensitive volume: the "clash" is the item itself.
        let dest = canonical(trimmed.lowercased() == item.name.lowercased()
            ? parent.appendingPathComponent(trimmed) : uniqueDestination(for: trimmed, in: parent))
        try FileManager.default.moveItem(at: item.url, to: dest)
        reload()
        return dest
    }

    func trash(_ urls: [URL]) throws {
        defer { reload() }
        for url in urls { try trashItem(url) }
    }

    @discardableResult func drop(_ urls: [URL], operation: FileDropOperation) throws -> [URL] {
        defer { reload() }
        return try urls.map { try perform(operation, $0, into: current) }
    }

    func download(_ remote: URL) {
        let id = UUID()
        downloads[id] = remote.lastPathComponent
        let dir = current
        Task {
            defer { downloads[id] = nil }
            guard let (temp, response) = try? await URLSession.shared.download(from: remote) else { return }
            let name = response.suggestedFilename ?? remote.lastPathComponent
            try? FileManager.default.moveItem(at: temp, to: uniqueDestination(for: name, in: dir))
            reload()
        }
    }

    // MARK: - Listing

    private func list(_ dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(DrawerItem.keys),
                                                      options: .skipsHiddenFiles)) ?? []
    }

    /// Debounced, off-main recursive search; stale results are dropped.
    private func scheduleSearch() {
        searchTask?.cancel()
        let (q, top) = (query, root)
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let urls = await Task.detached(priority: .userInitiated) { Self.search(q, in: top) }.value
            guard let self, !Task.isCancelled, self.query == q else { return }
            self.items = sortItems(urls.compactMap(DrawerItem.load), by: self.arrangeBy, foldersOnTop: self.foldersOnTop)
        }
    }

    /// Await the pending search (tests).
    func searchSettled() async { await searchTask?.value }

    private nonisolated static func search(_ q: String, in root: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.nameKey],
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var hits: [URL] = []
        for case let url as URL in e where url.lastPathComponent.localizedStandardContains(q) {
            hits.append(url)
            if hits.count >= Self.maxSearchResults { break }
        }
        return hits
    }
}
