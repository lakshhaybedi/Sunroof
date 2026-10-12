#!/usr/bin/env -S python3 -I
"""Copy Unclutter's notes into Sunroof's Notes folder.

Usage: scripts/import-unclutter-notes.py [--dry-run] [UNCLUTTER_NOTES_DIR] [SUNROOF_NOTES_DIR]

- Folders default to the ones each app is set to use (from their preferences).
- Each Unclutter .txt note becomes "<first line>.md" (Sunroof's naming); the original date is kept.
- Unclutter's files are only read, never changed. Notes already imported (same text) are skipped,
  so running it again is safe.
"""
import os
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
UNCLUTTER_DEFAULT = HOME / "Library/Containers/com.softwareambience.Unclutter/Data/Library/Application Support/Unclutter/Notes"
SUNROOF_DEFAULT = HOME / "Documents/Sunroof Notes"


def pref(domain, key):
    r = subprocess.run(["defaults", "read", domain, key], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None


def title_of(text):
    first = text.replace("\r\n", "\n").split("\n", 1)[0]
    return first.lstrip("# ").strip()


def filename_for(title):
    """Same rules as NoteStore.filename(forTitle:)."""
    t = title.replace("/", "-").replace(":", "-").strip().lstrip(".")
    t = t[:100].strip()
    while len(t.encode()) > 250:
        t = t[:-1]
    return (t or "Untitled") + ".md"


def unique(folder, name):
    path = folder / name
    stem, ext = os.path.splitext(name)
    n = 2
    while path.exists():
        path = folder / f"{stem} {n}{ext}"
        n += 1
    return path


def read(path):
    data = path.read_bytes()
    for enc in ("utf-8", "utf-16"):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            pass
    return data.decode("latin-1")


def main(argv):
    dry = "--dry-run" in argv
    args = [a for a in argv if a != "--dry-run"]
    src = Path(args[0]) if args else Path(pref("com.softwareambience.Unclutter", "NotesFolder") or UNCLUTTER_DEFAULT)
    dst = Path(args[1]) if len(args) > 1 else Path(pref("com.lakshhaybedi.Sunroof", "settings.notesFolder") or SUNROOF_DEFAULT)
    if not src.is_dir():
        sys.exit(f"Unclutter notes folder not found: {src}")

    existing = {read(p).strip() for p in dst.glob("*.md")} if dst.is_dir() else set()
    copied = skipped = empty = 0
    for note in sorted(src.glob("*.txt")):
        text = read(note).replace("\r\n", "\n")
        if not text.strip():
            empty += 1
            continue
        if text.strip() in existing:
            skipped += 1
            continue
        title = title_of(text) or note.stem
        target = unique(dst, filename_for(title))
        print(f"{'Would copy' if dry else 'Copied'}: {note.name} → {target.name}")
        if not dry:
            dst.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8")
            st = note.stat()
            os.utime(target, (st.st_atime, st.st_mtime))  # keep the note's date
        existing.add(text.strip())
        copied += 1

    verb = "Would copy" if dry else "Copied"
    print(f"\n{verb} {copied} note(s) into {dst}; {skipped} already there, {empty} empty skipped.")


if __name__ == "__main__":
    main(sys.argv[1:])
