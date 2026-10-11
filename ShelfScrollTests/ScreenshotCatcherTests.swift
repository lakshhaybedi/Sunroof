import Foundation
import Testing
@testable import ShelfScroll

@Suite struct ScreenshotCatcherTests {
    let source = tempDir()
    let drawer = tempDir()

    @discardableResult func file(_ name: String, in dir: URL, screenshot: Bool) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try pngData(width: 2, height: 2).write(to: url)
        if screenshot {
            let value = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
            _ = value.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, value.count, 0, 0) }
        }
        return url
    }

    @Test func detectsXattr() throws {
        #expect(ScreenshotCatcher.isScreenshot(try file("s.png", in: source, screenshot: true)))
        #expect(!ScreenshotCatcher.isScreenshot(try file("n.png", in: source, screenshot: false)))
    }

    @Test func collectMovesIntoScreenshotsFolder() throws {
        try file("Screenshot 1.png", in: source, screenshot: true)
        try file("notes.png", in: source, screenshot: false)
        let shots = drawer.appendingPathComponent("Screenshots")
        try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        try file("Screenshot 1.png", in: shots, screenshot: false)
        let moved = ScreenshotCatcher.collect(from: source, into: drawer, since: .distantPast)
        #expect(moved.map(\.lastPathComponent) == ["Screenshot 1 2.png"])
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("notes.png").path))
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent("Screenshot 1.png").path))
    }

    @Test func skipsHiddenTempFile() throws {
        try file(".Screenshot 1.png", in: source, screenshot: true)
        #expect(ScreenshotCatcher.collect(from: source, into: drawer, since: .distantPast).isEmpty)
    }

    @Test func skipsFilesFromBeforeStart() throws {
        try file("Old.png", in: source, screenshot: true)
        #expect(ScreenshotCatcher.collect(from: source, into: drawer, since: .now.addingTimeInterval(60)).isEmpty)
    }
}
