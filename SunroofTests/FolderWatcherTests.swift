import Foundation
import Testing
@testable import Sunroof

@MainActor
@Suite struct FolderWatcherTests {
    @Test func firesOnNewFile() async throws {
        let dir = tempDir()
        var fired = false
        let watcher = FolderWatcher(url: dir) { fired = true }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("new.txt").path, contents: Data())
        for _ in 0..<40 where !fired { try await Task.sleep(for: .milliseconds(50)) }
        #expect(fired)
        _ = watcher
    }
}
