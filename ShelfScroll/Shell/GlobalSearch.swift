import Foundation
import Observation

enum SearchHit: Identifiable, Equatable {
    case clip(Clip)
    case file(URL)
    case note(filename: String, title: String, preview: String)

    var id: String {
        switch self {
        case let .clip(c): "c:\(c.id)"
        case let .file(u): "f:\(u.path)"
        case let .note(f, _, _): "n:\(f)"
        }
    }
}

struct SearchSection: Identifiable, Equatable {
    let id: PanelID
    let title: String
    let hits: [SearchHit]
}

/// ⌘⇧F search across Clipboard, Files and Notes. Providers are closures so panels stay decoupled.
@MainActor @Observable
final class GlobalSearch {
    static let perSection = 5

    var isVisible = false
    var query = "" { didSet { if query != oldValue { schedule() } } }
    private(set) var sections: [SearchSection] = []
    var selection = 0

    @ObservationIgnored private let clips: (String) -> [Clip]
    @ObservationIgnored private let notes: (String) -> [Note]
    @ObservationIgnored private let files: @Sendable (String) -> [URL]
    @ObservationIgnored private var task: Task<Void, Never>?

    init(clips: @escaping (String) -> [Clip], notes: @escaping (String) -> [Note], files: @escaping @Sendable (String) -> [URL]) {
        self.clips = clips
        self.notes = notes
        self.files = files
    }

    var flat: [SearchHit] { sections.flatMap(\.hits) }
    var selectedHit: SearchHit? { flat.indices.contains(selection) ? flat[selection] : nil }

    func moveSelection(by delta: Int) {
        selection = max(0, min(selection + delta, flat.count - 1))
    }

    func settled() async { await task?.value }

    private func schedule() {
        task?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { sections = []; selection = 0; task = nil; return }
        let files = files
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            let clipHits = self.clips(q).prefix(Self.perSection).map(SearchHit.clip)
            let noteHits = self.notes(q).prefix(Self.perSection).map { SearchHit.note(filename: $0.filename, title: $0.title, preview: $0.preview) }
            let walk = Task.detached(priority: .userInitiated) { files(q) }
            let fileURLs = await withTaskCancellationHandler { await walk.value } onCancel: { walk.cancel() }
            // A newer query may have started while Files was searching: drop stale results.
            guard !Task.isCancelled, self.query.trimmingCharacters(in: .whitespaces) == q else { return }
            let fileHits = fileURLs.prefix(Self.perSection).map(SearchHit.file)
            self.sections = [
                SearchSection(id: .clipboard, title: "Clipboard", hits: Array(clipHits)),
                SearchSection(id: .files, title: "Files", hits: Array(fileHits)),
                SearchSection(id: .notes, title: "Notes", hits: Array(noteHits)),
            ].filter { !$0.hits.isEmpty }
            self.selection = 0
        }
    }
}
