# ShelfScroll Clipboard Implementation Plan (2 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Clipboard placeholder column with a working clipboard history + favorites panel: capture, sensitive handling, persistence, click-to-copy, keyboard paste into the previous app, search, Quick Look, and the Clipboard settings tab.

**Architecture:** Pure-ish value layer (`Clip`, `ClipReader`, `ClipWriter`, `ClipStore`) tested against private named pasteboards and temp directories; a polling `ClipboardMonitor`; a `Paster` that writes, hides the shelf and synthesizes ⌘V; a SwiftUI `ClipboardPanel` plugged into the Shell via `PanelDescriptor`.

**Tech Stack:** Swift 6, SwiftUI + AppKit, CryptoKit (hash), ImageIO (thumbnails), Quartz (`QLPreviewPanel`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-11-shelfscroll-design.md` (§5, §3 data locations, §8)

## Global Constraints

- Everything in the Shell plan's Global Constraints still applies (macOS 26, Swift 6, no SwiftData, perf budget, `./test.sh [Suite]`).
- History limit options 10 / 25 / 50; default **50**.
- Poll `changeCount` every 0.5 s, tolerance 0.3 s; 1.5 s while screens sleep or the session is locked.
- History: `~/Library/Application Support/ShelfScroll/history.json` + `images/`. Favorites: user folder, default `~/Documents/ShelfScroll Favorites`, `favorites.json` + `images/`. Sensitive clips: memory only, never written.
- JSON writes atomic, debounced 1 s, off the main thread.
- Own pasteboard marker type: `com.lakshhaybedi.ShelfScroll.own`.
- Header copy: titles "Clipboard History" / "Clipboard Favorites"; clear confirmation buttons "Cancel" / "Clear the Clipboard and History".
- Toast copy without Accessibility: "Copied — press ⌘V".
- Size caps: text clips > 5 MB and image clips > 20 MB are not recorded.

## Review Focus

1. **Huge clipboard content** (a 50 MB log, a 40 MB screenshot). Expect: not recorded; history stays small and the app inside the memory budget. → test in Task 1.
2. **Corrupt or partly missing store** (`history.json` truncated, an image file deleted by hand). Expect: app launches with whatever is valid; clips whose image is gone are dropped; no crash. → test in Task 3.
3. **Favorites folder missing** (cloud drive offline, folder deleted). Expect: next save recreates the folder; favorites in memory are not lost. → test in Task 3.
4. **Same content copied again from a different app.** Expect: one entry, moved to top, source app and date updated. → test in Task 3.
5. **Previous app quit while the shelf was open**, then ⏎ paste. Expect: clip is copied, toast shown, nothing crashes. → handled in Task 5 (`Paster`), checklist item in Task 7.

---

## File Structure

```
ShelfScroll/Clipboard/
  Clip.swift                 model + kind
  ClipReader.swift           NSPasteboard → Clip (or ignore)
  ClipWriter.swift           Clip → NSPasteboard
  ClipStore.swift            history/favorites, dedupe, limit, search, persistence
  ClipboardMonitor.swift     polling + sleep/lock slowdown
  Paster.swift               copy / paste into previous app / toast
  ClipboardPanel.swift       SwiftUI column (header, current clip, rows, keyboard)
  ClipRow.swift              one row
  ClipboardSettings.swift    settings tab
ShelfScroll/Shared/
  ThumbnailCache.swift       ImageIO thumbnails, NSCache, purge
  QuickLook.swift            QLPreviewPanel helper (Files reuses)
  Toast.swift                small HUD panel
ShelfScrollTests/
  ClipReaderTests.swift  ClipWriterTests.swift  ClipStoreTests.swift
```
Modify: `Shared/AppSettings.swift`, `Shell/ShelfController.swift` (previous app, purge on hide), `App/AppDelegate.swift`, `App/SettingsView.swift`, `docs/manual-checklist.md`.

---

### Task 1: Clip model + ClipReader

**Files:** Create `Clipboard/Clip.swift`, `Clipboard/ClipReader.swift`; Test `ShelfScrollTests/ClipReaderTests.swift`.

**Interfaces — Produces:**
```swift
enum ClipKind: String, Codable { case text, richText, url, image, files, color }
enum SensitiveMode: String, Codable, CaseIterable { case conceal, ignore }
struct ClipSource: Equatable, Codable { var bundleID: String?; var name: String? }
struct Clip: Identifiable, Equatable, Codable {
  var id: UUID; var kind: ClipKind; var date: Date
  var text: String?          // plain text, URL string, hex colour, or file names (newline-joined) for search
  var rtf: Data?             // .richText only
  var imageFile: String?     // filename inside the owning store's images dir
  var fileURLs: [URL]?       // .files only
  var source: ClipSource
  var contentHash: String    // SHA-256 hex of kind + primary payload; dedupe key
  var isSensitive: Bool = false   // never persisted (excluded from encoding is not required: store filters)
}
enum ClipReader {
  static let ownType = NSPasteboard.PasteboardType("com.lakshhaybedi.ShelfScroll.own")
  static let maxTextBytes = 5_000_000
  static let maxImageBytes = 20_000_000
  static func read(_ pb: NSPasteboard, source: ClipSource, imagesDir: URL,
                   sensitiveApps: [String: SensitiveMode], now: Date = .now) -> Clip?
}
```
Rules, in order: `nil` if the pasteboard has `ownType`, `org.nspasteboard.TransientType` or `org.nspasteboard.AutoGeneratedType`; `nil` if `sensitiveApps[source.bundleID] == .ignore`; sensitive = `org.nspasteboard.ConcealedType` present or mode `.conceal`. Kind priority: **file URLs** (`.fileURL`) → `.files`; **colour** (`.color`) → `.color` with `text` = `#RRGGBB`; **string** present → `.url` if the trimmed string parses as a URL with scheme http/https/file/mailto and has no whitespace, else `.richText` if `.rtf` data present, else `.text`; else **image** (`.png` or `.tiff`) → PNG written to `imagesDir/<id>.png` → `.image`. Sensitive images return `nil` (ponytail: password managers copy text; add in-memory image support if ever needed). Empty/whitespace-only strings → `nil`. Text over `maxTextBytes` or image data over `maxImageBytes` → `nil`.

- [ ] **Step 1: Write failing tests** — each uses `let pb = NSPasteboard(name: .init("test-\(UUID())"))`, `pb.clearContents()`, a temp `imagesDir`, and `source = ClipSource(bundleID: "com.apple.TextEdit", name: "TextEdit")`; release with `pb.releaseGlobally()` at the end:
  - `plainText`: `setString("hello", .string)` → kind `.text`, `text == "hello"`, `source == source`.
  - `richTextKeepsRTF`: string "hi" + `.rtf` data → `.richText`, `rtf != nil`, `text == "hi"`.
  - `urlString`: `"https://unclutterapp.com/panels/clipboard/"` → `.url`.
  - `textWithSpacesIsNotURL`: `"see https://x.com now"` → `.text`.
  - `fileURLs`: `writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL])` → `.files`, `fileURLs == [/tmp/a.txt]`, `text == "a.txt"`.
  - `pngImageSaved`: 4×4 PNG data on `.png` → `.image`, file exists at `imagesDir/<imageFile>`.
  - `textBeatsImage` (Word-style): string + tiff → `.text`.
  - `colour`: `writeObjects([NSColor.red])` → `.color`, `text == "#FF0000"`.
  - `ownMarkerIgnored`, `transientIgnored`, `autoGeneratedIgnored`: string + that type → `nil`.
  - `concealedIsSensitive`: string + `org.nspasteboard.ConcealedType` → `isSensitive == true`.
  - `appIgnoreList`: `sensitiveApps: ["com.apple.TextEdit": .ignore]` → `nil`.
  - `appConcealList`: `.conceal` → `isSensitive == true`.
  - `emptyStringIgnored`: `"   "` → `nil`.
  - `hugeTextIgnored` *(Review Focus 1)*: 5_000_001 × "a" → `nil`.
  - `sameContentSameHash`: reading "hello" twice gives equal `contentHash`; "hello" vs "hello!" differ.
- [ ] **Step 2: Run** `./test.sh ClipReaderTests`. Expected: compile failure (types missing).
- [ ] **Step 3: Implement** `Clip`, `ClipReader`. Hash = SHA-256 over `kind.rawValue + "\0" + payload` where payload is text / file paths joined by `\n` / PNG bytes.
- [ ] **Step 4: Run.** Expected: all pass.
- [ ] **Step 5: Commit** `feat(clipboard): read clips from the pasteboard`.

---

### Task 2: ClipWriter

**Files:** Create `Clipboard/ClipWriter.swift`; Test `ClipWriterTests.swift`.

**Interfaces — Consumes:** `Clip`, `ClipReader.ownType`. **Produces:** `enum ClipWriter { static func write(_ clip: Clip, to pb: NSPasteboard, imagesDir: URL, plainText: Bool = false) }` — clears, writes the clip's representations plus `ownType` (empty data). `.richText` writes `.rtf` + `.string` (only `.string` when `plainText`); `.url` writes `.string` + `.URL`; `.files` writes file URLs; `.image` writes PNG data (`.png`) + TIFF; `.color` writes `NSColor` + hex `.string`.

- [ ] **Step 1: Failing tests:** `roundTripText` (write → `pb.string(forType: .string) == text`, `pb.types` contains `ownType`); `plainTextDropsRTF` (rich clip with `plainText: true` → `pb.data(forType: .rtf) == nil`); `roundTripImage` (image clip from Task 1 helper → `pb.data(forType: .png) != nil`); `roundTripFiles` (`pb.readObjects(forClasses: [NSURL.self])` equals the URLs); `ownWritesAreIgnoredByReader` (write then `ClipReader.read` → `nil`).
- [ ] **Step 2: Run** `./test.sh ClipWriterTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(clipboard): write clips back to the pasteboard`.

---

### Task 3: ClipStore

**Files:** Create `Clipboard/ClipStore.swift`; Test `ClipStoreTests.swift`.

**Interfaces — Consumes:** `Clip`. **Produces:**
```swift
@MainActor @Observable final class ClipStore {
  init(historyDir: URL, favoritesDir: URL, limit: Int)
  var limit: Int                       // trimming applied on set
  private(set) var history: [Clip]     // newest first
  private(set) var favorites: [Clip]   // newest first
  var historyImagesDir: URL { get }    // historyDir/images
  var favoritesImagesDir: URL { get }  // favoritesDir/images
  func ingest(_ clip: Clip)
  func delete(_ id: Clip.ID)           // from history (and its image file)
  func clearHistory()                  // favorites untouched
  func isFavorite(_ clip: Clip) -> Bool        // by contentHash
  func toggleFavorite(_ clip: Clip)    // adds a copy (image copied into favoritesImagesDir) or removes by hash
  func updateText(_ id: Clip.ID, to text: String)  // in-place edit; kind becomes .text, hash recomputed
  func imageURL(for clip: Clip) -> URL?             // resolves against the dir that owns it
  func saveNow() async                 // flush pending debounced writes (tests, quit)
  static func filter(_ clips: [Clip], query: String) -> [Clip]
}
```
Rules: `ingest` with an existing `contentHash` moves that entry to the top with the new `date` and `source`; sensitive clips are kept in `history` but never written; over `limit` the oldest are removed (and their image files deleted). Favorites are a separate list and never evicted. `filter`: case-insensitive `localizedStandardContains` on `text`, file names, and `source.name`; empty query returns input. Load on `init`: decode each file; on decode failure start empty (and rename the bad file to `history.json.corrupt`); drop image clips whose file is missing. Save: debounce 1 s, encode non-sensitive clips, `createDirectory(withIntermediateDirectories: true)` then atomic write, on a detached task.

- [ ] **Step 1: Failing tests** (temp dirs, `limit: 3`; helper `clip("a")` makes a `.text` clip with hash of its text):
  - `newestFirst`: ingest a, b → `history.map(\.text) == ["b","a"]`.
  - `dedupeMovesToTopAndUpdatesSource` *(Review Focus 4)*: ingest a (TextEdit), b, a (Safari) → `["a","b"]`, `history[0].source.name == "Safari"`.
  - `limitEvictsOldest`: a,b,c,d → `["d","c","b"]`.
  - `loweringLimitTrims`: 3 clips, `limit = 1` → count 1.
  - `favoriteSurvivesEvictionAndClear`: favourite a; ingest b,c,d; `clearHistory()` → `history.isEmpty`, `favorites.map(\.text) == ["a"]`, `isFavorite(a)`.
  - `toggleFavoriteRemoves`: toggle twice → `favorites.isEmpty`.
  - `persistsAcrossInstances`: ingest a, favourite b, `await saveNow()`, new store same dirs → same history and favorites.
  - `sensitiveNotPersisted`: ingest sensitive s and a, save, reload → `["a"]`.
  - `corruptHistoryStartsEmpty` *(Review Focus 2)*: write `"{not json"` to `history.json` → store loads with empty history; `history.json.corrupt` exists.
  - `missingImageDropped` *(Review Focus 2)*: persisted image clip whose PNG is deleted before reload → not in history.
  - `favoritesFolderRecreated` *(Review Focus 3)*: favourite a, save, delete favoritesDir, favourite b, save → `favorites.json` exists with 2 entries.
  - `deleteRemovesImage`: image clip ingested then deleted → its PNG no longer exists.
  - `updateTextChangesHash`: edit a → "a2": `text == "a2"`, hash differs from before.
  - `filterMatchesTextFileNamesAndSource`: query "safari" matches by source name; "a.txt" matches a files clip; "" returns all.
- [ ] **Step 2: Run** `./test.sh ClipStoreTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(clipboard): history and favorites store`.

---

### Task 4: Settings + monitor

**Files:** Modify `Shared/AppSettings.swift`, `App/SettingsView.swift`; Create `Clipboard/ClipboardMonitor.swift`, `Clipboard/ClipboardSettings.swift`; Test: extend `AppSettingsTests`.

**Interfaces — Produces:**
```swift
enum ClipboardView: String, CaseIterable { case lastView, history, favorites }
// AppSettings additions (persisted like the others):
var historyLimit: Int                         // default 50
var clipboardOpensWith: ClipboardView         // default .lastView
var lastClipboardView: ClipboardView          // .history or .favorites; default .history
var sensitiveApps: [String: SensitiveMode]    // bundleID → mode; JSON-encoded; default [:]
var favoritesFolder: URL                      // default ~/Documents/ShelfScroll Favorites
@MainActor final class ClipboardMonitor {
  init(settings: AppSettings, store: ClipStore)
  func start(); func stop()
}
```
Monitor: `Timer` 0.5 s / tolerance 0.3 s on the main run loop; on `NSWorkspace.screensDidSleepNotification` or distributed `com.apple.screenIsLocked` reschedule at 1.5 s, back on `screensDidWake` / `com.apple.screenIsUnlocked`. Each tick: return if `settings.clipboardPaused` or `changeCount` unchanged; record the new count; source = `NSWorkspace.shared.frontmostApplication` (bundle ID + localized name); `ClipReader.read(…, imagesDir: store.historyImagesDir, sensitiveApps: settings.sensitiveApps)`; `store.ingest`. Start by recording the current `changeCount` (don't ingest what was already there). `store.limit` follows `settings.historyLimit` (observation).

Settings tab "Clipboard" (after General): heading **Sensitive Data** + caption "Data from these applications will appear concealed and not saved to disk:"; a list of apps (icon + name from `NSWorkspace.urlForApplication(withBundleIdentifier:)`) with a per-row Picker Conceal / Ignore; **+** opens `NSOpenPanel` in `/Applications` limited to `.application`, **−** removes the selection. Picker "Clipboard history keeps:" 10 items / 25 items / 50 items. Picker "Clipboard opens with:" Last view / History / Favorites. Row "Store favorites in" + path + "Choose…" (`NSOpenPanel` directories, `canCreateDirectories`).

- [ ] **Step 1: Failing test** `clipboardDefaults` in `AppSettingsTests`: `historyLimit == 50`, `clipboardOpensWith == .lastView`, `lastClipboardView == .history`, `sensitiveApps.isEmpty`, `favoritesFolder.lastPathComponent == "ShelfScroll Favorites"`; and `sensitiveAppsPersist`: set `["com.1password.1password": .conceal]`, reload → equal.
- [ ] **Step 2: Run** `./test.sh AppSettingsTests`. Expected: FAIL.
- [ ] **Step 3: Implement** settings, monitor, settings tab (insert as the 2nd tab, icon `clipboard`).
- [ ] **Step 4: Run** full `./test.sh`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(clipboard): monitor and settings`.

---

### Task 5: Paster, toast, previous app

**Files:** Create `Clipboard/Paster.swift`, `Shared/Toast.swift`; Modify `Shell/ShelfController.swift`.

**Interfaces — Consumes:** `ClipWriter`, `ClipStore.historyImagesDir/favoritesImagesDir`, `Permissions.isAccessibilityTrusted`. **Produces:**
```swift
// ShelfController additions
private(set) var previousApp: NSRunningApplication?   // frontmost app captured in show()
var onHide: [() -> Void]                              // called after hide starts (ThumbnailCache.purge etc.)
@MainActor final class Paster {
  init(store: ClipStore, shelf: ShelfController)
  func copy(_ clip: Clip, plainText: Bool = false)   // write only; shelf stays open
  func paste(_ clip: Clip, plainText: Bool = false)  // write, hide, reactivate previous app, ⌘V
}
enum Toast { @MainActor static func show(_ message: String) }   // HUD, top-centre of main screen, 1.2 s
```
`paste`: `copy`; `shelf.hide()`; if `Permissions.isAccessibilityTrusted` and `previousApp` is not terminated → `previousApp.activate()` then after 80 ms post `CGEvent` keyDown/keyUp for virtual key 9 with `.maskCommand` to `.cghidEventTap`; otherwise `Toast.show("Copied — press ⌘V")`. `ShelfController.show` sets `previousApp = NSWorkspace.shared.frontmostApplication` unless that is ShelfScroll itself.

- [ ] **Step 1: Implement** (adapter code; writer logic is covered by Task 2).
- [ ] **Step 2: Run** `./test.sh`. Expected: PASS.
- [ ] **Step 3: Commit** `feat(clipboard): paste into previous app`.

---

### Task 6: Clipboard panel UI

**Files:** Create `Clipboard/ClipboardPanel.swift`, `Clipboard/ClipRow.swift`, `Shared/ThumbnailCache.swift`, `Shared/QuickLook.swift`; Modify `App/AppDelegate.swift` (build store, monitor, paster; set `shelf.descriptors` with the real clipboard panel, placeholders for Files/Notes); Test: `ThumbnailCacheTests.swift`.

**Interfaces — Produces:**
```swift
@MainActor final class ThumbnailCache {
  static let shared: ThumbnailCache
  func thumbnail(for url: URL, maxPixelSize: Int) -> CGImage?   // ImageIO CGImageSourceCreateThumbnailAtIndex, cached by url+size
  func purge()
}
@MainActor enum QuickLook { static func show(_ urls: [URL]) }   // QLPreviewPanel with a retained data source
struct ClipboardPanel: View { init(store: ClipStore, settings: AppSettings, paster: Paster) }
```
Layout (matches the reference screenshots):
- `PanelHeader(title: "Clipboard History" | "Clipboard Favorites")` buttons right→left order on screen: 🔍 (`magnifyingglass`, toggles a search field under the header), ⏸ (`pause.fill`, orange when paused), ⊘ (`nosign`, popover with "Cancel" / "Clear the Clipboard and History": clears the pasteboard and `clearHistory()`), ≡ (`list.bullet`, History), ★ (`star.fill`, Favorites). The active view's button gets a filled rounded background.
- Initial view: `clipboardOpensWith` (`.lastView` → `lastClipboardView`); switching updates `lastClipboardView`.
- Paste-permission banner at top when `NSPasteboard.general.accessBehavior == .alwaysDeny`: "ShelfScroll can't read the clipboard. Allow it in System Settings › Privacy & Security › Paste from Other Apps." with an "Open Settings" button (`x-apple.systempreferences:com.apple.preference.security`).
- History view: first row = current clipboard (= `history.first` if its hash matches the live pasteboard), expanded, text editable in a `TextField(axis: .vertical)`; commit on Esc / focus loss via `store.updateText` + `paster.copy`. Then the remaining rows.
- `ClipRow`: ~4-line preview, min height 56, `.padding(12)`, separator line. Left gutter 28 pt: source app icon (`NSWorkspace.icon(forFile:)` of the app URL) — on hover/selection replaced by ☆/★ button (`toggleFavorite`). Right: × on hover/selection (`delete`). Body by kind: text (URLs underlined via `AttributedString`), image thumbnail (`ThumbnailCache`, max 160 px tall), file icon + name, colour swatch + hex. Sensitive: `•••••• · <source name>`; holding ⌥ while hovering reveals the text. **Click body → `paster.copy`** (row flashes selected).
- Favorites view rows: filled ★ in a 28 pt circle on the left (click = unfavourite), no ×.
- Keyboard (on the list; `focusable()` + `onKeyPress`): ↑/↓ select · ⏎ `paste` · ⌥⏎ `paste(plainText: true)` · ⌘1–9 paste n-th visible clip · ⌘C `copy` · ⌘S toggle favourite · ⌫ delete · Space `QuickLook.show` for image/files clips.
- Context menu: Paste · Paste as Plain Text · Copy · Favorite/Unfavorite · Delete.
- Empty states: History "Copy something and it shows up here." Favorites "Star a clip to keep it here forever."
- `AppDelegate` registers `ThumbnailCache.shared.purge` in `shelf.onHide`.

- [ ] **Step 1: Failing test** `ThumbnailCacheTests.thumbnailIsDownsampled`: write a 2000×1000 PNG to a temp file → `thumbnail(for:maxPixelSize: 200)` has `max(width,height) == 200`; `purge()` then call again still returns an image (re-generated).
- [ ] **Step 2: Run** `./test.sh ThumbnailCacheTests`. Expected: FAIL.
- [ ] **Step 3: Implement** cache, Quick Look helper, panel, rows, AppDelegate wiring.
- [ ] **Step 4: Run** full `./test.sh`. Expected: PASS.
- [ ] **Step 5: Build Release and measure** (as in Shell Task 10) with 50 text clips + 5 image clips in history and the shelf open: memory ≤ 150 MB; closed + idle: ≤ 80 MB, CPU ~0.0 %, wake-ups ≤ 2.
- [ ] **Step 6: Commit** `feat(clipboard): clipboard panel UI`.

---

### Task 7: Checklist

**Files:** Modify `docs/manual-checklist.md` — add a "Clipboard" section: copy text/URL/image/file/colour from various apps → appears with the right icon and preview; re-copying moves to top; click copies; ⏎ pastes into the previous app (with Accessibility) and shows the toast without it; ⌥⏎ pastes plain text; ⌘1–9; star/unstar; ⊘ confirmation clears; ⏸ stops capture; 1Password copy is concealed and gone after quit; app on Ignore list isn't recorded; search; Space Quick Look; current-clip edit + Esc updates the clipboard; previous app quit then ⏎ → toast, no crash *(Review Focus 5)*; settings tab controls apply live; history survives relaunch; favourites folder change.

- [ ] **Step 1:** Write the section. Record Task 6 Step 5 numbers in the performance table.
- [ ] **Step 2: Commit** `docs: clipboard checklist`.
