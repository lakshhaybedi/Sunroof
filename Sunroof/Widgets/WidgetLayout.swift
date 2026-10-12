import Foundation

struct WidgetItem: Codable, Equatable {
    var kind: WidgetKind
    var size: WidgetSize
}

struct WidgetPlacement: Equatable {
    let item: WidgetItem
    let x: Int
    let y: Int
}

/// The widget band's contents: an ordered list packed first-fit in reading order (like a phone home screen).
/// Dragging reorders, resizing re-packs, nothing overlaps; items that don't fit stay in the list, hidden.
struct WidgetLayout: Codable, Equatable {
    var items: [WidgetItem]

    static let `default` = WidgetLayout(items: [
        .init(kind: .calendar, size: .large), .init(kind: .weather, size: .medium), .init(kind: .music, size: .medium),
        .init(kind: .tasks, size: .medium), .init(kind: .stats, size: .small),
    ])

    func pack(columns: Int, rows: Int) -> (placed: [WidgetPlacement], hidden: [WidgetItem]) {
        guard columns > 0, rows > 0 else { return ([], items) }
        var used = Array(repeating: Array(repeating: false, count: columns), count: rows)
        var placed: [WidgetPlacement] = [], hidden: [WidgetItem] = []
        func free(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Bool {
            guard x + w <= columns, y + h <= rows else { return false }
            return (y..<y + h).allSatisfy { r in (x..<x + w).allSatisfy { !used[r][$0] } }
        }
        for var item in items {
            // Too tall for the band (a Large in one row): show it at the biggest size that fits.
            if item.size.span.h > rows, let fit = item.kind.allowedSizes.last(where: { $0.span.h <= rows }) { item.size = fit }
            let (w, h) = item.size.span
            var spot: (Int, Int)?
            search: for y in 0..<rows { for x in 0..<columns where free(x, y, w, h) { spot = (x, y); break search } }
            guard let (x, y) = spot else { hidden.append(item); continue }
            for r in y..<y + h { for c in x..<x + w { used[r][c] = true } }
            placed.append(WidgetPlacement(item: item, x: x, y: y))
        }
        return (placed, hidden)
    }

    mutating func move(_ kind: WidgetKind, toIndex index: Int) {
        guard let from = items.firstIndex(where: { $0.kind == kind }) else { return }
        let item = items.remove(at: from)
        items.insert(item, at: max(0, min(index, items.count)))
    }

    mutating func resize(_ kind: WidgetKind, to size: WidgetSize) {
        guard kind.allowedSizes.contains(size), let i = items.firstIndex(where: { $0.kind == kind }) else { return }
        items[i].size = size
    }

    mutating func add(_ kind: WidgetKind) {
        guard !items.contains(where: { $0.kind == kind }) else { return }
        items.append(WidgetItem(kind: kind, size: kind.defaultSize))
    }

    mutating func remove(_ kind: WidgetKind) { items.removeAll { $0.kind == kind } }

    var available: [WidgetKind] { WidgetKind.allCases.filter { k in !items.contains { $0.kind == k } } }
}
