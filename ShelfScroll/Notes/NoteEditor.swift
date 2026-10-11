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

    static let welcome = "Welcome to ShelfScroll\n\n- [ ] Try a checklist\n- **Bold**, *italic*, ==highlight==\n1. Numbered lists renumber themselves"

    init(store: NoteStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
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
        onTextView(tv)
        context.coordinator.attach(tv)
        load(tv, context: context, selection: selection)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NoteTextView else { return }
        onTextView(tv)
        tv.fontSize = fontSize
        if context.coordinator.filename != filename {
            load(tv, context: context, selection: 0)
        } else if let note = store.note(filename), note.revision != context.coordinator.revision {
            context.coordinator.revision = note.revision // replaced from disk (sync) or appended — reload, keep caret
            let sel = tv.selectedRange()
            tv.load(note.text)
            tv.setSelectedRange(NSRange(location: min(sel.location, (note.text as NSString).length), length: 0))
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) { coordinator.detach() }

    private func load(_ tv: NoteTextView, context: Context, selection: Int) {
        context.coordinator.filename = filename
        context.coordinator.revision = store.note(filename)?.revision ?? 0
        let (store, filename) = (store, filename)
        tv.onFocus = onFocus
        tv.baseURL = store.folder.appendingPathComponent("/", isDirectory: true)
        tv.onTextChange = { text in store.update(filename, text: text) }
        tv.onImage = { store.saveAttachment($0, for: filename) }
        let text = store.note(filename)?.text ?? ""
        tv.load(text)
        tv.setSelectedRange(NSRange(location: min(selection, (text as NSString).length), length: 0))
        tv.scrollRangeToVisible(tv.selectedRange())
    }

    /// Shows the floating formatting bar above a non-empty selection.
    @MainActor final class Coordinator: NSObject {
        var filename: String?
        var revision = 0
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
