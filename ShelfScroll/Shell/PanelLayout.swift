import AppKit
import SwiftUI

enum PanelID: String, CaseIterable, Codable {
    case clipboard, files, notes
}

struct PanelDescriptor {
    let id: PanelID
    let title: String
    let makeView: @MainActor () -> AnyView
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

    init(descriptors: [PanelDescriptor], displayKey: String) {
        ids = descriptors.map(\.id)
        super.init(nibName: nil, bundle: nil)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        for d in descriptors {
            let item = NSSplitViewItem(viewController: NSHostingController(rootView: d.makeView()))
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

/// Column header: centered secondary title, buttons trailing (matches Unclutter).
struct PanelHeader<Buttons: View>: View {
    let title: String
    let buttons: Buttons

    init(title: String, @ViewBuilder buttons: () -> Buttons) {
        self.title = title
        self.buttons = buttons()
    }

    var body: some View {
        ZStack {
            Text(title).font(.headline).foregroundStyle(.secondary)
            HStack(spacing: 6) { Spacer(); buttons }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
    }
}
