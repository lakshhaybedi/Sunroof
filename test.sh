#!/bin/bash
# Usage: ./test.sh [SuiteName]   — regenerates the project, runs unit tests, prints results only.
cd "$(dirname "$0")"
xcodegen -q || exit 1
xcodebuild test -project Sunroof.xcodeproj -scheme Sunroof \
  -destination 'platform=macOS,arch=arm64' ${1:+-only-testing:SunroofTests/$1} 2>&1 \
  | grep -v "Error Domain" | grep -E "[^ ] error: |Test .*(passed|failed)|Expectation failed|TEST (SUCCEEDED|FAILED)"
exit "${PIPESTATUS[0]}"
