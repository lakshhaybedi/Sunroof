import Foundation
import Testing
@testable import Sunroof

/// "a|b" = caret; "a‹b›c" = selection.
func te(_ s: String) -> TextEdit {
    let ns = s as NSString
    let open = ns.range(of: "‹"), close = ns.range(of: "›")
    if open.location != NSNotFound, close.location != NSNotFound {
        let text = s.replacingOccurrences(of: "‹", with: "").replacingOccurrences(of: "›", with: "")
        return TextEdit(text: text, selection: NSRange(location: open.location, length: close.location - open.location - 1))
    }
    let caret = ns.range(of: "|")
    return TextEdit(text: s.replacingOccurrences(of: "|", with: ""), selection: NSRange(location: caret.location, length: 0))
}

func render(_ t: TextEdit?) -> String? {
    guard let t else { return nil }
    let ns = NSMutableString(string: t.text)
    if t.selection.length == 0 { ns.insert("|", at: t.selection.location) }
    else { ns.insert("›", at: NSMaxRange(t.selection)); ns.insert("‹", at: t.selection.location) }
    return ns as String
}

@Suite struct ListEditingTests {
    @Test(arguments: [
        ("- item|", "- item\n- |"),
        ("1. one|\n2. two", "1. one\n2. |\n3. two"),
        ("- [x] done|", "- [x] done\n- [ ] |"),
        ("\t- a|", "\t- a\n\t- |"),
        ("- ab|cd", "- ab\n- |cd"),
        ("- |", "|"),
        ("> q|", "> q\n> |"),
        ("x\n- [ ] |", "x\n|"),
    ])
    func newline(_ input: String, _ expected: String) {
        #expect(render(ListEditing.newline(te(input))) == expected)
    }

    @Test func newlineOutsideListIsDefault() {
        #expect(ListEditing.newline(te("plain|")) == nil)
    }

    @Test func tabIndentsAndRenumbers() {
        let indented = ListEditing.indent(te("1. a\n2. b|"), outdent: false)
        #expect(render(indented) == "1. a\n\t1. b|")
        #expect(render(ListEditing.indent(indented!, outdent: true)) == "1. a\n2. b|")
        #expect(ListEditing.indent(te("plain|"), outdent: false) == nil)
    }

    @Test func renumber() {
        #expect(ListEditing.renumber("1. a\n1. b\n\t1. x\n\t5. y\n1. c\ntext\n3. d") ==
                "1. a\n2. b\n\t1. x\n\t2. y\n3. c\ntext\n3. d")
    }

    // Review I7: renumbering never touches fenced code.
    @Test func renumberSkipsCode() {
        #expect(ListEditing.renumber("1. a\n1. b\n```\n1. x\n1. y\n```\n1. c") == "1. a\n2. b\n```\n1. x\n1. y\n```\n1. c")
    }

    @Test func toggleCheckbox() {
        #expect(ListEditing.toggleCheckbox(lineContaining: 7, in: "x\n- [ ] a") == "x\n- [x] a")
        #expect(ListEditing.toggleCheckbox(lineContaining: 0, in: "- [x] a") == "- [ ] a")
        #expect(ListEditing.toggleCheckbox(lineContaining: 0, in: "- a") == "- a")
    }

    @Test func moveLineDownRenumbers() {
        #expect(render(ListEditing.moveLine(te("1. a|\n2. b"), up: false)) == "1. b\n2. a|")
        #expect(render(ListEditing.moveLine(te("x\ny|"), up: true)) == "y|\nx")
    }

    @Test func toggleInline() {
        #expect(render(ListEditing.toggleInline(te("x ‹abc› y"), open: "**", close: "**")) == "x **‹abc›** y")
        #expect(render(ListEditing.toggleInline(te("x **‹abc›** y"), open: "**", close: "**")) == "x ‹abc› y")
        #expect(render(ListEditing.toggleInline(te("a|"), open: "**", close: "**")) == "a**|**")
        #expect(render(ListEditing.toggleInline(te("‹u›"), open: "<u>", close: "</u>")) == "<u>‹u›</u>")
    }

    // Feedback: a selection that includes the line break (triple-click / drag to line end) wrapped markers
    // across lines, so they never matched and showed raw. Formatting trims to the line's text.
    @Test func toggleInlineTrimsLineBreakAndListMarker() {
        #expect(render(ListEditing.toggleInline(te("a\n‹4. This is a sentence\n›5. b"), open: "~~", close: "~~"))
                == "a\n4. ~~‹This is a sentence›~~\n5. b")
        #expect(render(ListEditing.toggleInline(te("‹ab ›c"), open: "**", close: "**")) == "**‹ab›** c")
    }

    @Test func toggleInlineAcrossLinesWrapsEachLine() {
        let wrapped = ListEditing.toggleInline(te("‹- a\n- b›"), open: "**", close: "**")
        #expect(render(wrapped) == "‹- **a**\n- **b**›")
        #expect(render(ListEditing.toggleInline(wrapped, open: "**", close: "**")) == "‹- a\n- b›")
    }

    // Feedback: links — paste a URL, press Return.
    @Test func insertLinkAroundSelection() {
        #expect(render(ListEditing.insertLink(te("see ‹docs› now"), url: "https://x.com")) == "see [docs](https://x.com)| now")
        #expect(render(ListEditing.insertLink(te("‹- [ ] task\n›"), url: "x.com")) == "- [ ] [task](https://x.com)|\n")
    }

    @Test func insertBareLinkAtCaret() {
        #expect(render(ListEditing.insertLink(te("go to |"), url: "  https://apple.com\n")) == "go to https://apple.com|")
    }

    @Test func normalizesURLs() {
        #expect(ListEditing.normalizedURL("apple.com") == "https://apple.com")
        #expect(ListEditing.normalizedURL("mailto:me@x.com") == "mailto:me@x.com")
        #expect(ListEditing.normalizedURL("http://x.com/a b") == "http://x.com/a%20b") // spaces would end the link
        #expect(ListEditing.normalizedURL("   ") == nil)
    }

    @Test func toggleBlock() {
        #expect(render(ListEditing.toggleBlock(te("- x|"), .heading(2))) == "## x|")
        #expect(render(ListEditing.toggleBlock(te("## x|"), .heading(2))) == "x|")
        #expect(render(ListEditing.toggleBlock(te("‹a\nb›"), .checklist)) == "‹- [ ] a\n- [ ] b›")
        #expect(render(ListEditing.toggleBlock(te("‹a\nb\nc›"), .numbered)) == "‹1. a\n2. b\n3. c›")
        #expect(render(ListEditing.toggleBlock(te("- a|"), .bullet)) == "a|")
    }

    @Test func expandShortcut() {
        #expect(render(ListEditing.expandShortcut(te("[] |"))) == "- [ ] |")
        #expect(ListEditing.expandShortcut(te("x |")) == nil)
    }
}
