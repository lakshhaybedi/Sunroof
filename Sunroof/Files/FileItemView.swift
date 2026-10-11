import AppKit
import SwiftUI

/// Icon-view cell: Quick Look thumbnail (Finder icon until it loads) + 2-line name; inline rename.
struct FileCell: View {
    let item: DrawerItem
    let size: CGFloat
    let selected: Bool
    @Binding var renaming: URL?
    var subtitle: String? = nil
    let onRename: (String) -> Void

    @State private var thumbnail: CGImage?
    @State private var draft = ""
    @FocusState private var nameFocused: Bool
    @Environment(\.displayScale) private var scale

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: scale).resizable().scaledToFit()
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().scaledToFit()
                }
            }
            .frame(width: size, height: size)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.primary.opacity(0.12) : .clear))

            if renaming == item.url {
                TextField("", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .focused($nameFocused)
                    .onAppear { draft = item.name; nameFocused = true }
                    .onSubmit { onRename(draft); renaming = nil }
                    .onChange(of: nameFocused) { _, f in if !f { renaming = nil } } // focus loss cancels
            } else {
                Text(item.name)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear)))
                    .foregroundStyle(selected ? .white : .primary)
                if let subtitle {
                    Label(subtitle, systemImage: "folder").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .frame(width: size + 40)
        .task(id: "\(item.url.path)#\(size)#\(item.dateModified.timeIntervalSince1970)") {
            thumbnail = await ThumbnailCache.shared.fileThumbnail(for: item.url, size: size, scale: scale)
        }
    }
}

/// Placeholder cell while a dropped link downloads.
struct DownloadCell: View {
    let name: String
    let size: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            ProgressView().controlSize(.large).frame(width: size, height: size).padding(4)
            Text(name).font(.callout).lineLimit(2).truncationMode(.middle).foregroundStyle(.secondary)
        }
        .frame(width: size + 40)
    }
}
