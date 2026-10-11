import Foundation
import Observation

struct Note: Identifiable, Equatable {
    var id: String { filename }
    var filename: String
    var text: String
    var modified: Date
    /// Bumped only when the text is replaced from disk (sync) — the editor reloads on change, never on typing.
    var revision = 0
    var title: String { NoteStore.title(of: text) }
    var preview: String { NoteStore.preview(of: text) }
}

/// Notes as plain `.md` files in one folder. Writes only what changed; never silently overwrites an external edit.
@MainActor @Observable
final class NoteStore {
    var folder: URL { didSet { load() } }
    private(set) var notes: [Note] = []
    private(set) var pinned: [String] = []

    @ObservationIgnored private let trashItem: (URL) throws -> Void
    @ObservationIgnored private var dirty = Set<String>()   // unsaved text
    @ObservationIgnored private var edited = Set<String>()  // changed this session → title rename allowed
    @ObservationIgnored private var diskModified: [String: Date] = [:]
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var reportedFailures = Set<String>()
    /// Called once per note when a save fails (permission denied, disk full, volume offline).
    @ObservationIgnored var onSaveError: ((String) -> Void)?

    init(folder: URL, trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.folder = folder
        self.trashItem = trash
        load()
    }

    private func url(_ filename: String) -> URL { folder.appendingPathComponent(filename) }
    private var pinsURL: URL { folder.appendingPathComponent(".pins.json") }

    func note(_ filename: String) -> Note? { notes.first { $0.filename == filename } }

    // MARK: - Editing

    @discardableResult func create(text: String = "") -> Note {
        ensureFolder()
        let name = uniqueDestination(for: "Untitled.md", in: folder).lastPathComponent
        let note = Note(filename: name, text: text, modified: .now)
        notes.append(note)
        write(name, text)
        sort()
        return note
    }

    /// Called on every keystroke (no text comparison — that's O(n) for huge notes).
    func update(_ filename: String, text: String) {
        if let i = notes.firstIndex(where: { $0.filename == filename }) {
            notes[i].text = text
            notes[i].modified = .now
        } else {
            // The file vanished under the editor (renamed/deleted elsewhere): keep the text; the save recreates it.
            notes.append(Note(filename: filename, text: text, modified: .now))
            sort()
        }
        dirty.insert(filename)
        edited.insert(filename)
        scheduleSave()
    }

    /// Flushes the note and, if its title changed while editing, renames the file to match. Returns the current filename.
    @discardableResult func finishEditing(_ filename: String) -> String {
        saveAll()
        guard edited.remove(filename) != nil, let i = notes.firstIndex(where: { $0.filename == filename }) else { return filename }
        let title = notes[i].title
        guard !title.isEmpty else { return filename }
        let desired = Self.filename(forTitle: title)
        // Already "<title>.md" or "<title> N.md": keep it (renaming would flip-flop between duplicates).
        let base = NSRegularExpression.escapedPattern(for: (desired as NSString).deletingPathExtension)
        if filename.range(of: "^\(base)( \\d+)?\\.md$", options: [.regularExpression, .caseInsensitive]) != nil { return filename }
        let dest = desired.lowercased() == filename.lowercased() ? url(desired) : uniqueDestination(for: desired, in: folder)
        guard (try? FileManager.default.moveItem(at: url(filename), to: dest)) != nil else { return filename }
        let new = dest.lastPathComponent
        notes[i].filename = new
        diskModified[new] = mtime(new)
        diskModified[filename] = nil
        if let p = pinned.firstIndex(of: filename) { pinned[p] = new; savePins() }
        sort()
        return new
    }

    func delete(_ filename: String) throws {
        try trashItem(url(filename))
        notes.removeAll { $0.filename == filename }
        dirty.remove(filename)
        if pinned.contains(filename) { pinned.removeAll { $0 == filename }; savePins() }
    }

    @discardableResult func duplicate(_ filename: String) -> Note {
        let text = note(filename)?.text ?? ""
        let name = uniqueDestination(for: filename, in: folder).lastPathComponent
        let copy = Note(filename: name, text: text, modified: .now)
        notes.append(copy)
        write(name, text)
        sort()
        return copy
    }

    func togglePin(_ filename: String) {
        if pinned.contains(filename) { pinned.removeAll { $0 == filename } } else { pinned.append(filename) }
        savePins()
        sort()
    }

    func search(_ query: String) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? notes : notes.filter { $0.text.localizedStandardContains(q) }
    }

    func saveAttachment(_ png: Data, for filename: String) -> String {
        let dir = folder.appendingPathComponent("attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = (filename as NSString).deletingPathExtension.replacingOccurrences(of: " ", with: "-") // markdown paths can't hold spaces
        var n = 1
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(base)-\(n).png").path) { n += 1 }
        try? png.write(to: dir.appendingPathComponent("\(base)-\(n).png"), options: .atomic)
        return "attachments/\(base)-\(n).png"
    }

    // MARK: - Saving & syncing

    func hasUnsavedChanges(_ filename: String) -> Bool { dirty.contains(filename) }

    /// Writes every unsaved note. If a file changed on disk since we last read it (in-place editors, sync inside
    /// the watcher's debounce), their version is kept as a conflict copy first. Failed writes stay unsaved.
    func saveAll() {
        pendingSave?.cancel()
        pendingSave = nil
        for name in dirty {
            guard let n = note(name) else { dirty.remove(name); continue }
            let fileURL = url(name)
            if let m = mtime(name), m != diskModified[name], let theirs = Self.read(fileURL), theirs != n.text {
                writeConflictCopy(theirs, for: name)
            }
            if write(name, n.text) {
                dirty.remove(name)
                reportedFailures.remove(name)
            } else if reportedFailures.insert(name).inserted {
                onSaveError?("Couldn't save “\(n.title.isEmpty ? name : n.title)”. Check that the Notes folder is available.")
            }
        }
    }

    private func writeConflictCopy(_ text: String, for name: String) {
        let day = Date.now.formatted(.iso8601.year().month().day())
        let base = (name as NSString).deletingPathExtension
        try? Data(text.utf8).write(to: uniqueDestination(for: "\(base) (conflict \(day)).md", in: folder), options: .atomic)
    }

    private func ensureFolder() {
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        watcher = FolderWatcher(url: folder) { [weak self] in self?.syncFromDisk() } // none could exist before
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveAll()
        }
    }

    @discardableResult private func write(_ name: String, _ text: String) -> Bool {
        ensureFolder()
        guard (try? Data(text.utf8).write(to: url(name), options: .atomic)) != nil else { return false }
        diskModified[name] = mtime(name)
        return true
    }

    /// Reconciles with the folder after an external change (sync from another Mac, another editor).
    func syncFromDisk() {
        let (files, evicted) = listing()
        let onDisk = Dictionary(uniqueKeysWithValues: files.map { ($0.lastPathComponent, $0) })
        for (name, fileURL) in onDisk {
            let m = mtime(name)
            if let i = notes.firstIndex(where: { $0.filename == name }) {
                guard m != diskModified[name], let text = Self.read(fileURL) else { continue }
                diskModified[name] = m
                guard text != notes[i].text else { continue } // same content: not a conflict
                if dirty.contains(name) {
                    writeConflictCopy(text, for: name) // keep local edits; preserve theirs next to it
                } else {
                    notes[i].text = text
                    notes[i].modified = m ?? .now
                    notes[i].revision += 1
                }
            } else if let text = Self.read(fileURL) {
                notes.append(Note(filename: name, text: text, modified: m ?? .now))
                diskModified[name] = m
            }
        }
        notes.removeAll { onDisk[$0.filename] == nil && !dirty.contains($0.filename) && !evicted.contains($0.filename) }
        sort()
    }

    // MARK: - Loading

    private func load() {
        notes = listing().files.compactMap { u in
            guard let text = Self.read(u) else { return nil } // unreadable / non-UTF-8: skipped, never rewritten
            let name = u.lastPathComponent
            diskModified[name] = mtime(name)
            return Note(filename: name, text: text, modified: diskModified[name] ?? .distantPast)
        }
        pinned = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: pinsURL))) ?? []
        sort()
        watcher = FolderWatcher(url: folder) { [weak self] in self?.syncFromDisk() }
    }

    /// Visible `.md` files, plus names of notes iCloud has evicted (".Name.md.icloud" placeholders) — those are
    /// asked to download and are never treated as deleted.
    private func listing() -> (files: [URL], evicted: Set<String>) {
        let all = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var files: [URL] = [], evicted = Set<String>()
        for u in all {
            let name = u.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".md.icloud") {
                let real = String(name.dropFirst().dropLast(".icloud".count))
                evicted.insert(real)
                try? FileManager.default.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(real))
            } else if !name.hasPrefix("."), u.pathExtension.lowercased() == "md" {
                files.append(u)
            }
        }
        return (files, evicted)
    }

    private nonisolated static func read(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func mtime(_ name: String) -> Date? {
        try? url(name).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func savePins() {
        try? JSONEncoder().encode(pinned).write(to: pinsURL, options: .atomic)
    }

    private func sort() {
        let pins = pinned
        notes.sort { a, b in
            let pa = pins.firstIndex(of: a.filename), pb = pins.firstIndex(of: b.filename)
            switch (pa, pb) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.modified > b.modified
            }
        }
    }

    // MARK: - Titles & previews

    nonisolated static func title(of text: String) -> String {
        let first = text.prefix { $0 != "\n" && $0 != "\r" }
        return first.drop { $0 == "#" || $0 == " " }.trimmingCharacters(in: .whitespaces)
    }

    nonisolated static func filename(forTitle title: String) -> String {
        var t = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        t = String(t.drop { $0 == "." }) // a leading dot would make the note a hidden file
        t = String(t.prefix(100)).trimmingCharacters(in: .whitespaces)
        while t.utf8.count > 250 { t.removeLast() } // filesystem limit is 255 bytes
        return (t.isEmpty ? "Untitled" : t) + ".md"
    }

    nonisolated static func preview(of text: String) -> String {
        let lines = text.components(separatedBy: .newlines).dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let stripped = lines.prefix(2).map { line -> String in
            let ns = NSMutableString(string: line)
            let markers = MarkdownStyler.parse(line, inCodeBlock: false).spans.filter { $0.kind == .marker }
            for m in markers.sorted(by: { $0.range.location > $1.range.location }) { ns.deleteCharacters(in: m.range) }
            return (ns as String).trimmingCharacters(in: .whitespaces)
        }
        return String(stripped.joined(separator: " ").prefix(140))
    }
}
