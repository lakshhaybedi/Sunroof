import AppKit
import SwiftUI

struct GlobalSearchView: View {
    @Bindable var search: GlobalSearch
    let onActivate: (SearchHit) -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard, files and notes", text: $search.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .onKeyPress(.downArrow) { search.moveSelection(by: 1); return .handled }
                    .onKeyPress(.upArrow) { search.moveSelection(by: -1); return .handled }
                    .onKeyPress(.return) { if let hit = search.selectedHit { onActivate(hit) }; return .handled }
                Text("⌘⇧F").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(12)
            if !search.sections.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(search.sections) { section in
                            Text(section.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 12).padding(.top, 8)
                            ForEach(section.hits) { hit in
                                row(hit)
                                    .background(RoundedRectangle(cornerRadius: 6)
                                        .fill(search.selectedHit == hit ? Color.accentColor.opacity(0.25) : .clear))
                                    .contentShape(Rectangle())
                                    .onTapGesture { onActivate(hit) }
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
            } else if !search.query.isEmpty {
                Text("No results").foregroundStyle(.secondary).padding(12)
            }
        }
        .frame(maxWidth: 640)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .padding(12)
        .onAppear { fieldFocused = true }
        .onChange(of: search.isVisible) { _, v in if v { fieldFocused = true } }
    }

    @ViewBuilder private func row(_ hit: SearchHit) -> some View {
        HStack(spacing: 8) {
            switch hit {
            case let .clip(c):
                AppIcon(bundleID: c.source.bundleID).frame(width: 20, height: 20)
                Text(c.isSensitive ? "••••••" : (c.text ?? "Image")).lineLimit(1)
            case let .file(u):
                Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 20, height: 20)
                Text(u.lastPathComponent).lineLimit(1)
                Text(u.deletingLastPathComponent().lastPathComponent).foregroundStyle(.secondary).lineLimit(1)
            case let .note(_, title, preview):
                Image(systemName: "note.text").frame(width: 20, height: 20).foregroundStyle(.secondary)
                Text(title.isEmpty ? "Untitled" : title).lineLimit(1)
                Text(preview).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }
}
