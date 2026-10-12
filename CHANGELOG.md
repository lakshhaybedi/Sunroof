# Changelog

## 0.2.2

- **Widgets float under the shelf**: they now sit in their own see-through tray below the shelf, so Clipboard, Files and Notes keep their full height. Each widget is a plain blurred card with a soft shadow, with no colour tint.

## 0.2.1

- **Clipboard**: click anywhere on a clip to copy it. It slides smoothly to the top, and a "Copied" note confirms it.
- **Files**: dragging a file to the top of the screen opens the shelf as soon as it reaches the menu bar, so Mission Control no longer gets in the way.
- **Files**: files dropped from a folder Sunroof can't change (such as the Desktop without Files & Folders access) are copied instead of failing.
- **Quick Look**: while previewing, the arrow keys move to the previous or next file, and Space closes the preview.

## 0.2.0

- **Widgets**: a band of widgets along the bottom of the shelf: **Calendar** (month view with an agenda), **Tasks** (Apple Reminders, or Sunroof's own list kept in `Tasks.md`), **Music** (Apple Music and Spotify), **Weather** (Open-Meteo, a city you pick or your location) and **System Stats** (CPU, memory, battery, disk, network).
- Drag widgets to rearrange them. Right-click a widget to resize or remove it, and use ＋ to add one. Drag the grip above the band to change how many rows it has. The layout is remembered per display.
- Widgets only run while the shelf is open, and macOS only asks for a permission when a widget needs it.
- Change widget settings, or turn widgets off, in *Settings › Widgets*.

## 0.1.1

- **Automatic updates**: Sunroof checks GitHub daily and downloads and installs new versions by itself. *Settings › General › Updates* has the toggles and a **Check Now** button, and the menu bar menu has **Check for Updates…**. Until releases are signed, re-allow Accessibility (for ⏎-to-paste) after an update installs.
- Easier clicking: every small button now responds across its whole area, not just the icon's pixels.
- A new menu bar icon: the roof with the sunroof open.
- The 0.1.0 → 0.1.1 move is manual (0.1.0 can't update itself); updates are automatic from here on.

## 0.1.0

First release.

- **Shelf**: a full-width strip that slides down from the top of the screen. Open it by scrolling down, holding a key or pausing at the top edge, by dragging a file up, or with a hotkey. Close it by scrolling up, pressing Esc or clicking away. Height and column widths are remembered per display; drag column titles to rearrange them.
- **Clipboard**: history (10/25/50) with source app icons; text, rich text, URLs, images, files and colours; favourites that sync; search; pause; ⏎ pastes into the app you were in, ⌥⏎ as plain text, ⌘1–9 quick paste. Password-manager clips are concealed and never touch disk.
- **Files**: a drop-zone drawer (move, ⌥ copy, ⌘⌥ alias), browser images and links, icons or list, folders inside the panel, Quick Look, rename, search with folder labels, auto-cleanup to the Trash, screenshot catcher.
- **Notes**: plain `.md` files with live markdown styling: a title line, checklists you click, auto-numbered lists, headings, highlights, code, quotes, links (⌘K field, ⌘-click to open), images and `||concealed||` text. Pins, search and conflict-safe sync.
- **Everywhere**: Send to Note, ⌘⇧F search across all three panels, floating sticky notes, accent colour, shelf tint, note font, Liquid Glass or solid, light/dark/auto.
- About 20 MB of memory at idle, 0 % CPU, no idle wake-ups. Universal (Apple Silicon + Intel), macOS 26+.
