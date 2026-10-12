import Foundation
import ImageIO

/// Display-size thumbnails via ImageIO (never decodes the full image). Purged when the shelf closes.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, CGImage>()

    // Kept between shelf opens (redrawing every thumbnail on each open made opening spike the GPU);
    // a 32 MB cap keeps memory modest, and NSCache also drops entries when macOS is short of memory.
    init() { cache.totalCostLimit = 32 * 1024 * 1024 }

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

    func cached(_ key: String) -> CGImage? { cache.object(forKey: key as NSString) }

    func store(_ image: CGImage, _ key: String) {
        cache.setObject(image, forKey: key as NSString, cost: image.bytesPerRow * image.height)
    }
}

import QuickLookThumbnailing

extension ThumbnailCache {
    /// Quick Look thumbnail for any file (PDFs, images, documents…) at the given point size.
    func fileThumbnail(for url: URL, size: CGFloat, scale: CGFloat) async -> CGImage? {
        let key = "ql:\(url.path)#\(size)@\(scale)"
        if let hit = cached(key) { return hit }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                   scale: scale, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        store(rep.cgImage, key)
        return rep.cgImage
    }
}
