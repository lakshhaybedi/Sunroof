import Foundation

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
        return DrawerItem(url: url, name: url.lastPathComponent, isDirectory: dir,
                          kind: v.localizedTypeDescription ?? "", dateAdded: v.addedToDirectoryDate ?? .distantPast,
                          dateModified: v.contentModificationDate ?? .distantPast, size: v.fileSize.map(Int64.init))
    }
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
