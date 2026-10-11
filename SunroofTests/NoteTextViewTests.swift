import AppKit
import Testing
@testable import Sunroof

@MainActor
@Suite struct NoteTextViewTests {
    func view(_ text: String, caret: Int? = nil) -> NoteTextView {
        let tv = NoteTextView(fontSize: 14)
        tv.load(text)
        tv.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
        return tv
    }

    func color(_ tv: NoteTextView, at i: Int) -> NSColor? {
        tv.textStorage?.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor
    }

    @Test func checkboxDecorations() {
        let tv = view("- [ ] a\n- [x] b\n")
        #expect(tv.decorations.contains(.checkbox(range: NSRange(location: 2, length: 3), checked: false)))
        #expect(tv.decorations.contains(.checkbox(range: NSRange(location: 10, length: 3), checked: true)))
    }

    @Test func noDecorationOnCaretLine() {
        let tv = view("- [ ] a\n- [x] b\n", caret: 1)
        #expect(!tv.decorations.contains(.checkbox(range: NSRange(location: 2, length: 3), checked: false)))
    }

    @Test func toggleCheckboxEditsTextAndUndoes() {
        let tv = view("- [ ] a\n- [x] b\n")
        tv.toggleCheckbox(at: 3)
        #expect(tv.string == "- [x] a\n- [x] b\n")
        tv.undoManager?.undo()
        #expect(tv.string == "- [ ] a\n- [x] b\n")
    }

    @Test func newlineContinuesList() {
        let tv = view("- a")
        tv.insertNewline(nil)
        #expect(tv.string == "- a\n- ")
    }

    @Test func tabIndents() {
        let tv = view("1. a\n2. b")
        tv.insertTab(nil)
        #expect(tv.string == "1. a\n\t1. b")
    }

    @Test func spaceExpandsChecklistShortcut() {
        let tv = view("[]")
        tv.insertText(" ", replacementRange: tv.selectedRange())
        #expect(tv.string == "- [ ] ")
    }

    @Test func inlineFormatting() {
        let tv = view("a b c")
        tv.setSelectedRange(NSRange(location: 2, length: 1))
        tv.toggleInline(open: "**", close: "**")
        #expect(tv.string == "a **b** c")
    }

    @Test func markersFadeOffCaretLine() {
        let tv = view("**b**\nx", caret: 7)
        #expect(color(tv, at: 0) == NoteTextView.markerColor)
        tv.setSelectedRange(NSRange(location: 1, length: 0))
        #expect(color(tv, at: 0) == NoteTextView.activeMarkerColor)
    }

    @Test func textUnchangedByStyling() {
        let lines = (0..<2000).map { ["# H\($0)", "- [ ] **t** \($0)", "1. `c` ==h==", "> q", "```", "code", "```", "plain ||x||"][$0 % 8] }
        let text = lines.joined(separator: "\n")
        let tv = view(text)
        #expect(tv.string == text)
    }

    @Test func restyleIsIncremental() {
        let text = (0..<10_000).map { "- line \($0) **bold**" }.joined(separator: "\n")
        let tv = view(text, caret: 50_000)
        tv.restyledLineCount = 0
        tv.insertText("x", replacementRange: tv.selectedRange())
        #expect(tv.restyledLineCount <= 3)
    }

    // Feedback: no indication of how to add a checkbox — an empty note shows a hint.
    @Test func emptyNoteShowsHint() {
        let tv = view("")
        #expect(tv.placeholder?.contains("[]") == true)
        tv.insertText("x", replacementRange: tv.selectedRange())
        #expect(tv.placeholder == nil)
    }

    // Feedback: "you can see the html code" — on the caret line only the span the caret is in shows its markers.
    @Test func onlyMarkersAroundCaretShow() {
        let tv = view("**b** and <u>u</u>", caret: 2) // caret inside **b**
        #expect(color(tv, at: 0) == NoteTextView.activeMarkerColor)   // "**" of the bold span
        #expect(color(tv, at: 10) == NoteTextView.markerColor)        // "<u>" — caret isn't in it
        tv.setSelectedRange(NSRange(location: 14, length: 0))         // inside <u>u</u>
        #expect(color(tv, at: 10) == NoteTextView.activeMarkerColor)
        #expect(color(tv, at: 0) == NoteTextView.markerColor)
    }

    // Feedback: faded "<u>" was still visible. Inactive markers are hidden: no colour and (almost) no width.
    @Test func inactiveMarkersTakeNoSpace() {
        let tv = view("2. <u>That</u>\nx", caret: 16)
        let font = tv.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        #expect(color(tv, at: 3) == .clear)
        #expect((font?.pointSize ?? 99) < 1)
    }
}
