import Foundation

/// File URL with no trailing slash, so URLs for the same item always compare equal
/// (`appendingPathComponent` adds a slash when the folder already exists).
func canonical(_ url: URL) -> URL { URL(filePath: url.standardizedFileURL.path, directoryHint: .notDirectory) }

enum ArrangeBy: String, CaseIterable { case name, kind, dateAdded, dateModified }

struct DrawerItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let isDirectory: Bool // packages (.app, .rtfd) count as files
    let kind: String
    let dateAdded: Date
    let dateModified: Date
    let size: Int64?

    static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .localizedTypeDescriptionKey,
                                             .addedToDirectoryDateKey, .contentModificationDateKey, .fileSizeKey,
                                             .localizedNameKey]

    static func load(_ url: URL) -> DrawerItem? {
        guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
        let dir = (v.isDirectory ?? false) && !(v.isPackage ?? false)
        let now = Date.now
        return DrawerItem(url: canonical(url), name: url.lastPathComponent, isDirectory: dir,
                          kind: v.localizedTypeDescription ?? "", dateAdded: date(v.addedToDirectoryDate, now: now),
                          dateModified: date(v.contentModificationDate, now: now), size: v.fileSize.map(Int64.init))
    }

    /// Missing dates (exFAT, SMB, some cloud folders) count as "now" so cleanup never treats them as old.
    static func date(_ d: Date?, now: Date) -> Date { d ?? now }
}

func sortItems(_ items: [DrawerItem], by arrange: ArrangeBy, foldersOnTop: Bool) -> [DrawerItem] {
    func byName(_ a: DrawerItem, _ b: DrawerItem) -> Bool { a.name.localizedStandardCompare(b.name) == .orderedAscending }
    let sorted = items.sorted { a, b in
        switch arrange {
        case .name: return byName(a, b)
        case .kind: return a.kind == b.kind ? byName(a, b) : a.kind.localizedStandardCompare(b.kind) == .orderedAscending
        case .dateAdded: return a.dateAdded == b.dateAdded ? byName(a, b) : a.dateAdded > b.dateAdded
        case .dateModified: return a.dateModified == b.dateModified ? byName(a, b) : a.dateModified > b.dateModified
        }
    }
    guard foldersOnTop else { return sorted }
    return sorted.filter(\.isDirectory) + sorted.filter { !$0.isDirectory }
}

/// ⇧-click: everything between the anchor (last plain/⌘ click) and the target, in display order.
func rangeSelection(_ ids: [URL], anchor: URL?, target: URL) -> Set<URL> {
    guard let anchor, let a = ids.firstIndex(of: anchor), let t = ids.firstIndex(of: target) else { return [target] }
    return Set(ids[min(a, t)...max(a, t)])
}
