import Foundation
import ImageIO

/// Display-size thumbnails via ImageIO (never decodes the full image). Purged when the shelf closes.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, CGImage>()

    init() { cache.totalCostLimit = 64 * 1024 * 1024 }

    func thumbnail(for url: URL, maxPixelSize: Int) -> CGImage? {
        let key = "\(url.path)#\(maxPixelSize)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary) else { return nil }
        cache.setObject(img, forKey: key, cost: img.bytesPerRow * img.height)
        return img
    }

    func purge() { cache.removeAllObjects() }
}
