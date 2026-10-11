import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FilesPanel: View {
    let model: DrawerModel
    let settings: AppSettings

    @State private var selection = Set<URL>()
    @State private var anchor: URL?
    @State private var renaming: URL?
    @State private var searching = false
    @State private var dropTargeted = false
    @FocusState private var focused: Bool
    @FocusState private var searchFocused: Bool

    private var size: CGFloat { AppSettings.itemSizes[min(max(settings.itemSizeIndex, 0), 3)] }
    private var selectedItems: [DrawerItem] { model.items.filter { selection.contains($0.url) } }

    var body: some View {
        @Bindable var settings = settings
        @Bindable var model = model
        VStack(spacing: 0) {
            PanelHeader(title: "Files") {
                gearMenu
                HeaderButton(symbol: "magnifyingglass", help: "Search", active: searching) {
                    searching.toggle()
                    if !searching { model.query = "" } else { searchFocused = true }
                }
            }
            if searching {
                TextField("Search", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(.horizontal, 8).padding(.bottom, 6)
            }
            if model.breadcrumbs.count > 1 && model.query.isEmpty { breadcrumbBar }
            Divider()
            content
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: dropTargeted ? 3 : 0).padding(2))
        .onReceive(NotificationCenter.default.publisher(for: .shelfFocusPanel)) { n in
            if n.object as? String == PanelID.files.rawValue { focused = true }
        }
        .onChange(of: focused) { _, f in if f { settings.lastPanel = .files } }
        .onDrop(of: [.fileURL, .url, .image], delegate: FilesDropDelegate(model: model, targeted: $dropTargeted))
    }

    // MARK: - Header

    private var gearMenu: some View {
        @Bindable var settings = settings
        return Menu {
            Button("New Folder") { if let url = try? model.newFolder() { selection = [url]; renaming = url } }
            Button("Show in Finder") { NSWorkspace.shared.open(model.current) }
            Divider()
            Picker("Arrange By", selection: $settings.arrangeBy) {
                Text("Name").tag(ArrangeBy.name)
                Text("Kind").tag(ArrangeBy.kind)
                Text("Date Added").tag(ArrangeBy.dateAdded)
                Text("Date Modified").tag(ArrangeBy.dateModified)
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Keep Folders on Top", isOn: $settings.foldersOnTop)
            Divider()
            Picker("View As", selection: $settings.filesAsList) {
                Text("Icons").tag(false).keyboardShortcut("1")
                Text("List").tag(true).keyboardShortcut("2")
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Item Size", selection: $settings.itemSizeIndex) {
                Text("Small").tag(0)
                Text("Medium").tag(1)
                Text("Large").tag(2)
                Text("Extra Large").tag(3)
            }
            Picker("Auto-cleanup", selection: $settings.cleanupDays) {
                Text("Off").tag(0)
                Text("After 7 Days").tag(7)
                Text("After 30 Days").tag(30)
                Text("After 90 Days").tag(90)
            }
            Toggle("Catch Screenshots", isOn: $settings.catchScreenshots)
        } label: {
            Image(systemName: "gearshape.fill").foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Options")
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            Button { model.goUp() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).help("Back (⌘↑)")
            ForEach(Array(model.breadcrumbs.enumerated()), id: \.offset) { i, url in
                if i > 0 { Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary) }
                Button(i == 0 ? "Files" : url.lastPathComponent) { model.open(url) }
                    .buttonStyle(.plain)
                    .foregroundStyle(i == model.breadcrumbs.count - 1 ? .primary : .secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 10).padding(.bottom, 6)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if model.rootMissing {
            VStack(spacing: 12) {
                Text("Folder not found").font(.headline)
                Text(settings.filesFolder.path).font(.caption).foregroundStyle(.secondary)
                Button("Choose…") { chooseFolder() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if settings.filesAsList {
            list
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: size + 40), spacing: 8)], spacing: 12) {
                ForEach(model.items) { item in
                    FileCell(item: item, size: size, selected: selection.contains(item.url), renaming: $renaming,
                             subtitle: model.query.isEmpty ? nil : folderLabel(item)) {
                        rename(item, to: $0)
                    }
                    .contentShape(Rectangle())
                    // One tap gesture (a separate double-tap gesture delays every single click by the double-click
                    // interval): select on the first click, open on the second via the event's click count.
                    .onTapGesture {
                        if NSApp.currentEvent?.clickCount ?? 1 >= 2 { open(item) } else { click(item) }
                    }
                    .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                    .contextMenu { menu(for: selection.contains(item.url) ? selectedItems : [item]) }
                }
                ForEach(model.downloads.sorted { $0.value < $1.value }, id: \.key) { _, name in
                    DownloadCell(name: name, size: size)
                }
            }
            .padding(10)
            if model.items.isEmpty && model.downloads.isEmpty {
                Text(model.query.isEmpty ? "Drop files here." : "No matches.")
                    .foregroundStyle(.secondary).padding(.top, 30)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selection = [] }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down, action: handleKey)
    }

    private var list: some View {
        Table(model.items, selection: $selection) {
            TableColumn("Name") { item in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 16, height: 16)
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                }
                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
            }
            .width(min: 160, ideal: 280)
            TableColumn("Modified") { item in
                Text(item.dateModified, format: .dateTime.day().month(.abbreviated).hour().minute()).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Size") { item in
                Text(item.isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: item.size ?? 0, countStyle: .file))
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 70)
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            menu(for: model.items.filter { urls.contains($0.url) })
        } primaryAction: { urls in
            model.items.filter { urls.contains($0.url) }.forEach(open)
        }
        .onKeyPress(phases: .down, action: handleKey)
    }

    // MARK: - Actions

    /// Search results: which folder each one is in ("Files" for the top level).
    private func folderLabel(_ item: DrawerItem) -> String {
        let parent = item.url.deletingLastPathComponent()
        return parent.path == model.root.path ? "Files" : parent.lastPathComponent
    }

    private func click(_ item: DrawerItem) {
        focused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
            anchor = item.url
        } else if flags.contains(.shift) {
            selection = rangeSelection(model.items.map(\.url), anchor: anchor, target: item.url)
        } else {
            selection = [item.url]
            anchor = item.url
        }
    }

    private func open(_ item: DrawerItem) {
        if NSEvent.modifierFlags.contains(.option) { NSWorkspace.shared.open(item.url); return } // ⌥: Finder
        if item.isDirectory {
            selection = []
            model.query = ""
            model.open(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func rename(_ item: DrawerItem, to name: String) {
        if let url = try? model.rename(item, to: name) { selection = [url] }
    }

    private func trash(_ items: [DrawerItem]) {
        do { try model.trash(items.map(\.url)) } catch { Toast.show(error.localizedDescription) }
        selection.subtract(items.map(\.url))
    }

    @ViewBuilder private func menu(for items: [DrawerItem]) -> some View {
        if !items.isEmpty {
            Button("Open") { items.forEach(open) }
            if items.count == 1, let item = items.first, !item.isDirectory {
                Menu("Open With") {
                    ForEach(NSWorkspace.shared.urlsForApplications(toOpen: item.url), id: \.self) { app in
                        Button(FileManager.default.displayName(atPath: app.path)) {
                            NSWorkspace.shared.open([item.url], withApplicationAt: app, configuration: .init())
                        }
                    }
                }
            }
            Button("Quick Look") { QuickLook.show(items.map(\.url)) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url)) }
            if items.count == 1, let item = items.first, !settings.filesAsList { // List view has no inline editor
                Button("Rename") { selection = [item.url]; renaming = item.url }
            }
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects(items.map { $0.url as NSURL })
            }
            ShareLink("Share", items: items.map(\.url))
            Divider()
            Button("Move to Trash", role: .destructive) { trash(items) }
        }
    }

    private func handleKey(_ key: KeyPress) -> KeyPress.Result {
        guard renaming == nil, !searchFocused else { return .ignored }
        let items = model.items
        let index = items.firstIndex { selection.contains($0.url) }
        if key.modifiers.contains(.command) {
            switch key.key {
            case .upArrow: model.goUp(); selection = []; return .handled
            case .delete: trash(selectedItems); return .handled
            default: break
            }
            switch key.characters {
            case "o": selectedItems.forEach(open); return .handled
            case "1": settings.filesAsList = false; return .handled
            case "2": settings.filesAsList = true; return .handled
            default: return .ignored
            }
        }
        switch key.key {
        case .leftArrow, .upArrow, .rightArrow, .downArrow:
            guard !items.isEmpty else { return .handled }
            // ponytail: linear prev/next, not 2-D grid navigation
            let forward = key.key == .rightArrow || key.key == .downArrow
            let next = forward ? min((index ?? -1) + 1, items.count - 1) : max((index ?? 1) - 1, 0)
            selection = [items[next].url]
            return .handled
        case .return:
            if selectedItems.count == 1, !settings.filesAsList { renaming = selectedItems[0].url }
            return .handled
        case .space:
            QuickLook.show(selectedItems.map(\.url))
            return .handled
        default:
            return .ignored
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { settings.filesFolder = url }
    }
}

/// Drop target for the whole column: files (move/copy/alias by modifier), web links (download), raw images.
struct FilesDropDelegate: DropDelegate {
    let model: DrawerModel
    @Binding var targeted: Bool

    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let op: DropOperation = switch FileDropOperation.from(NSEvent.modifierFlags) {
        case .move: .move
        case .copy, .alias: .copy // SwiftUI has no .link badge; alias shows the copy (+) badge
        }
        return DropProposal(operation: op)
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        let op = FileDropOperation.from(NSEvent.modifierFlags)
        let dir = model.current
        for provider in info.itemProviders(for: [.fileURL, .url, .image]) {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let file = (url as NSURL).filePathURL ?? url // Finder may hand over file:///.file/id= references
                    Task { @MainActor in
                        do { _ = try model.drop([file], operation: op) } catch { Toast.show(error.localizedDescription) }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let suggested = provider.suggestedName ?? "Image"
                _ = provider.loadFileRepresentation(for: .image) { temp, _, _ in
                    // The temp file vanishes when this returns: stage it now, pick the final name on the main actor
                    // so simultaneous drops can't race for the same name.
                    guard let temp else { return }
                    let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    guard (try? FileManager.default.copyItem(at: temp, to: staged)) != nil else { return }
                    let ext = temp.pathExtension.isEmpty ? "png" : temp.pathExtension
                    let name = (suggested as NSString).pathExtension.isEmpty ? "\(suggested).\(ext)" : suggested
                    Task { @MainActor in
                        try? FileManager.default.moveItem(at: staged, to: uniqueDestination(for: name, in: dir))
                        model.reload()
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.scheme == "http" || url.scheme == "https" else { return }
                    Task { @MainActor in model.download(url) }
                }
            }
        }
        return true
    }
}
