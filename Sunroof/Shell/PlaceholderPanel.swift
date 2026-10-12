import SwiftUI

/// Stand-in column until plans 2–4 replace each panel.
struct PlaceholderPanel: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: title) { EmptyView() }
            Divider()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension PanelDescriptor {
    static let placeholders: [PanelDescriptor] = [
        .init(id: .clipboard) { AnyView(PlaceholderPanel(title: "Clipboard History")) },
        .init(id: .files) { AnyView(PlaceholderPanel(title: "Files")) },
        .init(id: .notes) { AnyView(PlaceholderPanel(title: "Notes")) },
    ]
}
