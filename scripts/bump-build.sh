#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PLIST=Sources/AppUI/Info.plist
CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
NEXT=$((CURRENT + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT" "$PLIST"
echo "CFBundleVersion: $CURRENT → $NEXT"
