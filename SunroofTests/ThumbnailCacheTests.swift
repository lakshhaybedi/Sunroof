import CoreGraphics
import Foundation
import Testing
@testable import Sunroof

@MainActor
@Suite struct ThumbnailCacheTests {
    @Test func thumbnailIsDownsampled() throws {
        let url = tempDir().appendingPathComponent("big.png")
        try pngData(width: 2000, height: 1000).write(to: url)
        let cache = ThumbnailCache()
        let t = try #require(cache.thumbnail(for: url, maxPixelSize: 200))
        #expect(max(t.width, t.height) == 200)
        cache.purge()
        #expect(cache.thumbnail(for: url, maxPixelSize: 200) != nil)
    }

    @Test func fileThumbnailForPDF() async throws {
        let url = tempDir().appendingPathComponent("doc.pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 100, y: 100, width: 200, height: 200))
        ctx.endPDFPage()
        ctx.closePDF()
        let t = try #require(await ThumbnailCache().fileThumbnail(for: url, size: 64, scale: 2))
        #expect(max(t.width, t.height) <= 128)
    }
}
