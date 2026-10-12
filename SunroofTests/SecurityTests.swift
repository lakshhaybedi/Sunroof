import Foundation
import Testing
@testable import Sunroof

@MainActor @Suite struct SecurityTests {
    // ⌘-click in a note opens web and mail links only; a link to a local file is revealed, never run.
    @Test func noteLinksNeverRunFilesOrAppSchemes() {
        #expect(NoteLinkAction(URL(string: "https://example.com")!) == .open)
        #expect(NoteLinkAction(URL(string: "mailto:a@b.com")!) == .open)
        #expect(NoteLinkAction(URL(string: "file:///Users/me/Downloads/run.command")!) == .reveal)
        #expect(NoteLinkAction(URL(string: "x-apple.systempreferences:com.apple.preference.security")!) == .ignore)
        #expect(NoteLinkAction(URL(string: "javascript:alert(1)")!) == .ignore)
        #expect(NoteLinkAction(URL(string: "someapp://do-something")!) == .ignore)
    }

    // Clipboard history on disk is readable by this account only.
    @Test func clipboardFilesArePrivate() throws {
        let dir = tempDir().appendingPathComponent("Sunroof")
        let store = ClipStore(historyDir: dir, favoritesDir: tempDir(), limit: 10)
        store.ingest(Clip(kind: .text, date: .now, text: "secret-ish", source: ClipSource(bundleID: nil, name: nil), contentHash: "h"))
        store.saveSync()
        func mode(_ url: URL) throws -> Int { (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue }
        #expect(try mode(dir) == 0o700)
        #expect(try mode(dir.appendingPathComponent("images")) == 0o700)
        #expect(try mode(dir.appendingPathComponent("history.json")) == 0o600)
    }

    // Note images come from files on this Mac only (a remote URL would be a tracking pixel).
    @Test func noteImagesAreLocalOnly() {
        #expect(NoteImages.isAllowed(URL(fileURLWithPath: "/tmp/a.png")))
        #expect(!NoteImages.isAllowed(URL(string: "https://tracker.example/p.png")!))
    }

    // Searching never matches inside a concealed clip (that would confirm what a password contains).
    @Test func searchNeverMatchesConcealedText() {
        let pw = Clip(kind: .text, date: .now, text: "hunter2", source: ClipSource(bundleID: nil, name: "1Password"), contentHash: "p", isSensitive: true)
        #expect(ClipStore.filter([pw], query: "hunt").isEmpty)
        #expect(ClipStore.filter([pw], query: "1Password").count == 1)
    }
}
