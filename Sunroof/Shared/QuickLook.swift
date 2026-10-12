import AppKit
import Quartz

/// Shows files in the system Quick Look panel.
@MainActor
enum QuickLook {
    @MainActor private final class Source: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
        var urls: [URL] = []
        /// Moves the caller's selection (true = next) and returns the newly selected file.
        var onStep: (@MainActor (Bool) -> URL?)?

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
            urls[index] as NSURL
        }

        /// The panel is key while it's open, so arrows and space arrive here, not in the Files panel.
        func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
            guard event.type == .keyDown else { return false }
            let forward: Bool
            switch event.keyCode {
            case 49: panel.close(); return true // space toggles, like Finder
            case 123, 126: forward = false      // ← ↑
            case 124, 125: forward = true       // → ↓
            default: return false
            }
            guard urls.count == 1, let step = onStep, let url = step(forward) else { return false }
            urls = [url]
            panel.reloadData()
            return true
        }
    }

    private static let source = Source()

    /// `onStep` lets ←/→/↑/↓ move through the caller's items while a single file is previewed.
    static func show(_ urls: [URL], onStep: (@MainActor (Bool) -> URL?)? = nil) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        source.urls = urls
        source.onStep = onStep
        panel.dataSource = source
        panel.delegate = source
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        // Above the shelf (which sits at .statusBar) — otherwise the preview opens behind it.
        panel.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1)
        panel.orderFrontRegardless()
    }
}
