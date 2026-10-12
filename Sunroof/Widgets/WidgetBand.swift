import SwiftUI
import UniformTypeIdentifiers

/// Drag payload for a widget tile (private type: can't be dropped as text elsewhere).
struct WidgetDrag: Codable, Transferable {
    let kind: WidgetKind
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.lakshhaybedi.sunroof.widget"))
    }
}

/// The snap-grid band of widgets at the bottom of the shelf.
struct WidgetBand: View {
    @Bindable var host: WidgetHost
    /// Builds each widget's content for its size (the per-widget views).
    let content: (WidgetKind, WidgetSize) -> AnyView
    @State private var showGallery = false
    @State private var dragRows: Int?
    @State private var dropTarget: WidgetKind?

    private let cell = ShelfController.widgetCell
    private var rows: Int { dragRows ?? max(1, min(host.settings.widgetRows, 4)) }

    var body: some View {
        VStack(spacing: 0) {
            rowsGrip
            GeometryReader { geo in
                let columns = max(1, Int((geo.size.width - 8) / cell))
                let packed = host.layout.pack(columns: columns, rows: rows)
                ZStack(alignment: .topLeading) {
                    ForEach(packed.placed, id: \.item.kind) { p in tile(p) }
                    addButton(columns: columns, packed: packed)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 8)
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

    private func tile(_ p: WidgetPlacement) -> some View {
        let (w, h) = p.item.size.span
        let kind = p.item.kind
        return content(kind, p.item.size)
            .frame(width: CGFloat(w) * cell - 8, height: CGFloat(h) * cell - 8)
            .background(BehindWindowBlur()) // plain blur of whatever is under the shelf, no tint
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(dropTarget == kind ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.12),
                        lineWidth: dropTarget == kind ? 2 : 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            .offset(x: CGFloat(p.x) * cell, y: CGFloat(p.y) * cell)
            .draggable(WidgetDrag(kind: kind)) {
                Label(kind.name, systemImage: kind.symbol).padding(8).background(.regularMaterial, in: .rect(cornerRadius: 8))
            }
            .dropDestination(for: WidgetDrag.self) { items, _ in
                guard let moved = items.first?.kind, moved != kind,
                      let target = host.layout.items.firstIndex(where: { $0.kind == kind }) else { return false }
                host.layout.move(moved, toIndex: target)
                return true
            } isTargeted: { dropTarget = $0 ? kind : (dropTarget == kind ? nil : dropTarget) }
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
    }

    /// ＋ in the first free cell (or the band's top-right corner when full) opens the gallery.
    private func addButton(columns: Int, packed: (placed: [WidgetPlacement], hidden: [WidgetItem])) -> some View {
        let spot = firstFreeCell(columns: columns, placed: packed.placed)
        return Button { showGallery = true } label: {
            Image(systemName: "plus").font(.title2).foregroundStyle(.secondary)
                .frame(width: spot == nil ? 28 : cell - 8, height: spot == nil ? 28 : cell - 8)
                .background(RoundedRectangle(cornerRadius: spot == nil ? 8 : 16)
                    .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(.hit)
        .help("Add a widget")
        .offset(x: spot.map { CGFloat($0.0) * cell } ?? CGFloat(columns) * cell - 36,
                y: spot.map { CGFloat($0.1) * cell } ?? 0)
        .opacity(host.layout.available.isEmpty && spot == nil ? 0 : 1)
        .popover(isPresented: $showGallery, arrowEdge: .top) { gallery }
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

/// Blurs the desktop/windows behind the (transparent) widget tray; always "active" so it doesn't grey out.
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
