import AppKit
import Quartz

/// Shows files in the system Quick Look panel.
@MainActor
enum QuickLook {
    private final class Source: NSObject, QLPreviewPanelDataSource {
        var urls: [URL] = []
        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
            urls[index] as NSURL
        }
    }

    private static let source = Source()

    static func show(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        source.urls = urls
        panel.dataSource = source
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
}
