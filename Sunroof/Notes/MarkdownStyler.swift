import Foundation

enum BlockKind: Equatable, Hashable, Sendable {
    case paragraph, heading(Int), bullet(indent: Int), numbered(indent: Int, number: Int)
    case checklist(indent: Int, checked: Bool), quote, fence, code, rule, image(path: String)
}

enum SpanKind: Equatable, Hashable, Sendable { case marker, bold, italic, strike, underline, highlight, code, conceal, link(URL) }

/// A styled range inside one line, in UTF-16 offsets.
struct MarkSpan: Equatable, Hashable, Sendable {
    var range: NSRange
    var kind: SpanKind
}

struct LineStyle: Equatable, Sendable {
    var block: BlockKind
    var spans: [MarkSpan]
}

/// Parses one line of markdown into a block kind plus inline spans. Never changes text; only describes it.
enum MarkdownStyler {
    static func isFence(_ line: String) -> Bool {
        line.drop { $0 == " " || $0 == "\t" }.hasPrefix("```")
    }

    static func parse(_ line: String, inCodeBlock: Bool) -> LineStyle {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        if isFence(line) { return LineStyle(block: .fence, spans: [MarkSpan(range: full, kind: .marker)]) }
        if inCodeBlock { return LineStyle(block: .code, spans: []) }

        let (block, markerLength) = blockKind(line)
        var spans: [MarkSpan] = markerLength > 0 ? [MarkSpan(range: NSRange(location: 0, length: markerLength), kind: .marker)] : []
        if case .image = block { return LineStyle(block: block, spans: spans) }
        if block == .rule { return LineStyle(block: block, spans: spans) }
        spans += inline(ns, from: markerLength)
        return LineStyle(block: block, spans: spans)
    }

    // MARK: - Blocks

    private static let heading = try! NSRegularExpression(pattern: "^(#{1,3}) ")
    private static let checklist = try! NSRegularExpression(pattern: "^[-*] \\[([ xX])\\] ")
    private static let bullet = try! NSRegularExpression(pattern: "^[-*] ")
    private static let numbered = try! NSRegularExpression(pattern: "^(\\d{1,9})\\. ")
    private static let image = try! NSRegularExpression(pattern: "^!\\[[^\\]]*\\]\\(([^)\\s]+)\\)$")

    /// Block kind and the length of its leading marker (including indent).
    private static func blockKind(_ line: String) -> (BlockKind, Int) {
        let ns = line as NSString
        var i = 0, tabs = 0, spaces = 0
        while i < ns.length {
            let c = ns.character(at: i)
            if c == 9 { tabs += 1 } else if c == 32 { spaces += 1 } else { break }
            i += 1
        }
        let level = tabs + spaces / 2
        let rest = ns.substring(from: i)
        let restNS = rest as NSString
        let r = NSRange(location: 0, length: restNS.length)

        if i == 0 {
            if rest == "---" { return (.rule, 3) }
            if let m = image.firstMatch(in: rest, range: r) { return (.image(path: restNS.substring(with: m.range(at: 1))), ns.length) }
            if let m = heading.firstMatch(in: rest, range: r) { return (.heading(m.range(at: 1).length), m.range.length) }
            if rest.hasPrefix("> ") { return (.quote, 2) }
        }
        if let m = checklist.firstMatch(in: rest, range: r) {
            return (.checklist(indent: level, checked: restNS.substring(with: m.range(at: 1)) != " "), i + m.range.length)
        }
        if bullet.firstMatch(in: rest, range: r) != nil { return (.bullet(indent: level), i + 2) }
        if let m = numbered.firstMatch(in: rest, range: r) {
            return (.numbered(indent: level, number: Int(restNS.substring(with: m.range(at: 1))) ?? 1), i + m.range.length)
        }
        return (.paragraph, 0)
    }

    // MARK: - Inline

    /// (regex, kind, opening marker length, closing marker length). Order matters: earlier kinds claim their markers first.
    private static let inlineRules: [(NSRegularExpression, SpanKind, Int, Int)] = [
        (try! NSRegularExpression(pattern: "\\|\\|(?=\\S)(.{1,1000}?)(?<=\\S)\\|\\|"), .conceal, 2, 2),
        (try! NSRegularExpression(pattern: "\\*\\*(?=\\S)(.{1,1000}?)(?<=\\S)\\*\\*"), .bold, 2, 2),
        (try! NSRegularExpression(pattern: "(?<![\\w])__(?=\\S)(.{1,1000}?)(?<=\\S)__(?![\\w])"), .bold, 2, 2),
        (try! NSRegularExpression(pattern: "~~(?=\\S)(.{1,1000}?)(?<=\\S)~~"), .strike, 2, 2),
        (try! NSRegularExpression(pattern: "<u>(.{1,1000}?)</u>"), .underline, 3, 4),
        (try! NSRegularExpression(pattern: "==(?=\\S)(.{1,1000}?)(?<=\\S)=="), .highlight, 2, 2),
        (try! NSRegularExpression(pattern: "(?<![*\\w])\\*(?=[^\\s*])(.{1,1000}?)(?<=[^\\s*])\\*(?!\\*)"), .italic, 1, 1),
        (try! NSRegularExpression(pattern: "(?<![\\w_])_(?=[^\\s_])(.{1,1000}?)(?<=[^\\s_])_(?![\\w_])"), .italic, 1, 1),
    ]
    private static let codeSpan = try! NSRegularExpression(pattern: "`([^`]+)`")
    private static let link = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)\\s]+)\\)")
    private static let bareURL = try! NSRegularExpression(pattern: "https?://[^\\s<>()]+")

    static let maxInlineLength = 5_000 // longer lines (minified/base64 pastes) get no inline styling

    private static func inline(_ ns: NSString, from start: Int) -> [MarkSpan] {
        let range = NSRange(location: start, length: ns.length - start)
        guard range.length > 0, ns.length <= maxInlineLength else { return [] }
        var spans: [MarkSpan] = []
        var opaque: [NSRange] = []   // code spans and links: nothing else inside
        var markers: [NSRange] = []  // claimed delimiter ranges
        func free(_ r: NSRange, _ list: [NSRange]) -> Bool { !list.contains { NSIntersectionRange($0, r).length > 0 } }

        for m in codeSpan.matches(in: ns as String, range: range) {
            opaque.append(m.range)
            spans += [MarkSpan(range: NSRange(location: m.range.location, length: 1), kind: .marker),
                      MarkSpan(range: m.range(at: 1), kind: .code),
                      MarkSpan(range: NSRange(location: NSMaxRange(m.range) - 1, length: 1), kind: .marker)]
        }
        for m in link.matches(in: ns as String, range: range) where free(m.range, opaque) {
            guard let url = URL(string: ns.substring(with: m.range(at: 2))), url.scheme != nil else { continue }
            opaque.append(m.range)
            let text = m.range(at: 1)
            spans += [MarkSpan(range: NSRange(location: m.range.location, length: 1), kind: .marker),
                      MarkSpan(range: text, kind: .link(url)),
                      MarkSpan(range: NSRange(location: NSMaxRange(text), length: NSMaxRange(m.range) - NSMaxRange(text)), kind: .marker)]
        }
        for m in bareURL.matches(in: ns as String, range: range) where free(m.range, opaque) {
            guard let url = URL(string: ns.substring(with: m.range)) else { continue }
            opaque.append(m.range)
            spans.append(MarkSpan(range: m.range, kind: .link(url)))
        }
        for (regex, kind, open, close) in inlineRules {
            for m in regex.matches(in: ns as String, range: range) {
                let o = NSRange(location: m.range.location, length: open)
                let c = NSRange(location: NSMaxRange(m.range) - close, length: close)
                guard free(m.range, opaque), free(o, markers), free(c, markers) else { continue }
                markers += [o, c]
                spans += [MarkSpan(range: o, kind: .marker), MarkSpan(range: m.range(at: 1), kind: kind),
                          MarkSpan(range: c, kind: .marker)]
            }
        }
        return spans
    }
}
