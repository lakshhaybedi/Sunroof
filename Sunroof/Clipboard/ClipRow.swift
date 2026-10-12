import AppKit
import SwiftUI

/// One clip: gutter (app icon, or star on hover), preview, delete button on hover.
struct ClipRow: View {
    let clip: Clip
    let store: ClipStore
    let isSelected: Bool
    let isFavoritesView: Bool
    var expanded = false
    let onCopy: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var revealing = false

    /// Every row is the same height; content is left-aligned and vertically centred.
    static let height: CGFloat = 64

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            gutter.frame(width: 28)
            preview
                .frame(maxWidth: .infinity, alignment: .leading)
            if !isFavoritesView && (hovering || isSelected) {
                Button(action: onDelete) { Image(systemName: "xmark").font(.body.weight(.medium)) }
                    .buttonStyle(.hit).foregroundStyle(.secondary).help("Delete")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height, alignment: .center)
        .background(isSelected || expanded ? Color.primary.opacity(0.08) : .clear)
        .contentShape(Rectangle()) // the whole row copies (padding and gutter too); the star and × buttons win
        .onTapGesture(perform: onCopy)
        .onHover { hovering = $0 }
        .onModifierKeysChanged(mask: .option) { _, new in revealing = new.contains(.option) }
    }

    @ViewBuilder private var gutter: some View {
        if isFavoritesView {
            Button(action: onToggleFavorite) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.12)))
            }
            .buttonStyle(.hit).help("Remove from Favorites")
        } else if (hovering || isSelected) && !clip.isSensitive { // concealed clips can't be starred
            Button(action: onToggleFavorite) {
                Image(systemName: store.isFavorite(clip) ? "star.fill" : "star").font(.title3)
            }
            .buttonStyle(.hit).foregroundStyle(.secondary).help("Favorite")
        } else {
            AppIcon(bundleID: clip.source.bundleID)
        }
    }

    @ViewBuilder private var preview: some View {
        if clip.isSensitive && !(hovering && revealing) {
            Text("•••••• · \(clip.source.name ?? "Concealed")").foregroundStyle(.secondary)
        } else {
            switch clip.kind {
            case .text, .richText:
                Text(clip.text ?? "").lineLimit(2).truncationMode(.tail)
            case .url:
                Text(underlined(clip.text ?? "")).lineLimit(2).truncationMode(.middle)
            case .image:
                if let url = store.imageURL(for: clip),
                   let img = ThumbnailCache.shared.thumbnail(for: url, maxPixelSize: 320) {
                    Image(decorative: img, scale: 2).resizable().scaledToFit()
                        .frame(maxHeight: Self.height - 16, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Label("Image", systemImage: "photo").foregroundStyle(.secondary)
                }
            case .files:
                HStack(spacing: 8) {
                    if let first = clip.fileURLs?.first {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: first.path)).resizable().frame(width: 32, height: 32)
                    }
                    Text(clip.text ?? "").lineLimit(2)
                }
            case .color:
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: NSColor(hex: clip.text ?? "") ?? .clear))
                        .frame(width: 32, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
                    Text(clip.text ?? "").font(.body.monospaced())
                }
            }
        }
    }

    private func underlined(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        a.underlineStyle = .single
        return a
    }
}

/// Source-app icon, cached per bundle ID.
struct AppIcon: View {
    let bundleID: String?
    @MainActor private static var cache: [String: NSImage] = [:]

    var body: some View {
        if let image = Self.icon(bundleID) {
            Image(nsImage: image).resizable().frame(width: 24, height: 24)
        } else {
            Image(systemName: "doc.on.clipboard").foregroundStyle(.secondary)
        }
    }

    @MainActor private static func icon(_ id: String?) -> NSImage? {
        guard let id else { return nil }
        if let hit = cache[id] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        cache[id] = img
        return img
    }
}
