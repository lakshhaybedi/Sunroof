import AppKit
import SwiftUI

/// "Title  ~/path  [Choose…]" row backed by an NSOpenPanel.
struct FolderPicker: View {
    let title: String
    @Binding var url: URL

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(url.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Button("Choose…") { choose() }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = url.deletingLastPathComponent()
        if panel.runModal() == .OK, let chosen = panel.url { url = chosen }
    }
}
