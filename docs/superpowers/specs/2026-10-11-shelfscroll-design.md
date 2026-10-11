# ShelfScroll — Design Spec

Date: 2026-10-11 · Author: Lakshhay Bedi · Status: draft for review

## 1. Goal

A native macOS app that replicates Unclutter (clipboard history, file drawer, quick notes in a strip that slides down from the top of the screen) and improves on it — most of all a real markdown notes editor and much lower resource use. Daily-driver quality, open source on GitHub, distributed as a signed + notarized `.dmg`.

### Success criteria
- Full feature parity with Unclutter's three panels and its 7 settings tabs (as captured in the reference screenshots).
- All extras listed in §9 shipped.
- Meets the performance budget in §8 on Apple Silicon.
- `git tag vX.Y.Z && git push --tags` produces a notarized `.dmg` on GitHub Releases and a Sparkle update.

### Non-goals (v1)
- Mac App Store / sandbox. iOS. Unlimited clipboard history, history filters, text transforms, auto-expiring sensitive clips (explicitly deferred). Tables in notes.

## 2. Platform & constraints

- macOS 26 (Tahoe)+, Swift 6, SwiftUI inside an AppKit shell. Universal binary (arm64 + x86_64).
- Not sandboxed; hardened runtime on. Agent app (`LSUIElement`): no Dock icon.
- Bundle ID `com.lakshhaybedi.ShelfScroll`. License MIT.
- Dependencies (SPM): **Sparkle 2** (updates), **KeyboardShortcuts** (global hotkey + recorder). Nothing else.
- Permissions: **Accessibility** (only for auto-paste; app degrades to copy-only without it). One-time TCC prompts for **Documents** (default storage) and **Desktop** (screenshot catcher, if enabled). Possible macOS 26 clipboard-read privacy prompt — verify current enforcement before the Clipboard plan; onboarding must guide the user through it if present.

## 3. Architecture

One app target + one unit-test target. Folders, not packages:

```
ShelfScroll/
  App/        AppDelegate, status item, Settings window, onboarding, Sparkle
  Shell/      ShelfPanel (NSPanel), EdgeTrigger, PanelLayout (NSSplitView), GlobalSearch
  Clipboard/  ClipboardMonitor, ClipStore, Clip, views
  Files/      DrawerModel, drop handling, Quick Look, Cleanup, ScreenshotCatcher, views
  Notes/      NoteStore, MarkdownStyler, NoteTextView, StickyWindow, views
  Shared/     StorageLocation, Permissions, FolderWatcher (DispatchSource), ThumbnailCache
Tests/
scripts/perf.sh
.github/workflows/{build,release}.yml
```

- Each panel exposes one `@Observable` store and a `PanelDescriptor { id, title, view, searchProvider? }`. The Shell only knows descriptors. Panels never import each other.
- Only cross-panel link: Clipboard → Notes "Send to Note" via a `NoteAppending` protocol.

### Data locations
| Data | Location | Synced? |
|---|---|---|
| Drawer files | user-chosen folder (default `~/Documents/ShelfScroll Files`) | yes, if folder is in a cloud drive |
| Notes | user-chosen folder (default `~/Documents/ShelfScroll Notes`): `*.md`, `attachments/`, `.pins.json` | yes |
| Clipboard favorites | user-chosen folder (default `~/Documents/ShelfScroll Favorites`): `favorites.json` + `images/` | yes |
| Clipboard history | `~/Library/Application Support/ShelfScroll/history.json` + `images/` | no |
| Sensitive clips | memory only | never |
| Settings | `UserDefaults` | no |

All writes atomic; JSON writes debounced and off the main thread.

## 4. Shell

### Panel window
- Single borderless, non-activating `NSPanel`: `canJoinAllSpaces`, `fullScreenAuxiliary`, can become key (for typing) without activating the app, so the previously frontmost app remains the paste target.
- Full screen width, directly under the menu bar, on the screen containing the cursor (hotkey: same rule).
- Height: user-resizable by dragging the bottom edge. Min ≈ 200pt, max ≈ 85% of the screen's visible height. Persisted per display.
- Columns: `NSSplitView` (autosaved), horizontally resizable, widths persisted per display. Order and visibility from the Panels settings tab (drag to reorder, checkbox to enable).
- Slide-down animation; fade under Reduce Motion.

### Opening (`EdgeTrigger`)
At the top edge of any screen (cursor within 2pt), any enabled trigger opens the panel:
- **Scroll down** (default on): accumulated delta crosses a threshold; "Invert scrolling direction" setting flips it.
- **Hold** a modifier (⌘ ⌥ ⌃ ⇧, selectable).
- **Wait** a delay (0.25 / 0.5 / 1 / 2 s).
- **Drag a file** to the top edge → opens with Files focused.
- **Global hotkey** (recorder in General); pressing again closes.

Monitors are installed only for enabled triggers: `scrollWheel` always; `mouseMoved` only when Hold or Wait is enabled; `leftMouseDragged` for drag-open; `flagsChanged` only with Hold. Observe-only global `NSEvent` monitors (no event tap, no Accessibility needed). Trigger decision logic is a pure struct (inputs: cursor pos, screen frames, scroll delta, modifiers, elapsed time → open/no-op), unit-tested.

### Closing
Click outside, Esc, scroll up over the bottom edge, or the hotkey.

### Global search (⌘K)
Search bar across the top of the strip; queries every panel's `searchProvider`; results grouped by panel. ⏎ pastes a clip / opens a file / opens a note.

### Menu bar item (hideable)
Click toggles panel. Right-click: Pause Clipboard · Settings… · Check for Updates… · Quit.

### Settings window (7 tabs)
- **General:** Launch at login (`SMAppService`); open triggers (scroll / hold [modifier] / wait [delay]) with preview illustration; "or just press" hotkey recorder; Show menu bar icon.
- **Files:** Store files in [folder picker].
- **Notes:** Write notes to [folder picker]; editor font size.
- **Clipboard:** Sensitive Data app list (+/−, per-app Conceal or Ignore); History keeps 10 / 25 / 50; Opens with Last view / History / Favorites; Favorites folder.
- **Panels:** enable/disable + reorder Clipboard, Files, Notes.
- **Appearance:** Theme Auto / Light / Dark; Material Liquid Glass / Solid.
- **Advanced:** Do not open window on launch; Invert scrolling direction.

### Onboarding (first run)
Choose Files + Notes folders → demo of the gesture → explain & request Accessibility (skippable) → explain upcoming folder/clipboard prompts.

## 5. Clipboard

### Capture
- Poll `NSPasteboard.general.changeCount` every 0.5 s with 0.3 s timer tolerance; 1.5 s while screen locked/asleep.
- Source app = frontmost app at change time (icon shown).
- Types: plain text, rich text (RTF retained), URL, image (PNG on disk + thumbnail), file URLs, color.
- Dedupe: re-copying existing content moves it to top.
- Own writes tagged with a private pasteboard type and ignored by the monitor.
- Limit 10 / 25 / 50; evict oldest non-favorite.
- Pause stops capture.

### Sensitive data
- Auto-detect `org.nspasteboard.ConcealedType` / `TransientType`.
- User app list with per-app mode: **Conceal** (memory-only, shown as `•••••• · AppName`, reveal while holding ⌥ on hover, gone on quit) or **Ignore** (never recorded).

### Column UI
- Title "Clipboard History" / "Clipboard Favorites". Header buttons: 🔍 search · ⏸ pause (orange when paused) · ⊘ clear (confirmation popover "Cancel | Clear the Clipboard and History") · ≡ History · ★ Favorites (segmented).
- Top row = current clipboard, expanded; text editable in place, Esc / click-away commits to the clipboard.
- History row (~120pt, up to 4 lines): source app icon left, preview (URLs underlined; image thumb; file icon + name; color swatch). On hover/selection the icon becomes ☆ and × appears right. **Clicking the body copies the clip.**
- Favorites row: filled ★ in a circle left; click un-favorites.
- Search filters text, URLs, file names, source app name.

### Keyboard
↑↓ select · ⏎ paste into previous app (close panel, reactivate app, synthesize ⌘V) · ⌥⏎ paste as plain text · ⌘1–9 quick paste · ⌘C copy only · ⌘S star · ⌫ delete · Space Quick Look. Without Accessibility, paste actions copy and show "Copied — press ⌘V".

### Context menu
Paste · Paste as Plain Text · Copy · Favorite · Send to Note ▸ (recent notes / New Note) · Delete.

## 6. Files

- Header: ⚙︎ menu, 🔍. ⚙︎ menu: New Folder · Show in Finder · Arrange By Name / Kind / Date Added / Date Modified · Keep Folders on Top · View As Icons ⌘1 / List ⌘2 · Item Size slider (4 stops) · Auto-cleanup ▸ Off / 7 / 30 / 90 days · Catch Screenshots.
- Icons view: lazy grid, `QLThumbnailGenerator` thumbnails at item size, `NSCache` with cost limit. List view: name / date / size.
- Live updates via `DispatchSource` watch of the displayed folder.
- In-panel folder navigation with ‹ back + breadcrumb; ⌘↑ up; ⌥-double-click opens in Finder.
- Drop in: Move (default) / Copy (⌥) / Alias (⌘⌥), with cursor badge. Browser file promises written into the folder; dropped URLs downloaded via `URLSession` with progress ring. Name clashes get " 2" suffix.
- Drag out to any app (multi-select supported).
- Item actions: double-click / ⌘O open · Space Quick Look · ⏎ rename · ⌘⌫ Trash · ⌘/⇧-click multi-select · arrow navigation. Context menu: Open · Open With ▸ · Quick Look · Show in Finder · Rename · Copy · Share ▸ · Move to Trash.
- Search: name filter, recursive, shows subfolder path.
- **Auto-cleanup:** top-level items not added/modified for N days → Trash (never hard delete). Scheduled via `NSBackgroundActivityScheduler` (~daily). Notifies count.
- **Screenshot catcher:** read `com.apple.screencapture` location (default Desktop), watch it, move new files flagged as screen captures into `Screenshots/` in the drawer. Never changes the system setting.

## 7. Notes

### Storage & sync
- One `.md` per note; first line = title; filename from title at creation, renamed when the note is left if the title changed.
- `attachments/` for images; `.pins.json` for pinned notes.
- Atomic save ~1 s after typing stops and on panel close.
- Folder watched; untouched notes reload on external change. If the open note has unsaved local edits when an external change lands, keep local in the editor and write the external version as `Title (conflict YYYY-MM-DD).md`. Never silently overwrite.

### Column UI
- Header: + new · ≡ list · 🔍 search · Aa format menu.
- Toggle single-note ↔ list: ≡ button, pinch, or ⌃⇧ while hovering.
- Opening the panel restores last note + cursor; typing works immediately.
- List: 📌 pinned first, then by modified date. Row: title + 2-line plain-text preview + date; × on hover deletes (to Trash). Click / ⏎ / Space opens.
- Context menu: Pin · Float as Sticky · Show in Finder · Duplicate · Move to Trash.
- Full-text search, all notes in memory, filters as you type.

### Editor — markdown with live styling
`NSTextView` (TextKit 2). Backing text is the exact markdown. A line-based incremental styler (own code; tracks fenced-code state across lines) restyles only edited paragraphs. Syntax markers are dimmed + shrunk on all lines except the caret's line.

| Element | Markdown | Rendering |
|---|---|---|
| Bold / italic / strike | `**b**` `*i*` `~~s~~` | styled |
| Underline | `<u>u</u>` | underline |
| Highlight | `==h==` | marker highlight |
| Inline code | `` `c` `` | mono + background |
| Conceal | `\|\|secret\|\|` | `••••`, click to reveal |
| Headings | `#` `##` `###` | sized bold |
| Bullets | `-` `*` | • ◦ ▪ by depth |
| Numbered | `1.` | auto-renumbered |
| Checklist | `- [ ]` `- [x]` | clickable ☐ / ☑, checked dimmed + struck |
| Quote | `>` | left bar |
| Code block | ```` ``` ```` | mono block |
| Divider | `---` | rule |
| Link | `[t](url)`, bare URLs | underlined, ⌘-click opens |
| Image | `![](attachments/x.png)` | inline, scaled to width |

List behaviour: ⏎ continues (next number / new unchecked box); ⏎ on empty item ends the list; Tab / ⇧Tab indent/outdent with correct nested numbering; delete/move/paste renumbers; ⌘⌥↑/↓ moves line/item. Markdown shortcuts style instantly as typed.

Formatting: floating bar on selection (B I U S · highlight · code · link · conceal · H1–H3 · bullets · numbers · checklist). Shortcuts: ⌘B ⌘I ⌘U · ⌘⇧X strike · ⌘⇧H highlight · ⌘E code · ⌘K link · ⌘1–3 headings · ⌘⇧8 bullets · ⌘⇧7 numbers · ⌘⇧L checklist · ⌘⏎ toggle checkbox. Undo/redo, spell check, ⌘F find & replace from `NSTextView`.

Paste/drop images → saved to `attachments/`, inserted as image markdown.

### Floating stickies
Any note can float as an always-on-top resizable `NSPanel` using the same editor. Multiple allowed; frames persisted; closing never deletes.

### Send to Note
Appends a clip as a new paragraph to the chosen note (images copied into `attachments/`).

## 8. Performance budget (acceptance criteria)

Baseline measured from Unclutter (running under Rosetta): 309 MB memory, 0.3 % CPU, 3 idle wake-ups, 7 threads, 1.24 12-hr power, 519 MB disk read.

| Metric | Target |
|---|---|
| Memory, panel closed, idle | ≤ 80 MB |
| Memory, panel open, 50 clips + 100 drawer items | ≤ 150 MB |
| Idle CPU | ~0.0 % |
| Idle wake-ups/s | ≤ 2 |
| Threads | ≤ 7 |
| 12-hr power | < 1.0 |
| Disk read, 12 hr | < 50 MB |

Rules that achieve it: no SwiftData/Core Data; event monitors only for enabled triggers; coalesced pasteboard timer; ImageIO thumbnails at display size, full images only for Quick Look; caches purged on panel close; no rendering/animation/timers while hidden; incremental note styling.

Measured by `scripts/perf.sh` (Release build, 60 s settle, `footprint` + `powermetrics`/`top` wake-ups) before each release; results go in release notes.

## 9. Extras beyond Unclutter (included)

A clipboard search · B rich clip types · C keyboard flow + auto-paste · D paste as plain text · H Quick Look · I auto-cleanup · J screenshot catcher · K markdown checklists (expanded into full editor, §7) · L floating stickies · M send clip to note · N global search · O Liquid Glass + themes. Plus: in-panel folder navigation, conceal syntax, conflict-safe sync, pause clipboard.

## 10. Release & CI

- `build.yml`: push/PR on `macos-26` runner → `xcodebuild test`, Universal, unsigned.
- `release.yml` on `v*` tag: import Developer ID cert into temp keychain → Release build, hardened runtime, sign → `hdiutil` dmg (app + Applications symlink + background) → `notarytool submit --wait` (App Store Connect API key) → staple → Sparkle `sign_update` (EdDSA) → update `appcast.xml` on `gh-pages` → GitHub Release with dmg + `CHANGELOG.md` notes.
- Secrets: `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `SPARKLE_ED_PRIVATE_KEY`. `RELEASING.md` documents creating each.
- Without a paid account: build workflow + local Xcode runs work; release workflow stops at signing.
- Sparkle checks daily + "Check for Updates…".

## 11. Testing

Unit tests (XCTest, temp dirs / private named pasteboards — never the real clipboard or user folders):
- EdgeTrigger decision struct.
- Clip reading per type, sensitive classification, dedupe/limit/favorite-retention.
- Files: sort orders, cleanup selection by date, screenshot detection, modifier → Move/Copy/Alias, name-clash suffixing.
- Notes: styler (line → attribute ranges), list continue/exit/indent/renumber, byte-exact open→save round-trip, conflict file creation, title-rename.

Manual checklist: Spaces, full-screen apps, multiple displays, Stage Manager, Reduce Motion, light/dark, permissions denied paths.

## 12. Build order

Each is its own implementation plan:
1. **Shell** — panel, triggers, layout, settings skeleton, menu bar, onboarding, CI build workflow.
2. **Clipboard**.
3. **Files**.
4. **Notes** (largest).
5. **Global search, stickies, Send to Note** (cross-panel).
6. **Release pipeline** — signing, notarization, dmg, Sparkle, perf script.

## 13. Open risks

- macOS 26 clipboard privacy prompt behaviour — verify before plan 2.
- Non-activating panel + text input edge cases with some input methods — verify early in plan 1.
- TextKit 2 custom rendering (checkbox glyphs, hidden markers) is the hardest piece — spike at the start of plan 4.
