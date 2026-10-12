import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum PanelID: String, CaseIterable, Codable {
    case clipboard, files, notes
}

extension Notification.Name {
    /// Posted when the shelf opens to give a column keyboard focus (object: PanelID raw value).
    static let shelfFocusPanel = Notification.Name("Sunroof.focusPanel")
    /// Closes the shelf (e.g. so a macOS permission dialog isn't hidden behind it).
    static let shelfDismiss = Notification.Name("Sunroof.dismissShelf")
}

struct PanelDescriptor {
    let id: PanelID
    let title: String
    let makeView: @MainActor () -> AnyView
}

/// Order after dropping `moved`'s header onto `target`'s column: `moved` takes `target`'s place.
func movingPanel(_ moved: PanelID, onto target: PanelID, in order: [PanelID]) -> [PanelID] {
    guard moved != target, let from = order.firstIndex(of: moved), let to = order.firstIndex(of: target) else { return order }
    var result = order
    result.remove(at: from)
    result.insert(moved, at: to)
    return result
}

/// Drag payload for a column header (a private type, so it can't be dropped as text into notes).
struct PanelDrag: Codable, Transferable {
    let id: PanelID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.lakshhaybedi.sunroof.panel"))
    }
}

private struct PanelIDKey: EnvironmentKey { static let defaultValue: PanelID? = nil }
private struct ReorderKey: EnvironmentKey { nonisolated(unsafe) static let defaultValue: ((PanelID, PanelID) -> Void)? = nil }

extension EnvironmentValues {
    /// The column a view is hosted in (set by PanelSplitController).
    var panelID: PanelID? {
        get { self[PanelIDKey.self] }
        set { self[PanelIDKey.self] = newValue }
    }
    /// Moves a column onto another's place (dragging headers).
    var reorderPanel: ((PanelID, PanelID) -> Void)? {
        get { self[ReorderKey.self] }
        set { self[ReorderKey.self] = newValue }
    }
}

/// Column order shown in the shelf: user order (deduped), any missing panels appended, then filtered to enabled.
func visiblePanels(order: [PanelID], enabled: Set<PanelID>) -> [PanelID] {
    var seen = Set<PanelID>()
    let full = (order + PanelID.allCases).filter { seen.insert($0).inserted }
    return full.filter(enabled.contains)
}

/// Side-by-side resizable columns; widths autosave per display and per column set.
@MainActor
final class PanelSplitController: NSSplitViewController {
    let ids: [PanelID]

    init(descriptors: [PanelDescriptor], displayKey: String, settings: AppSettings? = nil,
         reorder: ((PanelID, PanelID) -> Void)? = nil) {
        ids = descriptors.map(\.id)
        super.init(nibName: nil, bundle: nil)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        for d in descriptors {
            let root = PanelRoot(id: d.id, settings: settings, reorder: reorder, content: d.makeView())
            let item = NSSplitViewItem(viewController: NSHostingController(rootView: root))
            item.minimumThickness = 220
            item.canCollapse = false
            addSplitViewItem(item)
        }
        splitView.autosaveName = "ShelfSplit-\(displayKey)-\(ids.map(\.rawValue).joined(separator: "-"))"
    }

    required init?(coder: NSCoder) { fatalError() }

    func focus(_ id: PanelID) {
        guard let i = ids.firstIndex(of: id) else { return }
        let v = splitViewItems[i].viewController.view
        v.window?.makeFirstResponder(v)
    }
}

/// Wraps each column: accent colour, which column it is, and the header drag-to-reorder hook.
struct PanelRoot: View {
    let id: PanelID
    let settings: AppSettings?
    let reorder: ((PanelID, PanelID) -> Void)?
    let content: AnyView

    var body: some View {
        content
            .tint(settings?.accent.color ?? .accentColor)
            .environment(\.panelID, id)
            .environment(\.reorderPanel, reorder)
    }
}

/// Column header: centered secondary title, buttons trailing (matches Unclutter).
/// Drag the header onto another column to move this column there.
struct PanelHeader<Buttons: View>: View {
    let title: String
    let buttons: Buttons
    @Environment(\.panelID) private var panelID
    @Environment(\.reorderPanel) private var reorder
    @State private var hovering = false
    @State private var targeted = false

    init(title: String, @ViewBuilder buttons: () -> Buttons) {
        self.title = title
        self.buttons = buttons()
    }

    var body: some View {
        let header = ZStack {
            Text(title).font(.headline).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if panelID != nil, reorder != nil {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption).foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0)
                        .help("Drag to move this column")
                }
                Spacer()
                buttons
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 6).fill(targeted ? Color.accentColor.opacity(0.25) : .clear))
        .onHover { hovering = $0 }

        if let panelID, let reorder {
            header
                .draggable(PanelDrag(id: panelID)) {
                    Text(title).font(.headline).padding(8).background(.regularMaterial, in: .rect(cornerRadius: 8))
                }
                .dropDestination(for: PanelDrag.self) { items, _ in
                    guard let moved = items.first?.id else { return false }
                    reorder(moved, panelID)
                    return true
                } isTargeted: { targeted = $0 }
        } else {
            header
        }
    }
}
