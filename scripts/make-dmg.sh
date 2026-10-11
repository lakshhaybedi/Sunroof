#!/bin/bash
# Usage: scripts/make-dmg.sh path/to/Sunroof.app output-dir
# Builds Sunroof-<version>.dmg containing the app and an Applications shortcut.
set -euo pipefail
APP="${1:?path to Sunroof.app}"
OUT="${2:?output directory}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$OUT/Sunroof-$VERSION.dmg"

# A leftover mounted volume from an earlier run would make hdiutil fail.
for v in /Volumes/Sunroof*; do [ -d "$v" ] && hdiutil detach -quiet -force "$v" || true; done

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$OUT"
hdiutil create -quiet -volname Sunroof -srcfolder "$STAGE" -format UDZO -ov "$DMG"
echo "$DMG"
