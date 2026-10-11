#!/bin/bash
# Usage: scripts/perf.sh [path/to/Sunroof.app]
# Measures idle memory / CPU / wake-ups / threads with the shelf closed and open, against the §8 budget.
# Uses temporary Files/Notes/Favorites folders, pauses clipboard recording, and restores your settings afterwards.
# (Clipboard history in ~/Library/Application Support/Sunroof is read, never changed while paused.)
set -uo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Build/Products/Release/Sunroof.app}"
DOMAIN=com.lakshhaybedi.Sunroof
WORK=$(mktemp -d)
BACKUP="$WORK/defaults.plist"
HAD_DEFAULTS=0
defaults export "$DOMAIN" "$BACKUP" 2>/dev/null && HAD_DEFAULTS=1

cleanup() {
    pkill -x Sunroof 2>/dev/null
    defaults delete "$DOMAIN" 2>/dev/null
    if [ "$HAD_DEFAULTS" = 1 ] && ! defaults import "$DOMAIN" "$BACKUP"; then
        echo "Couldn't restore your settings — backup kept at $BACKUP (restore: defaults import $DOMAIN \"$BACKUP\")"
        return
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

pkill -x Sunroof 2>/dev/null && sleep 1 # measure a fresh instance
defaults delete "$DOMAIN" 2>/dev/null
defaults write "$DOMAIN" settings.hasCompletedOnboarding -bool true
defaults write "$DOMAIN" settings.filesFolder "$WORK/Files"
defaults write "$DOMAIN" settings.notesFolder "$WORK/Notes"
defaults write "$DOMAIN" settings.favoritesFolder "$WORK/Favorites"
defaults write "$DOMAIN" settings.clipboardPaused -bool true # don't record what you copy during the run

measure() { # $1 = label
    open "$APP"; sleep 60
    local pid; pid=$(pgrep -x Sunroof) || { echo "| $1 | crashed | | | |"; return 1; }
    local mem; mem=$(footprint "$pid" | sed -nE 's/.*Footprint: ([0-9.]+) (KB|MB|GB).*/\1 \2/p' | head -1)
    local stats; stats=$(top -l 3 -s 5 -pid "$pid" -stats cpu,idlew,th | tail -1)
    read -r cpu wake threads <<<"$stats"
    echo "| $1 | $mem | $cpu % | $wake | $threads |"
    MB=$(echo "$mem" | awk '{print ($2=="GB") ? $1*1024 : ($2=="KB") ? $1/1024 : $1}')
    pkill -x Sunroof; sleep 1
}

echo "| State | Memory | CPU | Idle wake-ups | Threads |"
echo "|---|---|---|---|---|"
measure "Closed (budget ≤ 80 MB)"; closed=${MB:-999}
defaults write "$DOMAIN" settings.openOnLaunch -bool true
measure "Open (budget ≤ 150 MB)"; open=${MB:-999}
awk -v c="$closed" -v o="$open" 'BEGIN { exit !(c <= 80 && o <= 150) }' || { echo "Over the memory budget"; exit 1; }
