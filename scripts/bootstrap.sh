#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"

echo "▶ Checking Xcode command-line tools…"
xcode-select -p >/dev/null 2>&1 || xcode-select --install || true

if ! command -v brew >/dev/null; then
    echo "✗ Homebrew required: https://brew.sh" >&2
    exit 1
fi

echo "▶ Installing build tools via brew…"
brew list xcodegen   >/dev/null 2>&1 || brew install xcodegen
brew list ios-deploy >/dev/null 2>&1 || brew install ios-deploy
brew list fastlane   >/dev/null 2>&1 || brew install fastlane

local_cfg="$here/XcodeProject/Signing.local.xcconfig"
if [[ ! -f "$local_cfg" ]]; then
    cp "$here/XcodeProject/Signing.local.xcconfig.example" "$local_cfg"
    echo ""
    echo "✏️  Edit $local_cfg and set DEVELOPMENT_TEAM + BUNDLE_ID."
    echo "    Find your Team ID at https://developer.apple.com/account → Membership."
fi

echo ""
echo "✅ bootstrap complete. Next:"
echo "   1. Edit XcodeProject/Signing.local.xcconfig"
echo "   2. Enable Developer Mode on your iPhone (Settings → Privacy & Security)"
echo "   3. Plug phone in, run: make run"
