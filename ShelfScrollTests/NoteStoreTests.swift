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
        #expect(s.saveAttachment(png, for: "Trip Plan.md") == "attachments/Trip-Plan-1.png") // review I6: no spaces
        #expect(s.saveAttachment(png, for: "Trip.md") == "attachments/Trip-2.png")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("attachments/Trip-2.png").path))
    }

    // Review C1: typing into a note whose file vanished must bring the file back, not drop the text.
    @Test func updateRecreatesVanishedNote() throws {
        try write("A.md", "A\nold")
        let s = store()
        try FileManager.default.removeItem(at: folder.appendingPathComponent("A.md"))
        s.syncFromDisk()
        s.update("A.md", text: "A\nnew")
        s.saveAll()
        #expect(try read("A.md") == "A\nnew")
        #expect(s.note("A.md")?.text == "A\nnew")
    }

    // Review C2: an in-place external write (no directory event) is detected at save time → conflict copy.
    @Test func saveDetectsExternalWriteWithoutWatcher() throws {
        try write("A.md", "A\nold", modified: .init(timeIntervalSince1970: 1))
        let s = store()
        s.update("A.md", text: "A\nmine")
        try write("A.md", "A\ntheirs")
        s.saveAll()
        let day = Date.now.formatted(.iso8601.year().month().day())
        #expect(try read("A (conflict \(day)).md") == "A\ntheirs")
        #expect(try read("A.md") == "A\nmine")
    }

    // Review: identical external content is not a conflict.
    @Test func identicalExternalChangeIsNotAConflict() throws {
        try write("A.md", "A\nold", modified: .init(timeIntervalSince1970: 1))
        let s = store()
        s.update("A.md", text: "A\nsame")
        try write("A.md", "A\nsame")
        s.syncFromDisk()
        #expect(try files() == ["A.md"])
    }

    // Review C3: a failed write keeps the note unsaved and reports it.
    @Test func failedSaveStaysDirtyAndReports() throws {
        try write("A.md", "A")
        let s = store()
        var errors: [String] = []
        s.onSaveError = { errors.append($0) }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        s.update("A.md", text: "A\nnew")
        s.saveAll()
        #expect(s.hasUnsavedChanges("A.md"))
        #expect(errors.count == 1)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        s.saveAll()
        #expect(!s.hasUnsavedChanges("A.md"))
        #expect(try read("A.md") == "A\nnew")
    }

    // Review C2c: the folder created on first run gets a watcher.
    @Test func watcherStartsWhenFolderIsCreated() async throws {
        let fresh = tempDir().appendingPathComponent("Fresh")
        let s = NoteStore(folder: fresh)
        s.create(text: "First")
        try Data("Second".utf8).write(to: fresh.appendingPathComponent("Second.md"))
        for _ in 0..<40 where s.note("Second.md") == nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(s.note("Second.md") != nil)
    }

    // Review I4: a note already named "Ideas 2.md" for title "Ideas" keeps its name.
    @Test func duplicateTitleDoesNotFlipFlop() throws {
        let s = store()
        for _ in 0..<2 { let n = s.create(); s.update(n.filename, text: "Ideas"); s.finishEditing(n.filename) }
        s.update("Ideas 2.md", text: "Ideas\nmore")
        #expect(s.finishEditing("Ideas 2.md") == "Ideas 2.md")
    }

    // Review I5: leading dots would hide the file; long names stay within 255 bytes.
    @Test func leadingDotsStripped() {
        #expect(NoteStore.filename(forTitle: ".env notes") == "env notes.md")
        #expect(NoteStore.filename(forTitle: "...") == "Untitled.md")
        #expect(NoteStore.filename(forTitle: String(repeating: "🙂", count: 100)).utf8.count <= 255)
    }

    // Review I8: the editor reloads only on external changes — tracked by a revision, not text comparison.
    @Test func revisionBumpsOnlyOnExternalChange() throws {
        try write("A.md", "A\nold")
        let s = store()
        let r0 = s.note("A.md")!.revision
        s.update("A.md", text: "A\ntyped")
        #expect(s.note("A.md")!.revision == r0)
        s.saveAll()
        try write("A.md", "A\nexternal")
        s.syncFromDisk()
        #expect(s.note("A.md")!.revision == r0 + 1)
    }

    // Review I11: an iCloud-evicted note (".A.md.icloud" placeholder) isn't dropped.
    @Test func icloudPlaceholderKeepsNote() throws {
        try write("A.md", "A")
        let s = store()
        try FileManager.default.moveItem(at: folder.appendingPathComponent("A.md"), to: folder.appendingPathComponent(".A.md.icloud"))
        s.syncFromDisk()
        #expect(s.note("A.md") != nil)
    }

    // MARK: - Send to Note

    @Test func appendingSeparates() {
        #expect(NoteStore.appending("x", to: "A") == "A\n\nx")
        #expect(NoteStore.appending("x", to: "A\n") == "A\n\nx")
        #expect(NoteStore.appending("x", to: "A\n\n") == "A\n\nx")
        #expect(NoteStore.appending("x", to: "") == "x")
    }

    @Test func appendToExistingSaves() throws {
        try write("A.md", "A")
        let s = store()
        let r0 = s.note("A.md")!.revision
        #expect(s.append("clip", to: "A.md") == "A.md")
        s.saveAll()
        #expect(try read("A.md") == "A\n\nclip")
        #expect(s.note("A.md")!.revision == r0 + 1) // an open editor reloads
    }

    @Test func appendToNewNoteUsesFirstLineAsTitle() throws {
        let s = store()
        let name = s.append("Buy milk\nand eggs", to: nil)
        s.saveAll()
        #expect(name == "Buy milk.md")
        #expect(try read("Buy milk.md") == "Buy milk\nand eggs")
    }

    @Test func appendImageCopiesAttachment() throws {
        try write("Trip.md", "Trip")
        let s = store()
        s.appendImage(pngData(width: 2, height: 2), to: "Trip.md")
        #expect(s.note("Trip.md")!.text == "Trip\n\n![](attachments/Trip-1.png)")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("attachments/Trip-1.png").path))
    }

    // Review Focus 2: appending into a note with unsaved typing keeps both.
    @Test func appendWhileDirtyKeepsBoth() {
        let s = store()
        let n = s.create(text: "A")
        s.update(n.filename, text: "A\ntyped")
        s.append("clip", to: n.filename)
        #expect(s.note(n.filename)!.text == "A\ntyped\n\nclip")
    }

    @Test func recentTitles() throws {
        try write("Old.md", "Old", modified: .init(timeIntervalSince1970: 1))
        try write("New.md", "New", modified: .init(timeIntervalSince1970: 2))
        #expect(store().recentNoteTitles.map(\.title) == ["New", "Old"])
    }

    // MARK: - Stickies support

    @Test func renameNotifies() {
        let s = store()
        var events: [String] = []
        s.onRename.append { events.append("\($0)→\($1)") }
        let n = s.create()
        s.update(n.filename, text: "Groceries")
        s.finishEditing(n.filename)
        #expect(events == ["Untitled.md→Groceries.md"])
    }

    @Test func deleteNotifies() throws {
        try write("A.md", "A")
        let s = store()
        var deleted: [String] = []
        s.onDelete.append { deleted.append($0) }
        try s.delete("A.md")
        #expect(deleted == ["A.md"])
    }

    @Test func externalDeleteNotifies() throws {
        try write("A.md", "A")
        let s = store()
        var deleted: [String] = []
        s.onDelete.append { deleted.append($0) }
        try FileManager.default.removeItem(at: folder.appendingPathComponent("A.md"))
        s.syncFromDisk()
        #expect(deleted == ["A.md"])
    }

    // Review Focus 1: the same note edited from two editors — last text wins, saved once.
    @Test func twoEditorsUpdateSameNote() throws {
        let s = store()
        let n = s.create(text: "A")
        s.update(n.filename, text: "A\none")
        s.update(n.filename, text: "A\none two")
        s.saveAll()
        #expect(try read(n.filename) == "A\none two")
    }
}
