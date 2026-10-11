import Foundation
import Testing
@testable import ShelfScroll

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
