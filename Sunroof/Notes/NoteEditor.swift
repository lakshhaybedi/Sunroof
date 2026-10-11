import AppKit
import Observation
import SwiftUI

/// Owns which note is open and the live text view, so the shelf can focus it and finish editing on hide.
@MainActor @Observable
final class NotesController {
    let store: NoteStore
    let settings: AppSettings
    private(set) var current: String?
    @ObservationIgnored weak var textView: NoteTextView?

    static let welcome = """
    Welcome to Sunroof

    - [ ] Click a box to tick it — type [] and a space (or ⇧⌘L, or the ☑︎ button above) to add one
    - [ ] Select text for the formatting bar: **bold**, *italic*, ==highlight==, `code`
    1. Numbered lists renumber themselves; Tab indents
    """

    init(store: NoteStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        // Follow renames/deletes made elsewhere (a sticky, the list, sync).
        store.onRename.append { [weak self] old, new in
            guard let self, self.current == old else { return }
            self.current = new
            self.settings.lastNote = new
        }
        store.onDelete.append { [weak self] name in
            guard let self, self.current == name else { return }
            self.current = self.store.notes.first?.filename
        }
    }

    /// Last note, else the newest, else a welcome note.
    func restore() {
        if let last = settings.lastNote, store.note(last) != nil { current = last; return }
        current = store.notes.first?.filename ?? store.create(text: Self.welcome).filename
    }

    func open(_ filename: String) {
        finish()
        current = filename
        settings.lastNote = filename
        settings.lastNoteSelection = 0
        settings.notesShowList = false
    }

    func newNote() {
        let note = store.create()
        open(note.filename)
        focus()
    }

    /// Saves, applies a title rename, remembers the caret.
    func finish() {
        guard let name = current else { return }
        if let tv = textView { settings.lastNoteSelection = tv.selectedRange().location }
        let renamed = store.finishEditing(name)
        if renamed != name { current = renamed; settings.lastNote = renamed }
    }

    func focus() {
        guard !settings.notesShowList, let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
    }

    func delete(_ filename: String) {
        try? store.delete(filename)
        if current == filename { current = store.notes.first?.filename }
    }
}

/// Connects one text view to one note. Every keystroke goes to the store tagged with this editor's id;
/// when anyone else changes the note (another editor, sync, Send to Note) the text view reloads, keeping the caret.
@MainActor
final class NoteEditorBinding {
    let id = UUID()
    let store: NoteStore
    let textView: NoteTextView
    private(set) var filename: String
    private var seenRevision = -1
    private var observation = 0

    init(store: NoteStore, textView: NoteTextView, filename: String, selection: Int = 0) {
        self.store = store
        self.textView = textView
        self.filename = filename
        bind()
        load(selection: selection)
        observe()
    }

    /// Switch notes. A rename (same text under a new name) keeps the caret and undo instead of reloading.
    func setFilename(_ new: String) {
        guard new != filename else { return }
        filename = new
        bind()
        if let note = store.note(new), note.text == textView.string { seenRevision = note.revision }
        else { load(selection: 0) }
        observe()
    }

    func storeDidChange() {
        guard let note = store.note(filename), note.revision != seenRevision else { return }
        seenRevision = note.revision
        guard note.lastWriter != id else { return } // our own keystroke
        let sel = textView.selectedRange()
        textView.load(note.text)
        textView.setSelectedRange(NSRange(location: min(sel.location, (note.text as NSString).length), length: 0))
    }

    private func bind() {
        let store = store
        textView.baseURL = store.folder.appendingPathComponent("/", isDirectory: true)
        textView.onTextChange = { [weak self] text in
            guard let self else { return }
            store.update(self.filename, text: text, from: self.id)
        }
        textView.onImage = { [weak self] png in self.map { store.saveAttachment(png, for: $0.filename) } }
    }

    private func load(selection: Int) {
        let note = store.note(filename)
        seenRevision = note?.revision ?? 0
        let text = note?.text ?? ""
        textView.load(text)
        textView.setSelectedRange(NSRange(location: min(selection, (text as NSString).length), length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// Re-arms after each change; `observation` drops chains from before a filename switch.
    private func observe() {
        observation += 1
        let token = observation
        withObservationTracking { _ = store.note(filename)?.revision } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observation == token else { return }
                self.storeDidChange()
                self.observe()
            }
        }
    }
}

struct NoteEditor: NSViewRepresentable {
    let store: NoteStore
    let filename: String
    let fontSize: CGFloat
    var selection = 0
    var onTextView: (NoteTextView) -> Void = { _ in }
    var onFocus: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = NoteTextView(fontSize: fontSize)
        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.onFocus = onFocus
        onTextView(tv)
        context.coordinator.binding = NoteEditorBinding(store: store, textView: tv, filename: filename, selection: selection)
        context.coordinator.attach(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NoteTextView else { return }
        onTextView(tv)
        tv.onFocus = onFocus
        tv.fontSize = fontSize
        context.coordinator.binding?.setFilename(filename)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) { coordinator.detach() }

    /// Owns the binding and shows the floating formatting bar above a non-empty selection.
    @MainActor final class Coordinator: NSObject {
        var binding: NoteEditorBinding?
        private var bar: NSHostingView<FormatBar>?
        private var observer: Any?

        func attach(_ tv: NoteTextView) {
            observer = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification, object: tv,
                                                              queue: .main) { [weak self, weak tv] _ in
                MainActor.assumeIsolated {
                    guard let self, let tv else { return }
                    self.update(tv)
                }
            }
        }

        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            binding = nil
        }

        private func update(_ tv: NoteTextView) {
            guard let r = tv.selectionRect else { bar?.removeFromSuperview(); bar = nil; return }
            let host = bar ?? NSHostingView(rootView: FormatBar { [weak tv] in tv })
            if bar == nil { tv.addSubview(host); bar = host }
            let size = host.fittingSize
            host.frame = NSRect(x: max(4, min(r.minX, tv.bounds.width - size.width - 4)),
                                y: max(0, r.minY - size.height - 8), width: size.width, height: size.height)
        }
    }
}

/// B I U S · highlight · code · link · conceal · H1 H2 H3 · bullets · numbers · checklist
struct FormatBar: View {
    let target: () -> NoteTextView?

    var body: some View {
        HStack(spacing: 2) {
            button("bold", "Bold") { $0.toggleInline(open: "**", close: "**") }
            button("italic", "Italic") { $0.toggleInline(open: "*", close: "*") }
            button("underline", "Underline") { $0.toggleInline(open: "<u>", close: "</u>") }
            button("strikethrough", "Strikethrough") { $0.toggleInline(open: "~~", close: "~~") }
            Divider().frame(height: 16)
            button("highlighter", "Highlight") { $0.toggleInline(open: "==", close: "==") }
            button("chevron.left.forwardslash.chevron.right", "Code") { $0.toggleInline(open: "`", close: "`") }
            button("link", "Link") { $0.insertLink() }
            button("eye.slash", "Conceal") { $0.toggleInline(open: "||", close: "||") }
            Divider().frame(height: 16)
            text("H1") { $0.toggleBlock(.heading(1)) }
            text("H2") { $0.toggleBlock(.heading(2)) }
            text("H3") { $0.toggleBlock(.heading(3)) }
            Divider().frame(height: 16)
            button("list.bullet", "Bulleted List") { $0.toggleBlock(.bullet) }
            button("list.number", "Numbered List") { $0.toggleBlock(.numbered) }
            button("checklist", "Checklist") { $0.toggleBlock(.checklist) }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
    }

    private func button(_ symbol: String, _ help: String, _ action: @escaping (NoteTextView) -> Void) -> some View {
        Button { target().map(action) } label: { Image(systemName: symbol).frame(width: 22, height: 22) }
            .buttonStyle(.plain).help(help)
    }

    private func text(_ label: String, _ action: @escaping (NoteTextView) -> Void) -> some View {
        Button { target().map(action) } label: { Text(label).font(.caption.bold()).frame(width: 22, height: 22) }
            .buttonStyle(.plain)
    }
}
