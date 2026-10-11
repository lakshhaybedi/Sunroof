import Foundation
import Testing
@testable import ShelfScroll

@MainActor
@Suite struct NoteStoreTests {
    let folder = tempDir().appendingPathComponent("Notes")

    init() throws { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }

    func store() -> NoteStore { NoteStore(folder: folder, trash: { try FileManager.default.removeItem(at: $0) }) }

    func write(_ name: String, _ text: String, modified: Date? = nil) throws {
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
    }

    func read(_ name: String) throws -> String { try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) }
    func files() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".md") }.sorted() }

    @Test func loadsNotesSortedByModified() throws {
        try write("Old.md", "Old", modified: .init(timeIntervalSince1970: 1))
        try write("New.md", "New", modified: .init(timeIntervalSince1970: 2))
        #expect(store().notes.map(\.filename) == ["New.md", "Old.md"])
    }

    @Test func createMakesUntitledUnique() {
        let s = store()
        #expect(s.create().filename == "Untitled.md")
        #expect(s.create().filename == "Untitled 2.md")
    }

    @Test func updateSavedOnFinish() throws {
        let s = store()
        let n = s.create()
        s.update(n.filename, text: "Untitled\nhello")
        s.finishEditing(n.filename)
        #expect(try read("Untitled.md") == "Untitled\nhello")
    }

    @Test func titleRenameOnFinish() throws {
        let s = store()
        let n = s.create()
        s.update(n.filename, text: "Groceries\nmilk")
        #expect(s.finishEditing(n.filename) == "Groceries.md")
        #expect(try files() == ["Groceries.md"])
    }

    @Test func titleRenameCollision() throws {
        let s = store()
        for _ in 0..<2 {
            let n = s.create()
            s.update(n.filename, text: "Ideas")
            s.finishEditing(n.filename)
        }
        #expect(try files() == ["Ideas 2.md", "Ideas.md"])
    }

    @Test func titleSanitized() {
        #expect(NoteStore.filename(forTitle: "a/b: c") == "a-b- c.md")
        #expect(NoteStore.filename(forTitle: "  ") == "Untitled.md")
        #expect(NoteStore.filename(forTitle: String(repeating: "x", count: 300)).count <= 103)
        #expect(NoteStore.title(of: "## Heading\nbody") == "Heading")
        #expect(NoteStore.title(of: "") == "")
    }

    @Test func pinsFollowRenameAndComeFirst() throws {
        try write("A.md", "A", modified: .init(timeIntervalSince1970: 2))
        try write("B.md", "B", modified: .init(timeIntervalSince1970: 1))
        let s = store()
        s.togglePin("B.md")
        #expect(s.notes.map(\.filename) == ["B.md", "A.md"])
        s.update("B.md", text: "Bee")
        s.finishEditing("B.md")
        #expect(s.pinned == ["Bee.md"])
        #expect(store().pinned == ["Bee.md"])
    }

    @Test func roundTripByteExact() throws {
        let bytes = Data("Title\r\nline 🙂".utf8)
        let url = folder.appendingPathComponent("Title.md")
        try bytes.write(to: url)
        let past = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path)
        let s = store()
        s.finishEditing("Title.md")
        s.saveAll()
        #expect(try Data(contentsOf: url) == bytes)
        #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == past)
    }

    @Test func externalChangeReloadsCleanNote() throws {
        try write("A.md", "A\nold")
        let s = store()
        try write("A.md", "A\nnew")
        s.syncFromDisk()
        #expect(s.note("A.md")?.text == "A\nnew")
    }

    @Test func externalChangeWithLocalEditsMakesConflictCopy() throws {
        try write("A.md", "A\nold", modified: .init(timeIntervalSince1970: 1))
        let s = store()
        s.update("A.md", text: "A\nmine")
        try write("A.md", "A\ntheirs")
        s.syncFromDisk()
        #expect(s.note("A.md")?.text == "A\nmine")
        let day = Date.now.formatted(.iso8601.year().month().day())
        #expect(try read("A (conflict \(day)).md") == "A\ntheirs")
        s.saveAll()
        #expect(try read("A.md") == "A\nmine")
    }

    @Test func deleteUsesTrash() throws {
        try write("A.md", "A")
        let s = store()
        try s.delete("A.md")
        #expect(s.notes.isEmpty)
        #expect(try files().isEmpty)
    }

    @Test func duplicateIsUnique() throws {
        try write("A.md", "A\nx")
        let s = store()
        #expect(s.duplicate("A.md").filename == "A 2.md")
        #expect(try read("A 2.md") == "A\nx")
    }

    @Test func searchMatchesBody() throws {
        try write("A.md", "A\nbuy milk")
        try write("B.md", "B\nnothing")
        #expect(store().search("MILK").map(\.filename) == ["A.md"])
    }

    @Test func previewStripsMarkdown() {
        #expect(NoteStore.preview(of: "T\n- [ ] **buy** milk\n# Next") == "buy milk Next")
    }

    @Test func attachmentNamesUnique() throws {
        let s = store()
        let png = pngData(width: 2, height: 2)
        #expect(s.saveAttachment(png, for: "Trip.md") == "attachments/Trip-1.png")
        #expect(s.saveAttachment(png, for: "Trip.md") == "attachments/Trip-2.png")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("attachments/Trip-2.png").path))
    }
}
