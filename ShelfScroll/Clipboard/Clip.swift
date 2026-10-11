import CryptoKit
import Foundation

enum ClipKind: String, Codable, Sendable { case text, richText, url, image, files, color }
enum SensitiveMode: String, Codable, CaseIterable { case conceal, ignore }

struct ClipSource: Equatable, Codable, Sendable {
    var bundleID: String?
    var name: String?
}

struct Clip: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var kind: ClipKind
    var date: Date
    /// Plain text, URL string, hex colour, or newline-joined file names (used for display and search).
    var text: String?
    var rtf: Data?
    /// Filename inside the owning store's images directory.
    var imageFile: String?
    var fileURLs: [URL]?
    var source: ClipSource
    var contentHash: String
    /// Never persisted — the store filters sensitive clips out before saving.
    var isSensitive = false

    static func hash(kind: ClipKind, payload: Data) -> String {
        var data = Data(kind.rawValue.utf8)
        data.append(0)
        data.append(payload)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
