import Foundation
import Testing
@testable import Sunroof

private func s(_ loc: Int, _ len: Int, _ kind: SpanKind) -> MarkSpan { MarkSpan(range: NSRange(location: loc, length: len), kind: kind) }
private func sorted(_ spans: [MarkSpan]) -> [MarkSpan] {
    spans.sorted { ($0.range.location, $0.range.length) < ($1.range.location, $1.range.length) }
}

@Suite struct MarkdownStylerTests {
    struct BlockCase: CustomTestStringConvertible, Sendable {
        let line: String; let code: Bool; let block: BlockKind; let marker: Int?
        var testDescription: String { line.debugDescription }
    }

    static let blocks: [BlockCase] = [
        .init(line: "# Title", code: false, block: .heading(1), marker: 2),
        .init(line: "### H", code: false, block: .heading(3), marker: 4),
        .init(line: "#### H", code: false, block: .paragraph, marker: nil),
        .init(line: "- item", code: false, block: .bullet(indent: 0), marker: 2),
        .init(line: "\t- item", code: false, block: .bullet(indent: 1), marker: 3),
        .init(line: "  * item", code: false, block: .bullet(indent: 1), marker: 4),
        .init(line: "1. one", code: false, block: .numbered(indent: 0, number: 1), marker: 3),
        .init(line: "12. x", code: false, block: .numbered(indent: 0, number: 12), marker: 4),
        .init(line: "- [ ] task", code: false, block: .checklist(indent: 0, checked: false), marker: 6),
        .init(line: "- [x] done", code: false, block: .checklist(indent: 0, checked: true), marker: 6),
        .init(line: "- [X] done", code: false, block: .checklist(indent: 0, checked: true), marker: 6),
        .init(line: "> q", code: false, block: .quote, marker: 2),
        .init(line: "---", code: false, block: .rule, marker: 3),
        .init(line: "![](attachments/a.png)", code: false, block: .image(path: "attachments/a.png"), marker: 22),
        .init(line: "```swift", code: false, block: .fence, marker: 8),
        .init(line: "```", code: true, block: .fence, marker: 3),
        .init(line: "let *a*", code: true, block: .code, marker: nil),
        .init(line: "plain", code: false, block: .paragraph, marker: nil),
    ]

    @Test(arguments: blocks) func block(_ c: BlockCase) {
        let style = MarkdownStyler.parse(c.line, inCodeBlock: c.code)
        #expect(style.block == c.block)
        let firstMarker = style.spans.first { $0.kind == .marker && $0.range.location == 0 }
        #expect(firstMarker?.range.length == c.marker)
        if c.block == .code { #expect(style.spans.isEmpty) }
    }

    @Test func boldAndItalic() {
        #expect(sorted(MarkdownStyler.parse("**b** and *i*", inCodeBlock: false).spans) ==
                [s(0, 2, .marker), s(2, 1, .bold), s(3, 2, .marker), s(10, 1, .marker), s(11, 1, .italic), s(12, 1, .marker)])
    }

    @Test func strikeUnderlineHighlight() {
        #expect(sorted(MarkdownStyler.parse("~~s~~", inCodeBlock: false).spans) == [s(0, 2, .marker), s(2, 1, .strike), s(3, 2, .marker)])
        #expect(sorted(MarkdownStyler.parse("<u>u</u>", inCodeBlock: false).spans) == [s(0, 3, .marker), s(3, 1, .underline), s(4, 4, .marker)])
        #expect(sorted(MarkdownStyler.parse("==h==", inCodeBlock: false).spans) == [s(0, 2, .marker), s(2, 1, .highlight), s(3, 2, .marker)])
    }

    @Test func codeSpanHidesInnerMarkup() {
        #expect(sorted(MarkdownStyler.parse("`**x**`", inCodeBlock: false).spans) == [s(0, 1, .marker), s(1, 5, .code), s(6, 1, .marker)])
    }

    @Test func conceal() {
        #expect(sorted(MarkdownStyler.parse("||pw||", inCodeBlock: false).spans) == [s(0, 2, .marker), s(2, 2, .conceal), s(4, 2, .marker)])
    }

    @Test func links() {
        let url = URL(string: "https://x.com")!
        #expect(sorted(MarkdownStyler.parse("[t](https://x.com)", inCodeBlock: false).spans) ==
                [s(0, 1, .marker), s(1, 1, .link(url)), s(2, 16, .marker)])
        #expect(MarkdownStyler.parse("see https://x.com now", inCodeBlock: false).spans == [s(4, 13, .link(url))])
    }

    @Test(arguments: ["2 * 3 * 4", "snake_case_name", "**unclosed", "`", "", "a ~~ b", "[x](not a url)"])
    func notMarkdown(_ line: String) {
        #expect(MarkdownStyler.parse(line, inCodeBlock: false).spans.isEmpty)
    }

    @Test func utf16Offsets() {
        #expect(sorted(MarkdownStyler.parse("🙂 **b**", inCodeBlock: false).spans) == [s(3, 2, .marker), s(5, 1, .bold), s(6, 2, .marker)])
    }

    @Test func headingWithInline() {
        let spans = sorted(MarkdownStyler.parse("# **x**", inCodeBlock: false).spans)
        #expect(spans == [s(0, 2, .marker), s(2, 2, .marker), s(4, 1, .bold), s(5, 2, .marker)])
    }

    // Review I9: pathological long lines parse fast (no regex blow-up).
    @Test func longLineIsFast() {
        let line = String(repeating: "**x ", count: 25_000)
        let start = ContinuousClock.now
        _ = MarkdownStyler.parse(line, inCodeBlock: false)
        #expect(ContinuousClock.now - start < .milliseconds(200))
    }

    @Test func fenceDetection() {
        #expect(MarkdownStyler.isFence("```"))
        #expect(MarkdownStyler.isFence("  ```js"))
        #expect(!MarkdownStyler.isFence("a ```"))
    }
}
