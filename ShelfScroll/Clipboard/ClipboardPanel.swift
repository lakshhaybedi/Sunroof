import AppKit
import SwiftUI

struct ClipboardPanel: View {
    let store: ClipStore
    let settings: AppSettings
    let paster: Paster
    var notes: NoteAppending? = nil

    @State private var showFavorites = false
    @State private var searching = false
    @State private var query = ""
    @State private var selection: Clip.ID?
    @State private var confirmClear = false
    @State private var draft = ""
    @FocusState private var listFocused: Bool
    @FocusState private var editing: Bool
    @FocusState private var searchFocused: Bool

    private var clips: [Clip] {
        ClipStore.filter(showFavorites ? store.favorites : store.history, query: query)
    }

    /// The newest history clip is what's on the clipboard (copying from the panel promotes it).
    private var current: Clip? {
        guard !showFavorites, query.isEmpty, let first = store.history.first, !first.isSensitive else { return nil }
        return first
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: showFavorites ? "Clipboard Favorites" : "Clipboard History") { headerButtons }
            if searching {
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(.horizontal, 8).padding(.bottom, 6)
            }
            Divider()
            if NSPasteboard.general.accessBehavior == .alwaysDeny { permissionBanner }
            list
        }
        .onAppear {
            listFocused = true // ↑/↓/⏎ work as soon as the shelf opens
            showFavorites = switch settings.clipboardOpensWith {
            case .lastView: settings.lastClipboardView == .favorites
            case .history: false
            case .favorites: true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shelfFocusPanel)) { n in
            if n.object as? String == PanelID.clipboard.rawValue { listFocused = true }
        }
        .onChange(of: listFocused) { _, f in if f { settings.lastPanel = .clipboard } }
        .onChange(of: showFavorites) { _, fav in
            settings.lastClipboardView = fav ? .favorites : .history
            selection = nil
        }
    }

    // MARK: - Header

    @ViewBuilder private var headerButtons: some View {
        HeaderButton(symbol: "magnifyingglass", help: "Search", active: searching) {
            searching.toggle()
            if !searching { query = "" }
        }
        HeaderButton(symbol: "pause.fill", help: settings.clipboardPaused ? "Resume" : "Pause",
                     tint: settings.clipboardPaused ? .orange : nil) {
            settings.clipboardPaused.toggle()
        }
        HeaderButton(symbol: "nosign", help: "Clear") { confirmClear = true }
            .popover(isPresented: $confirmClear, arrowEdge: .bottom) {
                HStack(spacing: 0) {
                    Button("Cancel") { confirmClear = false }.buttonStyle(.borderless).padding(12)
                    Divider()
                    Button("Clear the Clipboard and History") {
                        NSPasteboard.general.clearContents()
                        store.clearHistory()
                        confirmClear = false
                    }
                    .buttonStyle(.borderless).padding(12)
                }
                .fixedSize()
            }
        HeaderButton(symbol: "list.bullet", help: "History", active: !showFavorites) { showFavorites = false }
        HeaderButton(symbol: "star.fill", help: "Favorites", active: showFavorites) { showFavorites = true }
    }

    private var permissionBanner: some View {
        HStack {
            Text("ShelfScroll can't read the clipboard. Allow it in System Settings › Privacy & Security › Paste from Other Apps.")
                .font(.caption)
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
            }
        }
        .padding(8)
        .background(.yellow.opacity(0.2))
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let current {
                        currentRow(current)
                        Divider()
                    }
                    ForEach(Array(clips.enumerated()).filter { $0.element.id != current?.id }, id: \.element.id) { _, clip in
                        row(clip)
                        Divider()
                    }
                    if clips.isEmpty {
                        Text(showFavorites ? "Star a clip to keep it here forever." : "Copy something and it shows up here.")
                            .foregroundStyle(.secondary).padding(.top, 40)
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onKeyPress(phases: .down) { handleKey($0, proxy: proxy) }
        }
    }

    private func row(_ clip: Clip) -> some View {
        ClipRow(clip: clip, store: store, isSelected: selection == clip.id, isFavoritesView: showFavorites,
                onCopy: { select(clip); copy(clip) },
                onToggleFavorite: { store.toggleFavorite(clip) },
                onDelete: { store.delete(clip.id) })
            .id(clip.id)
            .contextMenu { menu(clip) }
    }

    /// The current clipboard, expanded; text is editable in place.
    @ViewBuilder private func currentRow(_ clip: Clip) -> some View {
        if clip.kind == .text || clip.kind == .richText {
            HStack(alignment: .top, spacing: 10) {
                Button { store.toggleFavorite(clip) } label: {
                    Image(systemName: store.isFavorite(clip) ? "star.fill" : "star").font(.title3)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).frame(width: 28)
                TextField("", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($editing)
                    .onAppear { draft = clip.text ?? "" }
                    .onChange(of: clip.id) { _, _ in draft = store.history.first?.text ?? "" }
                    .onChange(of: editing) { _, now in if !now { commitEdit(clip) } }
                    .onSubmit { editing = false }
                Button { store.delete(clip.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(minHeight: 88, alignment: .top)
            .background(Color.primary.opacity(0.08))
            .id(clip.id)
            .contextMenu { menu(clip) }
        } else {
            ClipRow(clip: clip, store: store, isSelected: selection == clip.id, isFavoritesView: false, expanded: true,
                    onCopy: { copy(clip) }, onToggleFavorite: { store.toggleFavorite(clip) },
                    onDelete: { store.delete(clip.id) })
                .id(clip.id)
                .contextMenu { menu(clip) }
        }
    }

    @ViewBuilder private func menu(_ clip: Clip) -> some View {
        Button("Paste") { paster.paste(clip) }
        Button("Paste as Plain Text") { paster.paste(clip, plainText: true) }
        Button("Copy") { copy(clip) }
        if !clip.isSensitive {
            Button(store.isFavorite(clip) ? "Unfavorite" : "Favorite") { store.toggleFavorite(clip) }
        }
        if let notes, !clip.isSensitive {
            Menu("Send to Note") {
                ForEach(notes.recentNoteTitles, id: \.filename) { note in
                    Button(note.title) { send(clip, to: note.filename, notes) }
                }
                Divider()
                Button("New Note") { send(clip, to: nil, notes) }
            }
        }
        if !showFavorites {
            Divider()
            Button("Delete", role: .destructive) { store.delete(clip.id) }
        }
    }

    // MARK: - Actions

    private func send(_ clip: Clip, to filename: String?, _ notes: NoteAppending) {
        let name: String
        switch clip.kind {
        case .image:
            guard let url = store.imageURL(for: clip), let png = try? Data(contentsOf: url) else { return }
            name = notes.appendImage(png, to: filename)
        case .files:
            let links = (clip.fileURLs ?? []).map { "[\($0.lastPathComponent)](\($0.absoluteString))" }
            name = notes.append(links.joined(separator: "\n"), to: filename)
        default:
            name = notes.append(clip.text ?? "", to: filename)
        }
        Toast.show("Added to \((name as NSString).deletingPathExtension)")
    }

    private func select(_ clip: Clip) {
        selection = clip.id
        listFocused = true
    }

    private func copy(_ clip: Clip) {
        paster.copy(clip)
        if !showFavorites {
            var promoted = clip
            promoted.date = .now
            store.ingest(promoted) // moves it to the top: it's the current clipboard now
        }
    }

    private func commitEdit(_ clip: Clip) {
        guard draft != clip.text, !draft.isEmpty else { return }
        store.updateText(clip.id, to: draft)
        if let updated = store.history.first(where: { $0.id == clip.id }) { paster.copy(updated) }
    }

    private func handleKey(_ key: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !editing, !searchFocused else { return .ignored } // text fields keep their own keys
        let all = (current.map { [$0] } ?? []) + clips.filter { $0.id != current?.id }
        let index = all.firstIndex { $0.id == selection }
        let selected = index.map { all[$0] }

        if key.modifiers.contains(.command) {
            if let n = Int(key.characters), (1...9).contains(n), n <= all.count {
                paster.paste(all[n - 1]); return .handled
            }
            switch key.characters {
            case "c": if let selected { copy(selected) }; return .handled
            case "s": if let selected { store.toggleFavorite(selected) }; return .handled
            default: return .ignored
            }
        }
        switch key.key {
        case .downArrow, .upArrow:
            guard !all.isEmpty else { return .handled }
            let next = key.key == .downArrow ? min((index ?? -1) + 1, all.count - 1) : max((index ?? 1) - 1, 0)
            selection = all[next].id
            proxy.scrollTo(all[next].id)
            return .handled
        case .return:
            if let selected { paster.paste(selected, plainText: key.modifiers.contains(.option)) }
            return .handled
        case .delete, .deleteForward:
            if let selected, !showFavorites { store.delete(selected.id) }
            return .handled
        case .space:
            if let selected {
                if let url = store.imageURL(for: selected) { QuickLook.show([url]) }
                else if let urls = selected.fileURLs { QuickLook.show(urls) }
            }
            return .handled
        default:
            return .ignored
        }
    }
}

/// Small header icon button; `active` gets a filled background (like Unclutter's view toggles).
struct HeaderButton: View {
    let symbol: String
    let help: String
    var active = false
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(active ? Color.primary.opacity(0.15) : .clear))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
