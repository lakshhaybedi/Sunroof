# ShelfScroll Cross-Panel Features Implementation Plan (5 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The three features that span panels — Send to Note (M), global search across Clipboard / Files / Notes (N), and floating sticky notes (L).

**Architecture:** Each feature is a small pure core with tests plus thin UI: `NoteStore.append` (text/image into a note), a `GlobalSearch` model fed by three provider closures, and a `StickyManager` that opens `NSPanel`s hosting the existing note editor. Panels still don't import each other: `AppDelegate` wires closures.

**Tech Stack:** Swift 6, SwiftUI + AppKit, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-11-shelfscroll-design.md` (§4 global search, §5 Send to Note, §7 stickies + Send to Note, §9)

## Global Constraints

- Prior plans' Global Constraints apply.
- **Global search shortcut is ⌘⇧F** (not the spec's ⌘K): ⌘K is "insert link" in the notes editor, which has focus most of the time. (Ruling recorded in the ledger.)
- Global search: debounced 150 ms; at most 5 results per section; sections in order Clipboard, Files, Notes; Files search runs off the main thread.
- Send to Note appends `"\n\n" + text` (no extra blank lines if the note already ends with a newline); image clips are copied into `attachments/` and appended as `![](path)`; file clips append one `[name](file://…)` link per file; a new note from a clip uses the clip's first line (≤ 60 chars) as title.
- Stickies: `NSPanel` (`.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel`), level `.floating`, `[.canJoinAllSpaces, .fullScreenAuxiliary]`, default 280×320, title = note title; frames persisted in `AppSettings.stickies: [String: String]` (filename → `NSStringFromRect`); reopened at launch; closing a sticky never deletes the note; renames follow the note.

## Review Focus

1. **Same note open in the shelf and in a sticky, typing in both.** Expect: no text lost; the other editor reflects changes. → Task 3 manual + store-level test of two updates.
2. **Send to Note into the note that's open in the editor.** Expect: the appended text appears in the editor; nothing the user typed is dropped. → Task 1 test (store) + checklist.
3. **Sticky for a note that's deleted or renamed elsewhere.** Expect: rename → sticky follows; delete → sticky closes; no crash at launch for a missing note. → Task 3 tests.
4. **Global search while a folder enumeration is slow** (huge Files root). Expect: typing stays responsive; stale results never replace newer ones. → Task 2 test.
5. **Esc with the search overlay open.** Expect: closes the overlay, not the shelf. → Task 2 manual/checklist.

---

### Task 1: Send to Note

**Files:** Modify `Notes/NoteStore.swift`, `Clipboard/ClipboardPanel.swift`, `App/AppDelegate.swift`; Create `Shared/NoteAppending.swift`; Test: extend `NoteStoreTests`.

**Interfaces — Produces:**
```swift
@MainActor protocol NoteAppending: AnyObject {
  var recentNoteTitles: [(filename: String, title: String)] { get }   // 8 most recent
  @discardableResult func append(_ text: String, to filename: String?) -> String          // nil → new note; returns filename
  @discardableResult func appendImage(_ png: Data, to filename: String?) -> String
}
extension NoteStore: NoteAppending
static func NoteStore.appending(_ addition: String, to text: String) -> String
```
`ClipboardPanel` gains `init(…, notes: NoteAppending?)`; context menu `Menu("Send to Note")` with recent titles + Divider + "New Note". Text-like clips append `text`; images read the PNG via `store.imageURL(for:)` → `appendImage`; files append markdown links; sensitive clips are excluded (no menu item). Toast "Added to <title>".

- [ ] **Step 1: Failing tests:** `appendingSeparates` (`"A"` + `"x"` → `"A\n\nx"`; `"A\n"` + `"x"` → `"A\n\nx"`; `""` + `"x"` → `"x"`), `appendToExistingSaves` (file contains appended text after `saveAll`), `appendToNewNoteUsesFirstLineAsTitle` (`append("Buy milk\nand eggs", to: nil)` → note text `"Buy milk\nand eggs"`), `appendImageCopiesAttachment` (text ends with `![](attachments/<base>-1.png)` and file exists), `appendWhileDirtyKeepsBoth` *(Review Focus 2)*: `update(f, "A\ntyped")` then `append("clip", to: f)` → text `"A\ntyped\n\nclip"`.
- [ ] **Step 2: Run** `./test.sh NoteStoreTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** full suite. Expected: PASS.
- [ ] **Step 5: Commit** `feat: send clipboard clips to a note`.

---

### Task 2: Global search

**Files:** Create `Shell/GlobalSearch.swift`, `Shell/GlobalSearchView.swift`; Modify `Shell/ShelfController.swift`, `Files/DrawerModel.swift` (expose `static func search(_:in:) -> [URL]` as internal), `App/AppDelegate.swift`; Test `GlobalSearchTests.swift`.

**Interfaces — Produces:**
```swift
enum SearchHit: Identifiable, Equatable {
  case clip(Clip), file(URL), note(filename: String, title: String, preview: String)
  var id: String { get }
}
struct SearchSection: Identifiable, Equatable { let id: PanelID; let title: String; let hits: [SearchHit] }
@MainActor @Observable final class GlobalSearch {
  init(clips: @escaping (String) -> [Clip], notes: @escaping (String) -> [Note], files: @escaping @Sendable (String) -> [URL])
  var isVisible: Bool
  var query: String                   // didSet → debounced search
  private(set) var sections: [SearchSection]
  var selection: Int                  // flat index across sections
  var selectedHit: SearchHit? { get }
  func moveSelection(by delta: Int)   // clamps
  func settled() async                // await pending search (tests)
  static let perSection = 5
}
// ShelfController: var onGlobalSearch: (() -> Void)?; var escapeHandlers: [() -> Bool]  (first true consumes Esc)
//                  func setOverlay(_ view: NSView?)  — pinned to the top of the strip over the columns
```
⌘⇧F in the shelf's local key monitor → `onGlobalSearch`. `GlobalSearchView`: search field (auto-focused) + grouped results (clip row = app icon + 1-line text; file = Finder icon + name + parent folder; note = title + preview), ↑/↓ via `moveSelection`, ⏎ acts (clip → `paster.paste`; file → `NSWorkspace.open`; note → `notes.open` + note view + focus), click acts too. Esc → registered escape handler hides the overlay.

- [ ] **Step 1: Failing tests** (fake providers):
  - `groupsAndCaps`: 8 clip matches, 2 notes, 0 files → sections `[clipboard (5 hits), notes (2)]` (empty sections omitted).
  - `emptyQueryNoResults`.
  - `selectionCrossesSections`: `moveSelection(by: 6)` from 0 → `selectedHit` is the first note; clamps at the end and at 0.
  - `staleResultsDropped` *(Review Focus 4)*: files provider sleeps 300 ms for query "a" and returns `[/a]`, instant for "ab" → after typing "a" then "ab" and `settled()`, the file section shows only "ab"'s result.
- [ ] **Step 2: Run** `./test.sh GlobalSearchTests`. Expected: FAIL.
- [ ] **Step 3: Implement** model, view, ShelfController hooks, AppDelegate wiring.
- [ ] **Step 4: Run** full suite. Expected: PASS.
- [ ] **Step 5: Commit** `feat: global search across panels (⌘⇧F)`.

---

### Task 3: Floating stickies

**Files:** Create `Notes/StickyManager.swift`; Modify `Notes/NoteEditor.swift` (decouple from `NotesController`), `Notes/NoteStore.swift` (`onRename`, `onDelete` hooks), `Notes/NotesPanel.swift` (context menu "Float as Sticky"), `Shared/AppSettings.swift`, `App/AppDelegate.swift`; Tests: extend `NoteStoreTests`, `AppSettingsTests`.

**Interfaces — Produces:**
```swift
// NoteStore
var onRename: [(_ old: String, _ new: String) -> Void]
var onDelete: [(_ filename: String) -> Void]
// NoteEditor: init(store: NoteStore, filename: String, fontSize: CGFloat, selection: Int = 0,
//                  onTextView: @escaping (NoteTextView) -> Void = { _ in })
// AppSettings
var stickies: [String: String]       // filename → NSStringFromRect; JSON-encoded
@MainActor final class StickyManager {
  init(store: NoteStore, settings: AppSettings)
  func open(_ filename: String)       // focuses an existing sticky for that note
  func restore()                      // at launch; skips missing notes and drops them from settings
  var openFilenames: [String] { get }
}
```
Panel content: `NoteEditor(store:filename:fontSize:)` with the panel's title bound to the note title. `windowDidMove/Resize` → `settings.stickies[filename] = NSStringFromRect(frame)`; `windowWillClose` → remove entry and `store.finishEditing`. `onRename` re-keys the entry and the panel; `onDelete` closes the panel.

- [ ] **Step 1: Failing tests:** `renameNotifies` (finishEditing after a title change calls `onRename("Untitled.md", "Groceries.md")`), `deleteNotifies`, `twoEditorsUpdateSameNote` *(Review Focus 1)*: `update(f, "A\none")` then `update(f, "A\none two")` → text is the latter, saved once by `saveAll`; `stickiesPersist` in `AppSettingsTests`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** (NoteEditor refactor first, then manager, menu item, AppDelegate `stickies.restore()` after notes are set up).
- [ ] **Step 4: Run** full suite. Expected: PASS.
- [ ] **Step 5: Commit** `feat: floating sticky notes`.

---

### Task 4: Checklist

- [ ] **Step 1:** Add "Cross-panel" to `docs/manual-checklist.md`: Send to Note (recent + New Note; image clip; into the open note), ⌘⇧F search (all three sections, ↑/↓/⏎, click, Esc closes only the overlay), stickies (float, move/resize persist across relaunch, edit in shelf and sticky, rename follows, delete closes, stays on top across Spaces/full screen, closing keeps the note).
- [ ] **Step 2: Commit** `docs: cross-panel checklist`.
