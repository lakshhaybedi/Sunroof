import Foundation

struct TextEdit: Equatable {
    var text: String
    var selection: NSRange
}

enum BlockChange { case heading(Int), bullet, numbered, checklist, quote }

/// Pure editing rules for lists, checkboxes and formatting. Offsets are UTF-16.
enum ListEditing {

    // MARK: - Line helpers

    private struct Lines {
        var lines: [String]
        init(_ text: String) { lines = text.components(separatedBy: "\n") }
        var text: String { lines.joined(separator: "\n") }
        func start(_ i: Int) -> Int { lines[..<i].reduce(0) { $0 + ($1 as NSString).length + 1 } }
        func end(_ i: Int) -> Int { start(i) + (lines[i] as NSString).length }
        func index(at location: Int) -> Int {
            var pos = 0
            for (i, l) in lines.enumerated() {
                let len = (l as NSString).length
                if location <= pos + len { return i }
                pos += len + 1
            }
            return lines.count - 1
        }
        func range(_ sel: NSRange) -> ClosedRange<Int> {
            index(at: sel.location)...index(at: sel.length > 0 ? NSMaxRange(sel) - 1 : sel.location)
        }
    }

    private struct Prefix {
        var block: BlockKind
        var length: Int      // marker length incl. indent
        var indent: String
        var isList: Bool {
            switch block { case .bullet, .numbered, .checklist: true; default: false }
        }
    }

    private static func prefix(_ line: String) -> Prefix {
        let style = MarkdownStyler.parse(line, inCodeBlock: false)
        let marker = style.spans.first { $0.kind == .marker && $0.range.location == 0 }?.range.length ?? 0
        let indent = String(line.prefix { $0 == "\t" || $0 == " " })
        switch style.block {
        case .bullet, .numbered, .checklist, .quote, .heading: return Prefix(block: style.block, length: marker, indent: indent)
        default: return Prefix(block: .paragraph, length: 0, indent: "")
        }
    }

    private static func bulletChar(_ line: String) -> String {
        line.drop { $0 == "\t" || $0 == " " }.first == "*" ? "*" : "-"
    }

    // MARK: - Newline

    static func newline(_ t: TextEdit) -> TextEdit? {
        guard t.selection.length == 0 else { return nil }
        var l = Lines(t.text)
        let i = l.index(at: t.selection.location)
        let line = l.lines[i]
        let p = prefix(line)
        let continuation: String
        switch p.block {
        case .bullet: continuation = p.indent + bulletChar(line) + " "
        case .checklist: continuation = p.indent + bulletChar(line) + " [ ] "
        case let .numbered(_, n): continuation = p.indent + "\(n + 1). "
        case .quote: continuation = "> "
        default: return nil
        }
        let ns = line as NSString
        if ns.substring(from: p.length).trimmingCharacters(in: .whitespaces).isEmpty {
            l.lines[i] = "" // empty item ends the list
            return TextEdit(text: l.text, selection: NSRange(location: l.start(i), length: 0))
        }
        let col = max(t.selection.location - l.start(i), p.length)
        l.lines[i] = ns.substring(to: col)
        l.lines.insert(continuation + ns.substring(from: col), at: i + 1)
        let text = renumber(l.text)
        let nl = Lines(text)
        return TextEdit(text: text, selection: NSRange(location: nl.start(i + 1) + prefix(nl.lines[i + 1]).length, length: 0))
    }

    // MARK: - Indent

    static func indent(_ t: TextEdit, outdent: Bool) -> TextEdit? {
        var l = Lines(t.text)
        let rows = l.range(t.selection)
        guard rows.contains(where: { prefix(l.lines[$0]).isList }) else { return nil }
        let caretRow = l.index(at: t.selection.location)
        let fromEnd = l.end(caretRow) - t.selection.location
        for r in rows where prefix(l.lines[r]).isList {
            let line = l.lines[r]
            if !outdent { l.lines[r] = "\t" + line }
            else if line.hasPrefix("\t") { l.lines[r] = String(line.dropFirst()) }
            else if line.hasPrefix("  ") { l.lines[r] = String(line.dropFirst(2)) }
        }
        let text = renumber(l.text)
        let nl = Lines(text)
        if t.selection.length == 0 {
            return TextEdit(text: text, selection: NSRange(location: nl.end(caretRow) - fromEnd, length: 0))
        }
        let s = nl.start(rows.lowerBound)
        return TextEdit(text: text, selection: NSRange(location: s, length: nl.end(rows.upperBound) - s))
    }

    // MARK: - Renumber

    static func renumber(_ text: String) -> String {
        var l = Lines(text)
        var counters: [Int: Int] = [:] // indent level → next number
        for i in l.lines.indices {
            let line = l.lines[i]
            let p = prefix(line)
            switch p.block {
            case let .numbered(level, own):
                // Top-level lists keep their starting number (e.g. "5."); nested runs restart at 1.
                let n = counters[level] ?? (level == 0 ? own : 1)
                counters[level] = n + 1
                counters = counters.filter { $0.key <= level }
                let rest = (line as NSString).substring(from: p.length)
                l.lines[i] = p.indent + "\(n). " + rest
            case let .bullet(level), let .checklist(level, _):
                counters = counters.filter { $0.key < level }
            default:
                counters.removeAll()
            }
        }
        return l.text
    }

    // MARK: - Checkbox

    static func toggleCheckbox(lineContaining location: Int, in text: String) -> String {
        var l = Lines(text)
        let i = l.index(at: location)
        let line = l.lines[i]
        guard case let .checklist(_, checked) = prefix(line).block else { return text }
        let ns = line as NSString
        let box = ns.range(of: checked ? "[x]" : "[ ]", options: .caseInsensitive)
        guard box.location != NSNotFound else { return text }
        l.lines[i] = ns.replacingCharacters(in: box, with: checked ? "[ ]" : "[x]")
        return l.text
    }

    // MARK: - Move line

    static func moveLine(_ t: TextEdit, up: Bool) -> TextEdit {
        var l = Lines(t.text)
        let i = l.index(at: t.selection.location)
        let j = up ? i - 1 : i + 1
        guard l.lines.indices.contains(j) else { return t }
        let fromEnd = l.end(i) - t.selection.location
        let (pi, pj) = (prefix(l.lines[i]), prefix(l.lines[j]))
        l.lines.swapAt(i, j)
        // Numbered items at the same level swap content, not numbers.
        if case let .numbered(a, _) = pi.block, case let .numbered(b, _) = pj.block, a == b {
            let (li, lj) = (l.lines[j] as NSString, l.lines[i] as NSString) // li = moved line, now at j
            l.lines[j] = lj.substring(to: pj.length) + li.substring(from: pi.length)
            l.lines[i] = li.substring(to: pi.length) + lj.substring(from: pj.length)
        }
        let text = renumber(l.text)
        let nl = Lines(text)
        return TextEdit(text: text, selection: NSRange(location: max(nl.start(j), nl.end(j) - fromEnd), length: 0))
    }

    // MARK: - Inline formatting

    static func toggleInline(_ t: TextEdit, open: String, close: String) -> TextEdit {
        let ns = t.text as NSString
        let sel = t.selection
        let o = (open as NSString).length, c = (close as NSString).length
        if sel.location >= o, NSMaxRange(sel) + c <= ns.length,
           ns.substring(with: NSRange(location: sel.location - o, length: o)) == open,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: c)) == close {
            let m = NSMutableString(string: t.text)
            m.deleteCharacters(in: NSRange(location: NSMaxRange(sel), length: c))
            m.deleteCharacters(in: NSRange(location: sel.location - o, length: o))
            return TextEdit(text: m as String, selection: NSRange(location: sel.location - o, length: sel.length))
        }
        let inner = ns.substring(with: sel)
        if sel.length >= o + c, inner.hasPrefix(open), inner.hasSuffix(close) {
            let stripped = (inner as NSString).substring(with: NSRange(location: o, length: sel.length - o - c))
            return TextEdit(text: ns.replacingCharacters(in: sel, with: stripped),
                            selection: NSRange(location: sel.location, length: (stripped as NSString).length))
        }
        return TextEdit(text: ns.replacingCharacters(in: sel, with: open + inner + close),
                        selection: NSRange(location: sel.location + o, length: sel.length))
    }

    // MARK: - Block formatting

    static func toggleBlock(_ t: TextEdit, _ change: BlockChange) -> TextEdit {
        var l = Lines(t.text)
        let rows = l.range(t.selection)
        func matches(_ b: BlockKind) -> Bool {
            switch (change, b) {
            case let (.heading(n), .heading(m)): n == m
            case (.bullet, .bullet), (.numbered, .numbered), (.checklist, .checklist), (.quote, .quote): true
            default: false
            }
        }
        let remove = rows.allSatisfy { matches(prefix(l.lines[$0]).block) }
        let caretRow = l.index(at: t.selection.location)
        var caretDelta = 0
        for (k, r) in rows.enumerated() {
            let line = l.lines[r]
            let p = prefix(line)
            let content = (line as NSString).substring(from: p.length)
            let marker: String
            if remove { marker = "" } else {
                switch change {
                case let .heading(n): marker = String(repeating: "#", count: n) + " "
                case .bullet: marker = "- "
                case .numbered: marker = "\(k + 1). "
                case .checklist: marker = "- [ ] "
                case .quote: marker = "> "
                }
            }
            let keepIndent: String = {
                if case .heading = change { return "" }
                if change == .quote { return "" }
                return p.indent
            }()
            l.lines[r] = (remove ? p.indent : keepIndent) + marker + content
            if r == caretRow { caretDelta = (l.lines[r] as NSString).length - (line as NSString).length }
        }
        let text = renumber(l.text)
        let nl = Lines(text)
        if t.selection.length == 0 {
            let floor = nl.start(caretRow) + prefix(nl.lines[caretRow]).length
            return TextEdit(text: text, selection: NSRange(location: max(floor, t.selection.location + caretDelta), length: 0))
        }
        let s = nl.start(rows.lowerBound)
        return TextEdit(text: text, selection: NSRange(location: s, length: nl.end(rows.upperBound) - s))
    }

    // MARK: - Shortcuts

    /// After typing a space: "[] " at the start of a line becomes "- [ ] ".
    static func expandShortcut(_ t: TextEdit) -> TextEdit? {
        guard t.selection.length == 0 else { return nil }
        var l = Lines(t.text)
        let i = l.index(at: t.selection.location)
        let line = l.lines[i]
        let indent = String(line.prefix { $0 == "\t" || $0 == " " })
        let typed = indent + "[] "
        guard line.hasPrefix(typed), t.selection.location == l.start(i) + (typed as NSString).length else { return nil }
        l.lines[i] = indent + "- [ ] " + line.dropFirst(typed.count)
        return TextEdit(text: l.text, selection: NSRange(location: t.selection.location + 3, length: 0))
    }
}

extension BlockChange: Equatable {}
