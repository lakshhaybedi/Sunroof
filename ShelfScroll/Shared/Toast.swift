import AppKit
import SwiftUI

/// Small HUD message, top-centre of the main screen, for 1.2 s.
enum Toast {
    @MainActor private static var panel: NSPanel?

    @MainActor static func show(_ message: String) {
        panel?.orderOut(nil)
        let host = NSHostingView(rootView:
            Text(message)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
        )
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: v.midX - size.width / 2, y: v.maxY - size.height - 24))
        }
        p.orderFrontRegardless()
        panel = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if panel === p { p.orderOut(nil); panel = nil }
        }
    }
}
