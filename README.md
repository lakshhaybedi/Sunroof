# Sunroof

Your clipboard, files and notes, one scroll away. Move the pointer to the very top of the screen and scroll down — a strip slides down with three panels:

- **Clipboard** — history with source apps, favourites, search, paste straight into the app you were in, concealed password-manager clips.
- **Files** — a drop zone for things you need nearby: move, copy or alias in; drag out anywhere; Quick Look; auto-cleanup; screenshot catcher.
- **Notes** — plain markdown files with live styling: clickable checklists, auto-numbered lists, headings, highlights, images.

Plus Send to Note, ⌘⇧F search across everything, and floating sticky notes. Native Swift/SwiftUI for macOS 26+, Universal, ~20 MB of memory at idle.

## Install

Download the latest `.dmg` from [Releases](https://github.com/lakshhaybedi/Sunroof/releases), open it and drag Sunroof to Applications. If a release is marked *unsigned*, macOS blocks the first launch: try to open it once, then go to System Settings › Privacy & Security and click **Open Anyway**.

## Permissions

- **Accessibility** — only to paste for you (⏎ in the clipboard). Without it, clips are copied and you press ⌘V.
- **Documents / Desktop** — macOS asks once when Sunroof first uses its folders (Desktop only for the screenshot catcher).

Nothing leaves your Mac. Notes and Files are ordinary files in folders you choose — put them in iCloud Drive or Dropbox to sync. Clipboard history stays local; concealed clips are never written to disk.

## Build from source

```bash
brew install xcodegen
xcodegen && open Sunroof.xcodeproj
```

`./test.sh` runs the unit tests. See [RELEASING.md](RELEASING.md) for packaging and releases, and [docs/manual-checklist.md](docs/manual-checklist.md) for the manual test pass.

## License

MIT — see [LICENSE](LICENSE).
