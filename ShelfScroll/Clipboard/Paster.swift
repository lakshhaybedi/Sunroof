import AppKit

/// Copies clips to the clipboard, or pastes them into the app that was frontmost before the shelf opened.
@MainActor
final class Paster {
    private let store: ClipStore
    private let shelf: ShelfController

    init(store: ClipStore, shelf: ShelfController) {
        self.store = store
        self.shelf = shelf
    }

    func copy(_ clip: Clip, plainText: Bool = false) {
        let dir = store.imageURL(for: clip)?.deletingLastPathComponent() ?? store.historyImagesDir
        ClipWriter.write(clip, to: .general, imagesDir: dir, plainText: plainText)
    }

    func paste(_ clip: Clip, plainText: Bool = false) {
        copy(clip, plainText: plainText)
        let target = shelf.previousApp
        // Post ⌘V only after the shelf is gone, or the keystroke lands in the shelf itself.
        shelf.hide {
            guard Permissions.isAccessibilityTrusted, let target, !target.isTerminated else {
                Toast.show("Copied — press ⌘V")
                return
            }
            target.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let src = CGEventSource(stateID: .combinedSessionState)
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down) // V
                    e?.flags = .maskCommand
                    e?.post(tap: .cghidEventTap)
                }
            }
        }
    }
}
