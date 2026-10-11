import AppKit

/// Puts a clip back on a pasteboard, tagged with our own marker so the monitor ignores it.
enum ClipWriter {
    static func write(_ clip: Clip, to pb: NSPasteboard, imagesDir: URL, plainText: Bool = false) {
        pb.clearContents()
        let text = clip.text ?? ""
        switch clip.kind {
        case .text:
            pb.setString(text, forType: .string)
        case .richText:
            pb.setString(text, forType: .string)
            if !plainText, let rtf = clip.rtf { pb.setData(rtf, forType: .rtf) }
        case .url:
            pb.setString(text, forType: .string)
            if !plainText { pb.setString(text, forType: .URL) }
        case .files:
            if plainText { pb.setString(text, forType: .string) }
            else { pb.writeObjects((clip.fileURLs ?? []).map { $0 as NSURL }) }
        case .image:
            if let name = clip.imageFile, let png = try? Data(contentsOf: imagesDir.appendingPathComponent(name)) {
                pb.setData(png, forType: .png)
                if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
            }
        case .color:
            if !plainText, let color = NSColor(hex: text) { pb.writeObjects([color]) }
            pb.setString(text, forType: .string)
        }
        pb.addTypes([ClipReader.ownType], owner: nil)
        pb.setData(Data(), forType: ClipReader.ownType)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
