import AppKit
import SwiftUI

struct NotesPanel: View {
    let controller: NotesController
    var onFloat: ((String) -> Void)? = nil
    @State private var searching = false
    @State private var query = ""
    @State private var hovering = false
    @State private var selection: String?
    @FocusState private var listFocused: Bool
    @FocusState private var searchFocused: Bool

    private var store: NoteStore { controller.store }
    private var settings: AppSettings { controller.settings }
    private var showList: Bool { settings.notesShowList || controller.current == nil }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Notes") {
                HeaderButton(symbol: "plus", help: "New Note") { controller.newNote() }
                HeaderButton(symbol: "checklist", help: "Checklist (⇧⌘L) — or type [] and a space") {
                    if showList { controller.newNote() }
                    DispatchQueue.main.async { controller.textView?.toggleBlock(.checklist); controller.focus() }
                }
                HeaderButton(symbol: "list.bullet", help: "All Notes", active: showList) { toggleList() }
                HeaderButton(symbol: "magnifyingglass", help: "Search", active: searching) {
                    searching.toggle()
                    if searching { settings.notesShowList = true; searchFocused = true } else { query = "" }
                }
                formatMenu
            }
            if searching {
                TextField("Search notes", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(.horizontal, 8).padding(.bottom, 6)
            }
            Divider()
            if showList { list } else if let current = controller.current {
                NoteEditor(store: store, filename: current, fontSize: settings.noteFontSize,
                           noteFont: settings.noteFont, accent: settings.accent.nsColor,
                           selection: settings.lastNoteSelection,
                           onTextView: { controller.textView = $0 },
                           onFocus: { settings.lastPanel = .notes })
            }
        }
        .onAppear { if controller.current == nil { controller.restore() } }
        .onHover { hovering = $0 }
        .onModifierKeysChanged(mask: [.control, .shift]) { _, new in
            if hovering, new == [.control, .shift] { toggleList() }
        }
        .gesture(MagnifyGesture().onEnded { value in
            if value.magnification < 0.85 { settings.notesShowList = true }
            else if value.magnification > 1.15, controller.current != nil { settings.notesShowList = false }
        })
    }

    private func toggleList() {
        if !showList { controller.finish() }
        settings.notesShowList.toggle()
        if !settings.notesShowList { DispatchQueue.main.async { controller.focus() } }
    }

    private var formatMenu: some View {
        Menu {
            Button("Bold (⌘B)") { controller.textView?.toggleInline(open: "**", close: "**") }
            Button("Italic (⌘I)") { controller.textView?.toggleInline(open: "*", close: "*") }
            Button("Underline (⌘U)") { controller.textView?.toggleInline(open: "<u>", close: "</u>") }
            Button("Strikethrough (⇧⌘X)") { controller.textView?.toggleInline(open: "~~", close: "~~") }
            Button("Highlight (⇧⌘H)") { controller.textView?.toggleInline(open: "==", close: "==") }
            Button("Code (⌘E)") { controller.textView?.toggleInline(open: "`", close: "`") }
            Button("Link (⌘K)") { controller.textView?.insertLink() }
            Button("Conceal") { controller.textView?.toggleInline(open: "||", close: "||") }
            Divider()
            Button("Heading 1 (⌘1)") { controller.textView?.toggleBlock(.heading(1)) }
            Button("Heading 2 (⌘2)") { controller.textView?.toggleBlock(.heading(2)) }
            Button("Heading 3 (⌘3)") { controller.textView?.toggleBlock(.heading(3)) }
            Divider()
            Button("Bulleted List (⇧⌘8)") { controller.textView?.toggleBlock(.bullet) }
            Button("Numbered List (⇧⌘7)") { controller.textView?.toggleBlock(.numbered) }
            Button("Checklist (⇧⌘L)") { controller.textView?.toggleBlock(.checklist) }
        } label: {
            Image(systemName: "textformat").foregroundStyle(.secondary)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .disabled(showList)
        .help("Format")
    }

    // MARK: - List

    private var notes: [Note] { store.search(query) }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(notes) { note in
                    NoteRow(note: note, pinned: store.pinned.contains(note.filename), selected: (selection ?? controller.current) == note.filename,
                            onDelete: { controller.delete(note.filename) })
                        .contentShape(Rectangle())
                        .onTapGesture { controller.open(note.filename); DispatchQueue.main.async { controller.focus() } }
                        .contextMenu {
                            Button(store.pinned.contains(note.filename) ? "Unpin" : "Pin") { store.togglePin(note.filename) }
                            if let onFloat { Button("Float as Sticky") { onFloat(note.filename) } }
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([store.folder.appendingPathComponent(note.filename)])
                            }
                            Button("Duplicate") { store.duplicate(note.filename) }
                            Divider()
                            Button("Move to Trash", role: .destructive) { controller.delete(note.filename) }
                        }
                    Divider()
                }
                if notes.isEmpty {
                    Text(query.isEmpty ? "No notes yet." : "No matches.").foregroundStyle(.secondary).padding(.top, 30)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onKeyPress(phases: .down) { key in
            guard !searchFocused else { return .ignored }
            let names = notes.map(\.filename)
            let i = selection.flatMap { names.firstIndex(of: $0) }
            switch key.key {
            case .downArrow: if !names.isEmpty { selection = names[min((i ?? -1) + 1, names.count - 1)] }; return .handled
            case .upArrow: if !names.isEmpty { selection = names[max((i ?? 1) - 1, 0)] }; return .handled
            case .return, .space:
                if let selection { controller.open(selection); DispatchQueue.main.async { controller.focus() } }
                return .handled
            default: return .ignored
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let pinned: Bool
    let selected: Bool
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange) }
                    Text(note.title.isEmpty ? "Untitled" : note.title).font(.body.weight(.semibold)).lineLimit(1)
                }
                if !note.preview.isEmpty {
                    Text(note.preview).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(note.modified.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if hovering {
                Button(action: onDelete) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Move to Trash")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.primary.opacity(0.08) : .clear)
        .onHover { hovering = $0 }
    }
}
