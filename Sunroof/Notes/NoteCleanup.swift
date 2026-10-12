import Foundation

/// "Clean Up Note": turns plain-text notes (pasted, imported from Unclutter…) into tidy markdown.
/// Pure and idempotent. The title line, code blocks and quotes are left alone.
enum NoteCleanup {
    private static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    private static let checkbox = re(#"^(?:[-*•·]\s*)?(\[ \]|\[[xX]\]|☐|☑|☒|✓|✔|✅)\s*(.*)$"#)
    private static let bullet = re(#"^[•·*–—▪◦○●➤►‣⁃-]\s+(.*)$"#)
    private static let numbered = re(#"^(?:\(\w{1,4}\)|\d{1,3}[.)]|(?:[a-zA-Z]|[ivxIVX]{1,4})\))\s+(.*)$"#)
    private static let label = re(#"^([A-Z][A-Za-z0-9'’&/ ()-]{0,39}):\s+(\S.*)$"#)
    /// "Marc - text": up to 3 words, capitalised, then a spaced hyphen/en/em dash.
    private static let dashLabel = re(#"^([A-Z][A-Za-z0-9'’&/()]*(?: [A-Za-z0-9'’&/()]+){0,2}) ([-–—]) (\S.*)$"#)
    private static let divider = re(#"^[-–—_=]{3,}$"#)

    static func clean(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else { return text }
        var out: [String] = []
        // A short first line is the note's title and stays as it is; a long one is a paragraph, cleaned like the rest.
        if lines[0].count <= 60 { out.append(trimEnd(lines.removeFirst())) }
        var inFence = false
        var counters: [Int: Int] = [:] // numbering per indent level

        for raw in lines {
            let line = trimEnd(raw)
            let body = line.drop { $0 == " " || $0 == "\t" }
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            let level = indent.filter { $0 == "\t" }.count + indent.filter { $0 == " " }.count / 2
            let pad = String(repeating: "  ", count: level)
            let b = String(body)

            if b.hasPrefix("```") { inFence.toggle(); out.append(line); continue }
            if inFence || b.isEmpty { out.append(line); continue }

            if match(divider, b) != nil {
                out.append("---")
                counters = [:]
            } else if let m = match(checkbox, b) {
                let done = m[0] != "[ ]" && m[0] != "☐"
                out.append(pad + (done ? "- [x] " : "- [ ] ") + m[1])
                counters = counters.filter { $0.key < level }
            } else if let m = match(bullet, b) {
                out.append(pad + "- " + bold(m[0]))
                counters = counters.filter { $0.key < level }
            } else if let m = match(numbered, b) {
                let n = (counters[level] ?? 0) + 1
                counters = counters.filter { $0.key < level }
                counters[level] = n
                out.append(pad + "\(n). " + bold(m[0]))
            } else if level == 0, out.last?.isEmpty == true, isHeading(b) {
                out.append("## " + (b.hasSuffix(":") ? String(b.dropLast()) : b))
                counters = [:]
            } else {
                out.append(pad + bold(b))
                counters = [:]
            }
        }
        // Collapse runs of blank lines to one.
        return out.enumerated().filter { i, l in !(l.isEmpty && i > 0 && out[i - 1].isEmpty) }.map(\.1).joined(separator: "\n")
    }

    /// A short line on its own that ends with ":" ("Groceries:") or is in capitals ("TODAY").
    private static func isHeading(_ s: String) -> Bool {
        guard s.count <= 60, !s.hasPrefix("#"), !s.hasPrefix(">"), !s.hasPrefix("*"), !s.hasPrefix("|") else { return false }
        let words = s.split(separator: " ").count
        if s.hasSuffix(":") { return words <= 6 && !s.dropLast().contains(":") }
        let letters = s.filter(\.isLetter)
        return letters.count >= 3 && letters.allSatisfy(\.isUppercase) && words <= 8 && !s.hasSuffix(".")
    }

    /// "Name: John" → "**Name:** John" (labels of up to 4 words); "Marc - text" → "**Marc** - text".
    private static func bold(_ s: String) -> String {
        if let m = match(label, s), m[0].split(separator: " ").count <= 4 { return "**\(m[0]):** \(m[1])" }
        if let m = match(dashLabel, s) { return "**\(m[0])** \(m[1]) \(m[2])" }
        return s
    }

    private static func match(_ r: NSRegularExpression, _ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = r.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    private static func trimEnd(_ s: String) -> String {
        var s = s
        while s.last == " " || s.last == "\t" || s.last == "\r" { s.removeLast() }
        return s
    }
}
