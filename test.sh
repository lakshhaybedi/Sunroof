#!/bin/bash
# Usage: ./test.sh [SuiteName]   — regenerates the project, runs unit tests, prints results only.
cd "$(dirname "$0")"
xcodegen -q || exit 1
xcodebuild test -project ShelfScroll.xcodeproj -scheme ShelfScroll \
  -destination 'platform=macOS,arch=arm64' ${1:+-only-testing:ShelfScrollTests/$1} 2>&1 \
  | grep -E "error:|Test .*(passed|failed)|Expectation failed|TEST (SUCCEEDED|FAILED)"
exit "${PIPESTATUS[0]:-0}"
