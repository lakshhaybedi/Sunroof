# Shell — manual checklist

Run from Xcode or `build/Build/Products/Release/ShelfScroll.app`. To redo first-run: `defaults delete com.lakshhaybedi.ShelfScroll`.

## Opening & closing
- [ ] Scroll down at the very top of the screen opens the strip (trackpad)
- [ ] Same with a mouse wheel (if wrong direction: Advanced › Invert scrolling)
- [ ] Scrolling down anywhere else does nothing
- [ ] Momentum after opening doesn't flicker or close it
- [ ] Scroll up near the strip's bottom edge closes it
- [ ] Esc closes; clicking outside closes
- [ ] Hold ⌘ enabled: parking at the top + ⌘ opens; ⌘-dragging a menu bar icon does not
- [ ] Wait 0.5 s enabled: parking at the top opens after the pause; moving away cancels
- [ ] Dragging a Finder file to the top opens it; dragging a window to the top does not
- [ ] Recorded hotkey toggles from any app
- [ ] Triggers still work while the Settings or onboarding window is frontmost
- [ ] Menu bar icon: left click toggles, right click shows Pause / Settings… / Quit

## Window
- [ ] Full width directly under the menu bar; dragging the bottom edge resizes; stops at ~85 % of the screen
- [ ] Height and column widths are remembered after relaunch
- [ ] Column dividers drag; each column stays ≥ 220 pt
- [ ] Works on Space 2 after opening on Space 1
- [ ] Opens over a full-screen app (e.g. Safari full screen)
- [ ] Two displays: opens on the display under the cursor; heights/widths remembered per display
- [ ] Stacked displays: no trigger at the shared edge
- [ ] Stage Manager on: still opens and closes
- [ ] Reduce Motion on: fades instead of sliding
- [ ] While open, the previous app stays frontmost in the menu bar

## Settings
- [ ] Every control applies live: triggers, panel order/enable, theme, material, menu bar icon
- [ ] The last enabled panel can't be disabled
- [ ] Launch at login shows in System Settings › General › Login Items (needs a signed build; ad-hoc may show an error)

## Onboarding
- [ ] First launch shows onboarding; the gesture page says "Nice!" after opening the strip
- [ ] Accessibility button opens the system prompt; ✓ appears after granting and returning
- [ ] Done → relaunch is quiet; unticking "Do not open…" → relaunch shows the strip

## Clipboard
- [ ] Copy text, a URL, an image, a Finder file and a colour (Digital Color Meter) — each appears with the source app icon and the right preview
- [ ] Re-copying something already in history moves it to the top
- [ ] Clicking a row copies it (and it becomes the top row)
- [ ] ⏎ pastes into the app you were in (Accessibility granted); without it, "Copied — press ⌘V" appears
- [ ] ⌥⏎ pastes as plain text (rich text loses formatting)
- [ ] ⌘1–9 paste the n-th clip; ⌘C copies; ⌘S stars; ⌫ deletes; ↑/↓ move the selection
- [ ] Space opens Quick Look on image and file clips
- [ ] Hovering a row swaps the app icon for ☆ and shows ×; ★ view shows filled stars, clicking one unfavourites
- [ ] ⊘ shows "Cancel | Clear the Clipboard and History"; clearing keeps favourites
- [ ] ⏸ turns orange and nothing new is recorded; menu bar "Pause Clipboard" stays in sync
- [ ] A 1Password copy shows as •••••• · 1Password; holding ⌥ while hovering reveals it; it's gone after quitting
- [ ] An app set to Ignore in Settings › Clipboard is never recorded
- [ ] 🔍 search filters by text, file name and app name
- [ ] Editing the top text clip then pressing Esc updates the clipboard (paste elsewhere to check)
- [ ] Quit the app you were in while the shelf is open, then ⏎ → toast, no crash
- [ ] History limit 10 / 25 / 50 applies immediately; "opens with" applies on next open
- [ ] History and favourites survive a relaunch; changing the favourites folder carries favourites over

## Files
- [ ] Drag from Finder into the column: moves; ⌥ copies (+ badge); ⌘⌥ makes an alias (+ badge)
- [ ] Drag an image and a link from Safari: the image is saved; the link downloads (spinner cell, then the file)
- [ ] Drag a file out to Finder / Mail
- [ ] Dragging a file to the very top of the screen opens the shelf (Files)
- [ ] ⚙︎ Arrange By Name / Kind / Date Added / Date Modified; Keep Folders on Top; Icons ⌘1 / List ⌘2; Item Size; all persist
- [ ] Double-click a folder opens it in the panel; breadcrumbs and ‹ / ⌘↑ go back; ⌥-double-click opens in Finder
- [ ] ⏎ renames (clash → " 2"); ⌘⌫ moves to Trash; Space Quick Look; ⌘O opens
- [ ] Right-click: Open With, Show in Finder, Copy, Share, Move to Trash
- [ ] 🔍 search finds files in subfolders
- [ ] Finder changes to the folder appear live
- [ ] Auto-cleanup "After 7 Days" with an old file → toast "Moved 1 old item to the Trash" (within ~10 s of launch)
- [ ] Catch Screenshots on → ⇧⌘4 screenshot lands in Files/Screenshots (Desktop prompt appears once)
- [ ] Change the Files folder in Settings; point it at a deleted folder → "Folder not found" + Choose…

## Notes
- [ ] Opening the shelf puts the caret in the last note; typing works immediately (unless opened by dragging a file)
- [ ] Markers (`**`, `#`, `>`…) fade on other lines and reappear on the caret line
- [ ] Checkboxes render and toggle on click; ⌘⏎ toggles the caret line; checked items strike through
- [ ] ⏎ continues bullets / numbers / checklists / quotes; ⏎ on an empty item ends the list; Tab / ⇧Tab indent; numbers renumber after edits and ⌘⌥↑/↓ moves
- [ ] Typing `[] ` makes a checklist item
- [ ] ⌘B ⌘I ⌘U ⇧⌘X ⇧⌘H ⌘E ⌘K, ⌘1–3, ⇧⌘8, ⇧⌘7, ⇧⌘L all work; the floating bar appears over a selection; Aa menu works
- [ ] ⌘-click opens a link; `||secret||` shows •••• and reveals on click
- [ ] Paste a screenshot (⌘⇧⌃4 then ⌘V) → image appears inline, file in Notes/attachments
- [ ] ⌘F opens the find bar; undo/redo work across list edits
- [ ] ≡, pinch and holding ⌃⇧ over the panel toggle list ↔ note; + creates a note
- [ ] List: pinned first, previews, × on hover deletes to Trash, right-click Pin / Duplicate / Show in Finder
- [ ] Search finds text inside notes
- [ ] Rename the first line, close the shelf → the file is renamed in Finder
- [ ] Edit a note in TextEdit while it has unsaved changes here → a "(conflict …)" copy appears, nothing lost
- [ ] Quit right after typing → the text is on disk; a 10,000-line note still opens and types without lag
- [ ] Notes folder and font size settings apply live

## Cross-panel
- [ ] Right-click a clip → Send to Note ▸ recent note / New Note; toast "Added to …"; an image clip lands inline; the open note shows the addition without losing what you typed
- [ ] ⌘⇧F opens search over the shelf; results in Clipboard / Files / Notes; ↑/↓ + ⏎ and click act (paste / open file / open note); Esc closes only the search
- [ ] Right-click a note → Float as Sticky; it stays on top over other apps, Spaces and full-screen apps
- [ ] Move/resize a sticky, quit, relaunch → it reopens in the same place
- [ ] Type in the same note in the shelf and in the sticky → both show the text, nothing lost
- [ ] Rename a sticky's note (first line) → the sticky's title follows; delete the note → the sticky closes
- [ ] Closing a sticky keeps the note

## Performance (Release, measured 2026-10-11, Apple Silicon, macOS 27.0.1)

| | Target | Measured |
|---|---|---|
| Memory, closed | ≤ 80 MB | 20 MB |
| Memory, open (placeholder columns) | ≤ 150 MB | 22 MB |
| Idle CPU | ~0.0 % | 0.0 % |
| Idle wake-ups/s | ≤ 2 | 0 |
| Threads | ≤ 7 | 3 |
| Binary | Universal | x86_64 + arm64, 2.0 MB |

After Clipboard (45 text + 5 × 3000×2000 image clips): closed 20 MB, 0.0 % CPU, 4 threads; open 31 MB. Idle wake-ups (Activity Monitor) 0 — the 0.5 s clipboard timer still fires (~8 context switches/s) but is coalesced.

After Files (300-file drawer incl. 100 × 3000×2000 PNGs): closed 21 MB, open 33 MB, 0.0 % CPU, 4 threads.

After Notes (200 notes + a 10,000-line note open): closed 22 MB, open 61 MB, 0.0 % CPU, 4 threads.
