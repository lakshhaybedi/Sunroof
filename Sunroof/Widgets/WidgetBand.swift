import SwiftUI

/// The snap-grid band of widgets at the bottom of the shelf.
struct WidgetBand: View {
    @Bindable var host: WidgetHost
    /// Builds each widget's content for its size (the per-widget views).
    let content: (WidgetKind, WidgetSize) -> AnyView
    @State private var showGallery = false
    @State private var dragRows: Int?
    /// The tile being dragged to a new place, and how far it has moved.
    @State private var dragging: WidgetKind?
    @State private var dragOffset: CGSize = .zero

    private let cell = ShelfController.widgetCell
    private var rows: Int { dragRows ?? max(1, min(host.settings.widgetRows, 4)) }

    var body: some View {
        VStack(spacing: 0) {
            rowsGrip
            GeometryReader { geo in
                let columns = max(1, Int((geo.size.width - 8) / cell))
                // Cells stretch so the widgets fill the full width.
                let grid = Grid(width: (geo.size.width - 8) / CGFloat(columns), height: cell)
                let packed = host.layout.pack(columns: columns, rows: rows)
                ZStack(alignment: .topLeading) {
                    ForEach(packed.placed, id: \.item.kind) { p in tile(p, grid: grid, placed: packed.placed) }
                    addButton(columns: columns, packed: packed, grid: grid)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .coordinateSpace(.named("widgets"))
                .padding(.leading, 8)
                .animation(.smooth(duration: 0.25), value: host.layout)
                .onChange(of: columns, initial: true) { host.restartIfRunning(columns: columns) }
            }
        }
        .onChange(of: host.settings.widgetRows) { host.restartIfRunning() }
        .onChange(of: host.settings.showWidgets) { host.restartIfRunning() }
        .tint(host.settings.accent.color)
    }

    // MARK: - Pieces

    /// Drag up/down to add or remove rows.
    private var rowsGrip: some View {
        Capsule().fill(Color.secondary.opacity(0.5))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity, minHeight: 6)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { v in
                    let base = max(1, min(host.settings.widgetRows, 4))
                    dragRows = max(1, min(4, base + Int((-v.translation.height / cell).rounded())))
                }
                .onEnded { _ in
                    if let r = dragRows { host.settings.widgetRows = r }
                    dragRows = nil
                })
            .help("Drag to add or remove widget rows")
    }

    private struct Grid { let width: CGFloat; let height: CGFloat }

    private func rect(_ p: WidgetPlacement, _ g: Grid) -> CGRect {
        let (w, h) = p.item.size.span
        return CGRect(x: CGFloat(p.x) * g.width, y: CGFloat(p.y) * g.height, width: CGFloat(w) * g.width, height: CGFloat(h) * g.height)
    }

    private func tile(_ p: WidgetPlacement, grid: Grid, placed: [WidgetPlacement]) -> some View {
        let kind = p.item.kind
        let r = rect(p, grid)
        let lifted = dragging == kind
        return content(kind, p.item.size)
            .background(kind.tint.map { c in
                LinearGradient(colors: [c.opacity(0.32), c.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
            })
            .frame(width: r.width - 8, height: r.height - 8)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .glassEffect(.regular, in: .rect(cornerRadius: 18)) // the same Liquid Glass as the shelf: blurs what's behind
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .contextMenu {
                Menu("Size") {
                    ForEach(kind.allowedSizes, id: \.self) { size in
                        Button { host.layout.resize(kind, to: size) } label: {
                            if size == p.item.size { Label(size.title, systemImage: "checkmark") } else { Text(size.title) }
                        }
                    }
                }
                Button("Widget Settings…") { host.openSettings() }
                Button("Hide Widgets") { host.settings.showWidgets = false }
                Divider()
                Button("Remove Widget", role: .destructive) { host.layout.remove(kind) }
            }
            // Drag a widget onto another to take its place; the rest reflow.
            .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("widgets"))
                .onChanged { v in dragging = kind; dragOffset = v.translation }
                .onEnded { v in
                    if let target = placed.first(where: { $0.item.kind != kind && rect($0, grid).contains(v.location) }),
                       let index = host.layout.items.firstIndex(where: { $0.kind == target.item.kind }) {
                        host.layout.move(kind, toIndex: index)
                    }
                    withAnimation(.smooth(duration: 0.25)) { dragging = nil; dragOffset = .zero }
                })
            .scaleEffect(lifted ? 1.04 : 1)
            .shadow(color: .black.opacity(lifted ? 0.3 : 0), radius: 16, y: 8)
            .offset(x: r.minX + (lifted ? dragOffset.width : 0), y: r.minY + (lifted ? dragOffset.height : 0))
            .zIndex(lifted ? 1 : 0)
    }

    /// ＋ in the first free cell (or the band's top-right corner when full) opens the gallery.
    private func addButton(columns: Int, packed: (placed: [WidgetPlacement], hidden: [WidgetItem]), grid: Grid) -> some View {
        let spot = firstFreeCell(columns: columns, placed: packed.placed)
        return Button { showGallery = true } label: {
            Image(systemName: "plus").font(.title2).foregroundStyle(.secondary)
                .frame(width: spot == nil ? 28 : grid.width - 8, height: spot == nil ? 28 : cell - 8)
                .background(RoundedRectangle(cornerRadius: spot == nil ? 8 : 18)
                    .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(.hit)
        .help("Add a widget")
        .popover(isPresented: $showGallery, arrowEdge: .top) { gallery } // anchored to the ＋ itself, opening above it
        .offset(x: spot.map { CGFloat($0.0) * grid.width } ?? CGFloat(columns) * grid.width - 36,
                y: spot.map { CGFloat($0.1) * cell } ?? 0)
        .opacity(host.layout.available.isEmpty && spot == nil ? 0 : 1)
    }

    private func firstFreeCell(columns: Int, placed: [WidgetPlacement]) -> (Int, Int)? {
        guard !host.layout.available.isEmpty else { return nil }
        var used = Set<Int>()
        for p in placed {
            let (w, h) = p.item.size.span
            for y in p.y..<p.y + h { for x in p.x..<p.x + w { used.insert(y * columns + x) } }
        }
        for i in 0..<(columns * rows) where !used.contains(i) { return (i % columns, i / columns) }
        return nil
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add a widget").font(.headline)
            if host.layout.available.isEmpty {
                Text("All widgets are on the shelf.").foregroundStyle(.secondary)
            }
            ForEach(host.layout.available, id: \.self) { kind in
                Button { host.layout.add(kind); showGallery = false } label: {
                    Label(kind.name, systemImage: kind.symbol).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.hit)
            }
        }
        .padding(12)
        .frame(width: 220)
    }
}

/// Shown until a widget's real view exists, and inside tiles while loading.
struct WidgetPlaceholder: View {
    let kind: WidgetKind
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: kind.symbol).font(.title2).foregroundStyle(.tint)
            Text(kind.name).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension WidgetKind {
    /// A gentle wash of colour per widget (weather and music colour themselves from their content).
    var tint: Color? {
        switch self {
        case .calendar: .red
        case .tasks: .orange
        case .stats: .teal
        case .weather, .music: nil
        }
    }
}
