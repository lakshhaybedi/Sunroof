import AppKit
import SwiftUI

enum Decoration: Equatable {
    case checkbox(range: NSRange, checked: Bool) // the "[ ]" characters
    case bullet(range: NSRange, level: Int)      // the "-" / "*" character
    case rule(lineRange: NSRange)
    case quoteBar(lineRange: NSRange)
    case conceal(range: NSRange)
    case image(lineRange: NSRange, url: URL)
}

extension NSAttributedString.Key {
    static let noteDecoration = NSAttributedString.Key("Sunroof.decoration")
    static let noteLink = NSAttributedString.Key("Sunroof.link")
}

/// Attribute value marking characters that are drawn as something else.
private final class DecorationBox: NSObject {
    enum Kind { case checkbox(Bool), bullet(Int), rule, quoteBar, conceal, image(URL) }
    let kind: Kind
    init(_ kind: Kind) { self.kind = kind }
}

/// Markdown editor: the text storage is always the exact markdown. Styling only sets attributes; checkboxes,
/// bullets, rules, quote bars, concealed text and images are drawn over (cleared) characters.
final class NoteTextView: NSTextView {
    /// Markers outside the span being edited are hidden: clear and (almost) zero-width.
    static let markerColor = NSColor.clear
    static let hiddenMarkerFont = NSFont.systemFont(ofSize: 0.1)
    static let activeMarkerColor = NSColor.secondaryLabelColor

    var fontSize: CGFloat = 14 { didSet { if oldValue != fontSize { restyleAll() } } }
    var noteFont: NoteFont = .system { didSet { if oldValue != noteFont { restyleAll() } } }
    /// Links, checked boxes and the caret.
    var accentColor: NSColor = .controlAccentColor {
        didSet { if oldValue != accentColor { insertionPointColor = accentColor; restyleAll() } }
    }
    var baseURL: URL?
    var onTextChange: ((String) -> Void)?
    /// Saves pasted/dropped image data and returns its markdown path (e.g. "attachments/x.png").
    var onImage: ((Data) -> String?)?
    static let hint = "Title on the first line · type [] and a space for a checkbox · select text for formatting"
    /// Shown in an empty note so the markdown shortcuts are discoverable.
    var placeholder: String? { string.isEmpty ? Self.hint : nil }
    var restyledLineCount = 0 // instrumentation for the incremental-restyle test
    var onFocus: (() -> Void)?

    private var pending: (location: Int, length: Int, fence: Bool)? // union of ranges changed in one edit
    private var caretLineStart: Int?
    private var revealed = Set<Int>()
    private var loading = false
    private let ownUndo = UndoManager()

    convenience init(fontSize: CGFloat) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        self.init(frame: NSRect(x: 0, y: 0, width: 400, height: 300), textContainer: container)
        self.fontSize = fontSize
        isRichText = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isContinuousSpellCheckingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        drawsBackground = false
        isVerticallyResizable = true
        autoresizingMask = [.width]
        textContainerInset = NSSize(width: 10, height: 10)
        typingAttributes = baseAttributes
    }

    override var undoManager: UndoManager? { super.undoManager ?? ownUndo }

    var currentEdit: TextEdit { TextEdit(text: string, selection: selectedRange()) }

    // MARK: - Loading & editing

    func load(_ text: String) {
        loading = true
        string = text
        revealed.removeAll()
        restyleAll()
        undoManager?.removeAllActions()
        loading = false
    }

    /// Applies a transform as one minimal, undoable replacement.
    func perform(_ edit: TextEdit) {
        let old = string as NSString, new = edit.text as NSString
        let minLen = min(old.length, new.length)
        var p = 0
        while p < minLen, old.character(at: p) == new.character(at: p) { p += 1 }
        var s = 0
        while s < minLen - p, old.character(at: old.length - 1 - s) == new.character(at: new.length - 1 - s) { s += 1 }
        let range = NSRange(location: p, length: old.length - p - s)
        let replacement = new.substring(with: NSRange(location: p, length: new.length - p - s))
        if range.length > 0 || !replacement.isEmpty {
            guard shouldChangeText(in: range, replacementString: replacement) else { return }
            textStorage?.replaceCharacters(in: range, with: replacement)
            didChangeText()
        }
        setSelectedRange(edit.selection)
    }

    override func shouldChangeText(in range: NSRange, replacementString s: String?) -> Bool {
        guard super.shouldChangeText(in: range, replacementString: s) else { return false }
        let removed = (string as NSString).substring(with: range)
        let new = (range.location, (s as NSString?)?.length ?? range.length,
                   removed.contains("```") || (s?.contains("```") ?? false))
        if let p = pending { // several ranges in one edit (Replace All): restyle their union
            let start = min(p.location, new.0)
            pending = (start, max(p.location + p.length, new.0 + new.1) - start, p.fence || new.2)
        } else {
            pending = new
        }
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }

    override func didChangeText() {
        super.didChangeText()
        if hasMarkedText() { revealed.removeAll(); return } // IME composing: restyle when the text is committed
        if let p = pending {
            restyle(paragraphsIn: NSRange(location: p.location, length: p.length), toEnd: p.fence)
            pending = nil
        }
        revealed.removeAll()
        if !loading { onTextChange?(string) }
    }

    override func unmarkText() {
        super.unmarkText()
        if let p = pending { restyle(paragraphsIn: NSRange(location: p.location, length: p.length)); pending = nil }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !hasMarkedText(), let ns = textStorage?.string as NSString? else { return }
        let start = ns.lineRange(for: NSRange(location: min(selectedRange().location, ns.length), length: 0)).location
        guard start != caretLineStart else {
            restyle(paragraphsIn: NSRange(location: start, length: 0)) // caret moved within the line: which span is active changed
            return
        }
        let old = caretLineStart
        caretLineStart = start
        if let old, old <= ns.length { restyle(paragraphsIn: NSRange(location: old, length: 0)) }
        restyle(paragraphsIn: NSRange(location: start, length: 0))
    }

    // MARK: - Commands

    override func insertNewline(_ sender: Any?) {
        if let e = ListEditing.newline(currentEdit) { perform(e) } else { super.insertNewline(sender) }
    }

    override func insertTab(_ sender: Any?) {
        if let e = ListEditing.indent(currentEdit, outdent: false) { perform(e) } else { super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        if let e = ListEditing.indent(currentEdit, outdent: true) { perform(e) } else { super.insertBacktab(sender) }
    }

    override func insertText(_ text: Any, replacementRange: NSRange) {
        super.insertText(text, replacementRange: replacementRange)
        if (text as? String) == " ", let e = ListEditing.expandShortcut(currentEdit) { perform(e) }
    }

    func toggleInline(open: String, close: String) { perform(ListEditing.toggleInline(currentEdit, open: open, close: close)) }
    func toggleBlock(_ change: BlockChange) { perform(ListEditing.toggleBlock(currentEdit, change)) }
    func moveLine(up: Bool) { perform(ListEditing.moveLine(currentEdit, up: up)) }

    // MARK: - Link entry

    private var linkField: NSView?
    private var linkTarget: NSRange?
    var isEnteringLink: Bool { linkTarget != nil }

    /// ⌘K / link button: a small field under the selection; Return inserts the link, Esc or clicking away cancels.
    func insertLink() {
        commitLink(nil)
        let sel = selectedRange()
        linkTarget = sel
        let length = (string as NSString).length
        let anchorRange = sel.length > 0 ? sel : NSRange(location: max(0, min(sel.location, length) - 1), length: length > 0 ? 1 : 0)
        let anchor = rect(for: anchorRange) ?? NSRect(x: textContainerOrigin.x, y: textContainerOrigin.y, width: 0, height: fontSize)
        let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suggested = clip.range(of: #"^(https?://|mailto:)\S+$"#, options: .regularExpression) != nil ? clip : ""
        let host = NSHostingView(rootView: LinkField(initial: suggested) { [weak self] url in self?.commitLink(url) })
        let size = NSSize(width: 300, height: 34)
        host.frame = NSRect(x: max(4, min(anchor.minX, bounds.width - size.width - 4)), y: anchor.maxY + 4,
                            width: size.width, height: size.height)
        addSubview(host)
        linkField = host
    }

    /// nil cancels.
    func commitLink(_ url: String?) {
        guard let target = linkTarget else { return }
        linkTarget = nil
        linkField?.removeFromSuperview()
        linkField = nil
        if let url, NSMaxRange(target) <= (string as NSString).length {
            perform(ListEditing.insertLink(TextEdit(text: string, selection: target), url: url))
        }
        window?.makeFirstResponder(self)
    }

    func toggleCheckbox(at location: Int) {
        let sel = selectedRange()
        perform(TextEdit(text: ListEditing.toggleCheckbox(lineContaining: location, in: string), selection: sel))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (flags, key, event.keyCode) {
        case ([.command], "b", _): toggleInline(open: "**", close: "**")
        case ([.command], "i", _): toggleInline(open: "*", close: "*")
        case ([.command], "u", _): toggleInline(open: "<u>", close: "</u>")
        case ([.command, .shift], "x", _): toggleInline(open: "~~", close: "~~")
        case ([.command, .shift], "h", _): toggleInline(open: "==", close: "==")
        case ([.command], "e", _): toggleInline(open: "`", close: "`")
        case ([.command], "k", _): insertLink()
        case ([.command], "1", _): toggleBlock(.heading(1))
        case ([.command], "2", _): toggleBlock(.heading(2))
        case ([.command], "3", _): toggleBlock(.heading(3))
        case ([.command, .shift], _, 28): toggleBlock(.bullet)    // ⌘⇧8
        case ([.command, .shift], _, 26): toggleBlock(.numbered)  // ⌘⇧7
        case ([.command, .shift], "l", _): toggleBlock(.checklist)
        case ([.command], "\r", _): toggleCheckbox(at: selectedRange().location)
        case ([.command, .option], _, 126): moveLine(up: true)
        case ([.command, .option], _, 125): moveLine(up: false)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: - Images

    override func paste(_ sender: Any?) {
        if !insertImage(from: .general) { super.paste(sender) }
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        insertImage(from: sender.draggingPasteboard) || super.performDragOperation(sender)
    }

    /// Image data (or an image file) without text → saved via `onImage` and inserted as its own line.
    private func insertImage(from pb: NSPasteboard) -> Bool {
        guard let onImage, pb.string(forType: .string) == nil else { return false }
        var data = pb.data(forType: .png) ?? pb.data(forType: .tiff).flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        if data == nil, let url = (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.first,
           NSImage(contentsOf: url) != nil, let rep = NSImage(contentsOf: url)?.tiffRepresentation {
            data = NSBitmapImageRep(data: rep)?.representation(using: .png, properties: [:])
        }
        guard let png = data, let path = onImage(png) else { return false }
        let sel = selectedRange()
        let insert = "\n![](\(path))\n"
        let text = (string as NSString).replacingCharacters(in: sel, with: insert)
        perform(TextEdit(text: text, selection: NSRange(location: sel.location + (insert as NSString).length, length: 0)))
        return true
    }

    // MARK: - Styling

    private var baseFont: NSFont { noteFont.font(ofSize: fontSize) }

    private var baseParagraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2
        p.paragraphSpacing = 4
        return p
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: baseParagraph]
    }

    func restyleAll() {
        restyle(paragraphsIn: NSRange(location: 0, length: (string as NSString).length), toEnd: true)
    }

    /// Restyles whole lines covering `range` (to the end of the document if a code fence may have changed).
    func restyle(paragraphsIn range: NSRange, toEnd: Bool = false) {
        guard let ts = textStorage else { return }
        let ns = ts.string as NSString
        let start = ns.lineRange(for: NSRange(location: min(range.location, ns.length), length: 0)).location
        var end = toEnd ? ns.length : NSMaxRange(ns.lineRange(for: NSRange(location: min(NSMaxRange(range), ns.length), length: 0)))
        var inCode = codeState(before: start, in: ns)
        let caretLocation = min(selectedRange().location, ns.length)
        let caretStart = ns.lineRange(for: NSRange(location: caretLocation, length: 0)).location
        ts.beginEditing()
        var loc = start
        repeat {
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            var content = line
            if content.length > 0, ns.character(at: NSMaxRange(content) - 1) == 10 { content.length -= 1 }
            ts.setAttributes(baseAttributes, range: line)
            let text = ns.substring(with: content)
            let fence = MarkdownStyler.isFence(text)
            style(content, text: text, inCode: inCode, caret: line.location == caretStart,
                  caretInLine: caretLocation - content.location, in: ts)
            if fence { inCode.toggle(); end = ns.length } // a fence changes everything below it
            restyledLineCount += 1
            loc = NSMaxRange(line)
        } while loc < end
        ts.endEditing()
        typingAttributes = baseAttributes
        needsDisplay = true
    }

    private func codeState(before location: Int, in ns: NSString) -> Bool {
        var inCode = false
        var search = NSRange(location: 0, length: location)
        while true {
            let r = ns.range(of: "```", range: search)
            guard r.location != NSNotFound else { break }
            let line = ns.lineRange(for: r)
            if MarkdownStyler.isFence(ns.substring(with: line).trimmingCharacters(in: .newlines)) { inCode.toggle() }
            let next = NSMaxRange(line)
            guard next < location else { break }
            search = NSRange(location: next, length: location - next)
        }
        return inCode
    }

    private func style(_ content: NSRange, text: String, inCode: Bool, caret: Bool, caretInLine: Int, in ts: NSTextStorage) {
        let style = MarkdownStyler.parse(text, inCodeBlock: inCode)
        // Inline markers show only for the span the caret is in (open marker … close marker).
        var markerGroup: [NSRange: NSRange] = [:]
        let spans = style.spans
        for i in spans.indices.dropFirst().dropLast() where spans[i].kind != .marker {
            let (o, c) = (spans[i - 1], spans[i + 1])
            guard o.kind == .marker, c.kind == .marker, NSMaxRange(o.range) == spans[i].range.location,
                  NSMaxRange(spans[i].range) == c.range.location else { continue }
            let group = NSUnionRange(o.range, c.range)
            markerGroup[o.range] = group
            markerGroup[c.range] = group
        }
        func markerActive(_ local: NSRange) -> Bool {
            guard caret else { return false }
            guard let g = markerGroup[local] else { return true } // block markers ("# ", "> ") show on the caret line
            return caretInLine >= g.location && caretInLine <= NSMaxRange(g)
        }
        let at = { (r: NSRange) in NSRange(location: content.location + r.location, length: r.length) }
        let indent = text.prefix { $0 == "\t" || $0 == " " }.utf16.count
        let blockMarker = style.spans.first { $0.kind == .marker && $0.range.location == 0 }.map { at($0.range) }
        var handledBlockMarker = false
        func clear(_ r: NSRange) { ts.addAttribute(.foregroundColor, value: NSColor.clear, range: r) }
        func decorate(_ r: NSRange, _ kind: DecorationBox.Kind) { ts.addAttribute(.noteDecoration, value: DecorationBox(kind), range: r) }

        switch style.block {
        case let .heading(n):
            let scale: CGFloat = [1.6, 1.35, 1.15][min(n, 3) - 1]
            ts.addAttribute(.font, value: noteFont.font(ofSize: fontSize * scale, weight: .bold), range: content)
        case .fence:
            ts.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: fontSize * 0.92, weight: .regular),
                              .foregroundColor: caret ? Self.activeMarkerColor : Self.markerColor], range: content)
            handledBlockMarker = true
        case .code:
            ts.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: fontSize * 0.92, weight: .regular),
                              .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.15)], range: content)
        case .quote:
            ts.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: content)
            let p = baseParagraph.mutableCopy() as! NSMutableParagraphStyle
            p.firstLineHeadIndent = 14 // room for the bar (the "> " marker is hidden)
            p.headIndent = 14
            ts.addAttribute(.paragraphStyle, value: p, range: content)
            decorate(content, .quoteBar)
        case .paragraph where content.location == 0:
            // The first line is the note's title.
            ts.addAttribute(.font, value: noteFont.font(ofSize: fontSize * 1.3, weight: .bold), range: content)
        case .rule where !caret:
            clear(content)
            decorate(content, .rule)
            handledBlockMarker = true
        case let .image(path) where !caret:
            if let url = URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL?.appendingPathComponent(path) {
                clear(content)
                let p = baseParagraph.mutableCopy() as! NSMutableParagraphStyle
                p.minimumLineHeight = imageHeight(url)
                ts.addAttribute(.paragraphStyle, value: p, range: content)
                decorate(content, .image(url))
                handledBlockMarker = true
            }
        case let .bullet(level) where !caret:
            let dash = NSRange(location: content.location + indent, length: 1)
            clear(dash)
            decorate(dash, .bullet(level))
            handledBlockMarker = true
        case let .checklist(_, checked) where !caret:
            let marker = NSRange(location: content.location + indent, length: 2)
            let box = NSRange(location: content.location + indent + 2, length: 3)
            clear(NSUnionRange(marker, box))
            decorate(box, .checkbox(checked))
            handledBlockMarker = true
        case .numbered:
            if let blockMarker { ts.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: blockMarker) }
            handledBlockMarker = true
        default:
            break
        }
        if case .checklist(_, true) = style.block, let blockMarker {
            let rest = NSRange(location: NSMaxRange(blockMarker), length: NSMaxRange(content) - NSMaxRange(blockMarker))
            ts.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                              .foregroundColor: NSColor.secondaryLabelColor], range: rest)
        }

        for span in style.spans {
            let r = at(span.range)
            switch span.kind {
            case .marker:
                if handledBlockMarker, r == blockMarker { continue }
                if markerActive(span.range) {
                    ts.addAttribute(.foregroundColor, value: Self.activeMarkerColor, range: r)
                } else {
                    ts.addAttributes([.foregroundColor: Self.markerColor, .font: Self.hiddenMarkerFont], range: r)
                }
            case .bold: addTrait(.boldFontMask, r, ts)
            case .italic: addTrait(.italicFontMask, r, ts)
            case .strike: ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            case .underline: ts.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            case .highlight: ts.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: r)
            case .code:
                ts.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: fontSize * 0.92, weight: .regular),
                                  .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.3)], range: r)
            case .conceal where !revealed.contains(r.location):
                clear(r)
                decorate(r, .conceal)
            case .conceal: break
            case let .link(url):
                ts.addAttributes([.foregroundColor: accentColor, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                  .noteLink: url, .toolTip: Self.hint(for: url)], range: r)
            }
        }
    }

    private func addTrait(_ trait: NSFontTraitMask, _ r: NSRange, _ ts: NSTextStorage) {
        ts.enumerateAttribute(.font, in: r) { value, sub, _ in
            let font = (value as? NSFont) ?? baseFont
            ts.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: sub)
        }
    }

    private func imageHeight(_ url: URL) -> CGFloat {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat, let h = props[kCGImagePropertyPixelHeight] as? CGFloat, w > 0
        else { return fontSize * 1.4 }
        let width = min(w / 2, max(textContainer?.size.width ?? 400, 100) - 20)
        return min(width * h / w, 320)
    }

    // MARK: - Decorations

    var decorations: [Decoration] {
        guard let ts = textStorage else { return [] }
        var out: [Decoration] = []
        ts.enumerateAttribute(.noteDecoration, in: NSRange(location: 0, length: ts.length)) { value, r, _ in
            guard let box = value as? DecorationBox else { return }
            switch box.kind {
            case let .checkbox(c): out.append(.checkbox(range: r, checked: c))
            case let .bullet(l): out.append(.bullet(range: r, level: l))
            case .rule: out.append(.rule(lineRange: r))
            case .quoteBar: out.append(.quoteBar(lineRange: r))
            case .conceal: out.append(.conceal(range: r))
            case let .image(u): out.append(.image(lineRange: r, url: u))
            }
        }
        return out
    }

    /// Rect of the first line of the selection, in view coordinates (for the formatting bar).
    var selectionRect: NSRect? {
        let sel = selectedRange()
        guard sel.length > 0 else { return nil }
        let ns = string as NSString
        let firstLine = NSIntersectionRange(sel, ns.lineRange(for: NSRange(location: sel.location, length: 0)))
        return rect(for: firstLine.length > 0 ? firstLine : sel)
    }

    private func rect(for range: NSRange) -> NSRect? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return lm.boundingRect(forGlyphRange: glyphs, in: tc).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let placeholder {
            (placeholder as NSString).draw(at: NSPoint(x: textContainerOrigin.x + 5, y: textContainerOrigin.y),
                                           withAttributes: [.font: baseFont, .foregroundColor: NSColor.placeholderTextColor])
        }
        guard let lm = layoutManager, let tc = textContainer, let ts = textStorage, ts.length > 0 else { return }
        let glyphs = lm.glyphRange(forBoundingRect: visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y), in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        ts.enumerateAttribute(.noteDecoration, in: chars) { value, range, _ in
            guard let box = value as? DecorationBox, let r = rect(for: range) else { return }
            drawDecoration(box.kind, in: r)
        }
    }

    private func drawDecoration(_ kind: DecorationBox.Kind, in r: NSRect) {
        switch kind {
        case let .checkbox(checked):
            let config = NSImage.SymbolConfiguration(pointSize: fontSize, weight: .regular)
                .applying(.init(paletteColors: [checked ? accentColor : .secondaryLabelColor]))
            guard let img = NSImage(systemSymbolName: checked ? "checkmark.square.fill" : "square", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return }
            let s = img.size
            img.draw(in: NSRect(x: r.minX, y: r.midY - s.height / 2, width: s.width, height: s.height))
        case let .bullet(level):
            let glyph = ["•", "◦", "▪"][level % 3] as NSString
            glyph.draw(at: NSPoint(x: r.minX, y: r.minY), withAttributes: [.font: baseFont, .foregroundColor: NSColor.secondaryLabelColor])
        case .rule:
            NSColor.separatorColor.setFill()
            NSRect(x: textContainerOrigin.x, y: r.midY, width: bounds.width - textContainerOrigin.x * 2, height: 1).fill()
        case .quoteBar:
            accentColor.withAlphaComponent(0.6).setFill()
            let x = textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 5) + 2
            NSBezierPath(roundedRect: NSRect(x: x, y: r.minY, width: 3, height: r.height), xRadius: 1.5, yRadius: 1.5).fill()
        case .conceal:
            ("••••" as NSString).draw(at: NSPoint(x: r.minX, y: r.minY),
                                     withAttributes: [.font: baseFont, .foregroundColor: NSColor.secondaryLabelColor])
        case let .image(url):
            guard let img = ThumbnailCache.shared.thumbnail(for: url, maxPixelSize: 1200) else { return }
            let h = r.height - 4, w = min(h * CGFloat(img.width) / CGFloat(img.height), bounds.width - 40)
            let ns = NSImage(cgImage: img, size: NSSize(width: w, height: w * CGFloat(img.height) / CGFloat(img.width)))
            ns.draw(in: NSRect(x: r.minX, y: r.minY + 2, width: ns.size.width, height: ns.size.height))
        }
    }

    // MARK: - Mouse

    /// Tooltip text for a link under the pointer.
    func linkHint(forCharacterAt i: Int) -> String? {
        guard let ts = textStorage, i >= 0, i < ts.length, let url = ts.attribute(.noteLink, at: i, effectiveRange: nil) as? URL
        else { return nil }
        return Self.hint(for: url)
    }

    static func hint(for url: URL) -> String {
        if url.scheme == "mailto" { return "⌘-click to email \(url.absoluteString.dropFirst(7))" }
        let host = url.host()?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
        return "⌘-click to open \(host) in your browser"
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.userInfo?["links"] != nil }.forEach(removeTrackingArea)
        // .activeAlways: the shelf belongs to an app that usually isn't active.
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: ["links": true]))
    }

    // Tooltips come from the .toolTip text attribute; this only shows the hand cursor while ⌘ is held over a link.
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateLinkCursor(event.modifierFlags, at: convert(event.locationInWindow, from: nil))
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard let window else { return }
        updateLinkCursor(event.modifierFlags, at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func updateLinkCursor(_ flags: NSEvent.ModifierFlags, at p: NSPoint) {
        guard flags.contains(.command), characterIndex(at: p).flatMap({ linkHint(forCharacterAt: $0) }) != nil else { return }
        NSCursor.pointingHand.set()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let (kind, range) = decoration(at: p) {
            switch kind {
            case .checkbox: toggleCheckbox(at: range.location); return
            case .conceal:
                revealed.insert(range.location)
                restyle(paragraphsIn: range)
                return
            default: break
            }
        }
        if event.modifierFlags.contains(.command), let url = attribute(.noteLink, at: p) as? URL {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    private func characterIndex(at p: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer, let ts = textStorage, ts.length > 0 else { return nil }
        let local = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        return min(lm.characterIndex(for: local, in: tc, fractionOfDistanceBetweenInsertionPoints: nil), ts.length - 1)
    }

    private func attribute(_ key: NSAttributedString.Key, at p: NSPoint) -> Any? {
        characterIndex(at: p).flatMap { textStorage?.attribute(key, at: $0, effectiveRange: nil) }
    }

    private func decoration(at p: NSPoint) -> (DecorationBox.Kind, NSRange)? {
        guard let i = characterIndex(at: p), let ts = textStorage else { return nil }
        var range = NSRange()
        guard let box = ts.attribute(.noteDecoration, at: i, effectiveRange: &range) as? DecorationBox,
              let r = rect(for: range), r.insetBy(dx: -4, dy: -2).contains(p) else { return nil }
        return (box.kind, range)
    }
}

/// The small "paste a link" field shown under the selection.
private struct LinkField: View {
    @State var url: String
    let onDone: (String?) -> Void
    @FocusState private var focused: Bool
    @State private var done = false

    init(initial: String, onDone: @escaping (String?) -> Void) {
        _url = State(initialValue: initial)
        self.onDone = onDone
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "link").foregroundStyle(.secondary)
            TextField("Paste a link and press Return", text: $url)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { finish(url) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .overlay(Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 1))
        .onAppear { focused = true }
        .onChange(of: focused) { _, f in if !f { finish(nil) } } // Esc / click away
    }

    private func finish(_ value: String?) {
        guard !done else { return }
        done = true
        onDone(value)
    }
}
