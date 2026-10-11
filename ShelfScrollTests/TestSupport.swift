import AppKit
import Foundation

func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("shelfscroll-test-\(UUID())")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func pngData(width: Int, height: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

/// A private pasteboard, released when the test ends.
final class TestPasteboard {
    let pb = NSPasteboard(name: .init("test-\(UUID())"))
    init() { pb.clearContents() }
    deinit { pb.releaseGlobally() }
}
