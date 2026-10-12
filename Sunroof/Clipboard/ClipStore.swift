import Foundation
import Observation

/// Clipboard history (local only) and favorites (in a user folder that may sync).
/// Sensitive clips live in memory only.
@MainActor @Observable
final class ClipStore {
    private(set) var history: [Clip] = []
    private(set) var favorites: [Clip] = []
    var limit: Int { didSet { if limit != oldValue { trim(); scheduleSave(history: true) } } }

    @ObservationIgnored private let historyDir: URL
    @ObservationIgnored private(set) var favoritesDir: URL
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var historyDirty = false
    @ObservationIgnored private var favoritesDirty = false
    /// False when favorites.json exists but can't be read (evicted cloud file, permissions):
    /// never overwrite what we couldn't load.
    @ObservationIgnored private var favoritesWritable = true

    var historyImagesDir: URL { historyDir.appendingPathComponent("images") }
    var favoritesImagesDir: URL { favoritesDir.appendingPathComponent("images") }
    private var historyFile: URL { historyDir.appendingPathComponent("history.json") }
    private var favoritesFile: URL { favoritesDir.appendingPathComponent("favorites.json") }

    init(historyDir: URL, favoritesDir: URL, limit: Int) {
        self.historyDir = historyDir
        self.favoritesDir = favoritesDir
        self.limit = limit
        try? FileManager.default.createDirectory(at: historyDir.appendingPathComponent("images"), withIntermediateDirectories: true)
        Self.makePrivate(historyDir) // clipboard history is readable by this account only
        Self.makePrivate(historyImagesDir)
        history = Self.load(historyFile, imagesDir: historyImagesDir) ?? []
        loadFavorites()
        trim()
    }

    // MARK: - Mutations

    func ingest(_ clip: Clip) {
        if let i = history.firstIndex(where: { $0.contentHash == clip.contentHash }) {
            var existing = history.remove(at: i)
            existing.date = clip.date
            existing.source = clip.source
            history.insert(existing, at: 0)
            if let file = clip.imageFile, file != existing.imageFile { removeImage(file, in: historyImagesDir) }
        } else {
            history.insert(clip, at: 0)
        }
        trim()
        scheduleSave(history: true)
    }

    func delete(_ id: Clip.ID) {
        guard let i = history.firstIndex(where: { $0.id == id }) else { return }
        let c = history.remove(at: i)
        if let f = c.imageFile { removeImage(f, in: historyImagesDir) }
        scheduleSave(history: true)
    }

    func clearHistory() {
        history.compactMap(\.imageFile).forEach { removeImage($0, in: historyImagesDir) }
        history.removeAll()
        scheduleSave(history: true)
    }

    func isFavorite(_ clip: Clip) -> Bool {
        favorites.contains { $0.contentHash == clip.contentHash }
    }

    func toggleFavorite(_ clip: Clip) {
        guard !clip.isSensitive else { return } // concealed clips are memory-only
        if let i = favorites.firstIndex(where: { $0.contentHash == clip.contentHash }) {
            let removed = favorites.remove(at: i)
            if let f = removed.imageFile { removeImage(f, in: favoritesImagesDir) }
        } else {
            var copy = clip
            copy.id = UUID()
            copy.isSensitive = false
            if clip.imageFile != nil, let src = imageURL(for: clip) {
                try? FileManager.default.createDirectory(at: favoritesImagesDir, withIntermediateDirectories: true)
                let name = "\(copy.id.uuidString).png"
                try? FileManager.default.copyItem(at: src, to: favoritesImagesDir.appendingPathComponent(name))
                copy.imageFile = name
            }
            favorites.insert(copy, at: 0)
        }
        scheduleSave(favorites: true)
    }

    func updateText(_ id: Clip.ID, to text: String) {
        guard let i = history.firstIndex(where: { $0.id == id }) else { return }
        history[i].kind = .text
        history[i].text = text
        history[i].rtf = nil
        history[i].contentHash = Clip.hash(kind: .text, payload: Data(text.utf8))
        scheduleSave(history: true)
    }

    func imageURL(for clip: Clip) -> URL? {
        guard let file = clip.imageFile else { return nil }
        let dir = favorites.contains { $0.id == clip.id } ? favoritesImagesDir : historyImagesDir
        return dir.appendingPathComponent(file)
    }

    static func filter(_ clips: [Clip], query: String) -> [Clip] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return clips }
        return clips.filter { c in
            // A concealed clip only matches by app name: matching its text would confirm what a password contains.
            [c.isSensitive ? nil : c.text, c.source.name].compactMap { $0 }.contains { $0.localizedStandardContains(q) }
                || (c.fileURLs ?? []).contains { $0.lastPathComponent.localizedStandardContains(q) }
        }
    }

    /// Switch the favorites folder: load what's there, or carry current favorites over if it has none.
    func useFavoritesFolder(_ url: URL) {
        guard url.standardizedFileURL != favoritesDir.standardizedFileURL else { return }
        let oldImages = favoritesImagesDir
        favoritesDir = url
        if FileManager.default.fileExists(atPath: favoritesFile.path) {
            loadFavorites()
        } else {
            favoritesWritable = true
            try? FileManager.default.createDirectory(at: favoritesImagesDir, withIntermediateDirectories: true)
            for name in favorites.compactMap(\.imageFile) {
                try? FileManager.default.copyItem(at: oldImages.appendingPathComponent(name),
                                                  to: favoritesImagesDir.appendingPathComponent(name))
            }
            scheduleSave(favorites: true)
        }
    }

    // MARK: - Persistence

    /// Synchronous flush for app termination.
    func saveSync() {
        pendingSave?.cancel()
        Self.write(snapshot())
    }

    func saveNow() async {
        pendingSave?.cancel()
        pendingSave = nil
        let jobs = snapshot()
        await Task.detached(priority: .utility) { Self.write(jobs) }.value
    }

    private func scheduleSave(history h: Bool = false, favorites f: Bool = false) {
        historyDirty = historyDirty || h
        favoritesDirty = favoritesDirty || f
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    private struct Job: Sendable { let url: URL; let clips: [Clip] }

    /// What needs writing now; clears the dirty flags.
    private func snapshot() -> [Job] {
        var jobs: [Job] = []
        if historyDirty { jobs.append(Job(url: historyFile, clips: history.filter { !$0.isSensitive })) }
        if favoritesDirty && favoritesWritable { jobs.append(Job(url: favoritesFile, clips: favorites)) }
        historyDirty = false
        favoritesDirty = false
        return jobs
    }

    private nonisolated static func write(_ jobs: [Job]) {
        let encoder = JSONEncoder()
        for job in jobs {
            guard let data = try? encoder.encode(job.clips) else { continue }
            try? FileManager.default.createDirectory(at: job.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: job.url, options: .atomic)
            makePrivate(job.url)
        }
    }

    /// rwx/rw for this account only (0700 folders, 0600 files).
    nonisolated static func makePrivate(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        try? FileManager.default.setAttributes([.posixPermissions: isDir.boolValue ? 0o700 : 0o600], ofItemAtPath: url.path)
    }

    private func loadFavorites() {
        let exists = FileManager.default.fileExists(atPath: favoritesFile.path)
        let loaded = Self.load(favoritesFile, imagesDir: favoritesImagesDir)
        favorites = loaded ?? []
        favoritesWritable = !exists || loaded != nil
    }

    /// nil when the file exists but can't be read; [] when missing or corrupt (corrupt file moved aside).
    private static func load(_ file: URL, imagesDir: URL) -> [Clip]? {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        guard let data = try? Data(contentsOf: file) else { return nil }
        guard let clips = try? JSONDecoder().decode([Clip].self, from: data) else {
            let bad = file.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: bad)
            try? FileManager.default.moveItem(at: file, to: bad)
            return []
        }
        return clips.filter { c in
            guard let f = c.imageFile else { return true }
            return FileManager.default.fileExists(atPath: imagesDir.appendingPathComponent(f).path)
        }
    }

    private func trim() {
        guard history.count > limit else { return }
        history[limit...].compactMap(\.imageFile).forEach { removeImage($0, in: historyImagesDir) }
        history.removeSubrange(limit...)
    }

    private func removeImage(_ name: String, in dir: URL) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }
}
