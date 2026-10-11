import Foundation
import Testing
@testable import ShelfScroll

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
}
