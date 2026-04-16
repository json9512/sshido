#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"

check() { printf "%-28s" "$1"; shift; if "$@" >/dev/null 2>&1; then echo "✅"; else echo "❌"; fi; }

check "xcode-select"        xcode-select -p
check "xcodebuild"          xcodebuild -version
check "xcodegen"            command -v xcodegen
check "ios-deploy"          command -v ios-deploy
check "Signing.local.xcconfig" test -f "$here/XcodeProject/Signing.local.xcconfig"
check "physical device"     bash -c '[ -n "$(xcrun devicectl list devices 2>/dev/null | grep -Ei "iphone|ipad" || true)" ]'
