import AppKit
import Testing
@testable import Sunroof

@MainActor
@Suite struct NoteEditorBindingTests {
    let folder = tempDir().appendingPathComponent("Notes")

    func type(_ text: String, into b: NoteEditorBinding) {
        let end = NSRange(location: (b.textView.string as NSString).length, length: 0)
        b.textView.setSelectedRange(end)
        b.textView.insertText(text, replacementRange: end)
    }

    // Review C1: two editors on one note — a stale editor must not overwrite the other's text.
    @Test func twoEditorsStayInSync() {
        let s = NoteStore(folder: folder)
        let n = s.create(text: "A")
        let shelf = NoteEditorBinding(store: s, textView: NoteTextView(fontSize: 14), filename: n.filename)
        let sticky = NoteEditorBinding(store: s, textView: NoteTextView(fontSize: 14), filename: n.filename)
        type(" from sticky", into: sticky)
        shelf.storeDidChange()
        #expect(shelf.textView.string == "A from sticky")
        type("!", into: shelf)
        sticky.storeDidChange()
        #expect(s.note(n.filename)?.text == "A from sticky!")
        #expect(sticky.textView.string == "A from sticky!")
    }

    // Own keystrokes never reload the editor (caret and undo survive).
    @Test func ownWritesDontReload() {
        let s = NoteStore(folder: folder)
        let n = s.create(text: "A")
        let b = NoteEditorBinding(store: s, textView: NoteTextView(fontSize: 14), filename: n.filename)
        type("bc", into: b)
        b.textView.setSelectedRange(NSRange(location: 1, length: 0))
        b.storeDidChange()
        #expect(b.textView.selectedRange().location == 1)
    }

    // Review I3/minor 9: a rename switches the editor's filename without reloading; typing keeps going to the new file.
    @Test func renameKeepsEditorAndCaret() {
        let s = NoteStore(folder: folder)
        let n = s.create()
        let b = NoteEditorBinding(store: s, textView: NoteTextView(fontSize: 14), filename: n.filename)
        type("Groceries", into: b)
        let renamed = s.finishEditing(n.filename)
        b.textView.setSelectedRange(NSRange(location: 3, length: 0))
        b.setFilename(renamed)
        #expect(b.textView.selectedRange().location == 3)
        type("!", into: b)
        #expect(s.note(renamed)?.text == "Groceries!")
        #expect(s.note(n.filename) == nil)
    }

    // Review I2: the shelf's controller follows renames and deletes made elsewhere (e.g. by a sticky).
    @Test func controllerFollowsRenameAndDelete() throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        let s = NoteStore(folder: folder, trash: { try FileManager.default.removeItem(at: $0) })
        let c = NotesController(store: s, settings: AppSettings(defaults: defaults))
        let n = s.create()
        c.open(n.filename)
        s.update(n.filename, text: "Foo")
        let renamed = s.finishEditing(n.filename)
        #expect(c.current == renamed)
        let other = s.create(text: "Other")
        try s.delete(renamed)
        #expect(c.current == other.filename)
    }
}
