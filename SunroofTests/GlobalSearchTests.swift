import Foundation
import Testing
@testable import Sunroof

@MainActor
@Suite struct GlobalSearchTests {
    func clip(_ s: String) -> Clip {
        Clip(kind: .text, date: .now, text: s, source: ClipSource(), contentHash: s)
    }

    func note(_ name: String) -> Note { Note(filename: "\(name).md", text: name, modified: .now) }

    @Test func groupsAndCaps() async {
        let g = GlobalSearch(clips: { _ in (0..<8).map { self.clip("c\($0)") } },
                             notes: { _ in [self.note("n1"), self.note("n2")] },
                             files: { _ in [] })
        g.query = "x"
        await g.settled()
        #expect(g.sections.map(\.id) == [.clipboard, .notes])
        #expect(g.sections.map(\.hits.count) == [5, 2])
    }

    @Test func emptyQueryNoResults() async {
        let g = GlobalSearch(clips: { _ in [self.clip("c")] }, notes: { _ in [] }, files: { _ in [] })
        g.query = "x"
        await g.settled()
        g.query = ""
        await g.settled()
        #expect(g.sections.isEmpty)
    }

    @Test func selectionCrossesSections() async {
        let g = GlobalSearch(clips: { _ in (0..<8).map { self.clip("c\($0)") } },
                             notes: { _ in [self.note("n1"), self.note("n2")] },
                             files: { _ in [URL(fileURLWithPath: "/f")] })
        g.query = "x"
        await g.settled()
        g.moveSelection(by: 6) // 5 clips, 1 file → first note
        #expect(g.selectedHit == .note(filename: "n1.md", title: "n1", preview: ""))
        g.moveSelection(by: 100)
        #expect(g.selection == 7)
        g.moveSelection(by: -100)
        #expect(g.selection == 0)
    }

    // Review Focus 4: a slow, older Files search never replaces a newer one.
    @Test func staleResultsDropped() async throws {
        let g = GlobalSearch(clips: { _ in [] }, notes: { _ in [] }, files: { q in
            if q == "a" { Thread.sleep(forTimeInterval: 0.3) }
            return [URL(fileURLWithPath: "/\(q)")]
        })
        g.query = "a"
        try await Task.sleep(for: .milliseconds(200)) // the "a" search is now running
        g.query = "ab"
        await g.settled()
        try await Task.sleep(for: .milliseconds(400)) // let the stale "a" search finish
        #expect(g.sections.first?.hits == [.file(URL(fileURLWithPath: "/ab"))])
    }
}
