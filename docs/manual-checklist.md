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

## Performance (Release, measured 2026-10-11, Apple Silicon, macOS 27.0.1)

| | Target | Measured |
|---|---|---|
| Memory, closed | ≤ 80 MB | 20 MB |
| Memory, open (placeholder columns) | ≤ 150 MB | 22 MB |
| Idle CPU | ~0.0 % | 0.0 % |
| Idle wake-ups/s | ≤ 2 | 0 |
| Threads | ≤ 7 | 3 |
| Binary | Universal | x86_64 + arm64, 2.0 MB |
