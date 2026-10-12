import Foundation
import Observation

struct TaskItem: Identifiable, Equatable {
    let id: String
    var title: String
    var done: Bool
    var due: Date? = nil
}

/// Sunroof's own task list: markdown checkboxes in `Tasks.md` (also a normal note). Pure text transforms.
enum SunroofTasks {
    static let filename = "Tasks.md"
    private static let pattern = try! NSRegularExpression(pattern: #"^\s*[-*] \[([ xX])\] (.+)$"#)

    static func parse(_ text: String) -> [TaskItem] {
        text.components(separatedBy: "\n").enumerated().compactMap { i, line in
            let ns = line as NSString
            guard let m = pattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
            return TaskItem(id: "line:\(i)", title: ns.substring(with: m.range(at: 2)), done: ns.substring(with: m.range(at: 1)) != " ")
        }
    }

    /// Ticks/unticks one line; every other line is untouched.
    static func toggling(_ id: String, in text: String) -> String {
        guard let i = Int(id.replacingOccurrences(of: "line:", with: "")) else { return text }
        let lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(i) else { return text }
        let offset = lines[..<i].reduce(0) { $0 + ($1 as NSString).length + 1 }
        return ListEditing.toggleCheckbox(lineContaining: offset, in: text)
    }

    /// Adds an unticked task after the last task line (or starts the list).
    static func adding(_ title: String, to text: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return text }
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        let new = "- [ ] \(t)"
        if let last = lines.indices.last(where: { i in
            let ns = lines[i] as NSString
            return pattern.firstMatch(in: lines[i], range: NSRange(location: 0, length: ns.length)) != nil
        }) {
            lines.insert(new, at: last + 1)
            return lines.joined(separator: "\n")
        }
        if lines.isEmpty { return "Tasks\n\n\(new)" }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n\n" + new
    }
}

/// Live view of `Tasks.md` through the NoteStore (so edits elsewhere show up and saving/sync rules apply).
@MainActor @Observable
final class SunroofTasksSource {
    @ObservationIgnored let store: NoteStore

    init(store: NoteStore) { self.store = store }

    private var text: String { store.note(SunroofTasks.filename)?.text ?? "" }
    var tasks: [TaskItem] { SunroofTasks.parse(text) }

    func toggle(_ id: String) {
        guard store.note(SunroofTasks.filename) != nil else { return }
        store.update(SunroofTasks.filename, text: SunroofTasks.toggling(id, in: text))
    }

    /// False when `Tasks.md` exists but can't be read (it's left alone).
    @discardableResult func add(_ title: String) -> Bool {
        guard store.ensureNote(SunroofTasks.filename, text: "Tasks") else { return false }
        store.update(SunroofTasks.filename, text: SunroofTasks.adding(title, to: text))
        return true
    }
}
