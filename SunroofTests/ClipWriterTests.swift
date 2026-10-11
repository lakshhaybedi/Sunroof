import AppKit
import Testing
@testable import Sunroof

@MainActor
@Suite struct ClipWriterTests {
    let box = TestPasteboard()
    var pb: NSPasteboard { box.pb }
    let dir = tempDir()
    let source = ClipSource(bundleID: "x", name: "X")

    func readBack() -> Clip? { ClipReader.read(pb, source: source, imagesDir: dir, sensitiveApps: [:]) }

    func textClip(_ s: String, kind: ClipKind = .text, rtf: Data? = nil) -> Clip {
        var c = Clip(kind: kind, date: .now, text: s, source: source, contentHash: "h")
        c.rtf = rtf
        return c
    }

    @Test func roundTripText() {
        ClipWriter.write(textClip("hello"), to: pb, imagesDir: dir)
        #expect(pb.string(forType: .string) == "hello")
        #expect(pb.types?.contains(ClipReader.ownType) == true)
    }

    @Test func plainTextDropsRTF() {
        let rtf = NSAttributedString(string: "hi").rtf(from: NSRange(location: 0, length: 2))
        ClipWriter.write(textClip("hi", kind: .richText, rtf: rtf), to: pb, imagesDir: dir, plainText: true)
        #expect(pb.data(forType: .rtf) == nil)
        #expect(pb.string(forType: .string) == "hi")
    }

    @Test func richTextKeepsRTF() {
        let rtf = NSAttributedString(string: "hi").rtf(from: NSRange(location: 0, length: 2))
        ClipWriter.write(textClip("hi", kind: .richText, rtf: rtf), to: pb, imagesDir: dir)
        #expect(pb.data(forType: .rtf) != nil)
    }

    @Test func roundTripImage() throws {
        try pngData(width: 4, height: 4).write(to: dir.appendingPathComponent("i.png"))
        var c = Clip(kind: .image, date: .now, source: source, contentHash: "h")
        c.imageFile = "i.png"
        ClipWriter.write(c, to: pb, imagesDir: dir)
        #expect(pb.data(forType: .png) != nil)
    }

    @Test func roundTripFiles() {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]
        var c = Clip(kind: .files, date: .now, text: "a.txt\nb.txt", source: source, contentHash: "h")
        c.fileURLs = urls
        ClipWriter.write(c, to: pb, imagesDir: dir)
        #expect(pb.readObjects(forClasses: [NSURL.self]) as? [URL] == urls)
    }

    @Test func ownWritesAreIgnoredByReader() {
        ClipWriter.write(textClip("hello"), to: pb, imagesDir: dir)
        #expect(readBack() == nil)
    }

    // Review I5: a concealed clip put back on the clipboard stays marked concealed.
    @Test func sensitiveWriteMarkedConcealed() {
        var c = textClip("pw")
        c.isSensitive = true
        ClipWriter.write(c, to: pb, imagesDir: dir)
        #expect(pb.types?.contains(.init("org.nspasteboard.ConcealedType")) == true)
    }
}
