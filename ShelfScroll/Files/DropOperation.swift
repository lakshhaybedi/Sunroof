import AppKit

/// What a drop into the drawer does, matching Finder: plain = move, ⌥ = copy, ⌘⌥ = alias.
enum DropOperation: Equatable {
    case move, copy, alias

    static func from(_ flags: NSEvent.ModifierFlags) -> DropOperation {
        if flags.contains(.option) { return flags.contains(.command) ? .alias : .copy }
        return .move
    }
}

/// Finder-style free name in `dir`: "a.txt", then "a 2.txt", "a 3.txt", …
func uniqueDestination(for name: String, in dir: URL) -> URL {
    let fm = FileManager.default
    var url = dir.appendingPathComponent(name)
    guard fm.fileExists(atPath: url.path) else { return url }
    let ext = (name as NSString).pathExtension
    let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
    var n = 2
    repeat {
        url = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
        n += 1
    } while fm.fileExists(atPath: url.path)
    return url
}

/// Moves, copies or aliases `source` into `dir` under a free name. Moving a file onto its own folder is a no-op.
@discardableResult
func perform(_ op: DropOperation, _ source: URL, into dir: URL) throws -> URL {
    let fm = FileManager.default
    if op == .move, source.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL { return source }
    let dest = uniqueDestination(for: source.lastPathComponent, in: dir)
    switch op {
    case .move: try fm.moveItem(at: source, to: dest)
    case .copy: try fm.copyItem(at: source, to: dest)
    case .alias:
        let data = try source.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(data, to: dest)
    }
    return dest
}
