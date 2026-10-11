#!/bin/bash
# Usage: scripts/perf.sh [path/to/ShelfScroll.app]
# Measures idle memory / CPU / wake-ups / threads with the shelf closed and open, against the §8 budget.
# Uses temporary Files/Notes/Favorites folders and restores your ShelfScroll settings afterwards.
set -uo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Build/Products/Release/ShelfScroll.app}"
DOMAIN=com.lakshhaybedi.ShelfScroll
WORK=$(mktemp -d)
BACKUP="$WORK/defaults.plist"
HAD_DEFAULTS=0
defaults export "$DOMAIN" "$BACKUP" 2>/dev/null && HAD_DEFAULTS=1

cleanup() {
    pkill -x ShelfScroll 2>/dev/null
    defaults delete "$DOMAIN" 2>/dev/null
    [ "$HAD_DEFAULTS" = 1 ] && defaults import "$DOMAIN" "$BACKUP"
    rm -rf "$WORK"
}
trap cleanup EXIT

pkill -x ShelfScroll 2>/dev/null && sleep 1 # measure a fresh instance
defaults delete "$DOMAIN" 2>/dev/null
defaults write "$DOMAIN" settings.hasCompletedOnboarding -bool true
defaults write "$DOMAIN" settings.filesFolder "$WORK/Files"
defaults write "$DOMAIN" settings.notesFolder "$WORK/Notes"
defaults write "$DOMAIN" settings.favoritesFolder "$WORK/Favorites"

measure() { # $1 = label
    open "$APP"; sleep 60
    local pid; pid=$(pgrep -x ShelfScroll) || { echo "| $1 | crashed | | | |"; return 1; }
    local mem; mem=$(footprint "$pid" | sed -nE 's/.*Footprint: ([0-9.]+) (KB|MB|GB).*/\1 \2/p' | head -1)
    local stats; stats=$(top -l 3 -s 5 -pid "$pid" -stats cpu,idlew,th | tail -1)
    read -r cpu wake threads <<<"$stats"
    echo "| $1 | $mem | $cpu % | $wake | $threads |"
    MB=$(echo "$mem" | awk '{print ($2=="GB") ? $1*1024 : ($2=="KB") ? $1/1024 : $1}')
    pkill -x ShelfScroll; sleep 1
}

echo "| State | Memory | CPU | Idle wake-ups | Threads |"
echo "|---|---|---|---|---|"
measure "Closed (budget ≤ 80 MB)"; closed=${MB:-999}
defaults write "$DOMAIN" settings.openOnLaunch -bool true
measure "Open (budget ≤ 150 MB)"; open=${MB:-999}
awk -v c="$closed" -v o="$open" 'BEGIN { exit !(c <= 80 && o <= 150) }' || { echo "Over the memory budget"; exit 1; }
