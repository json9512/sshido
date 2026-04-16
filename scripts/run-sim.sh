#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

DEVICE="${SIM_DEVICE:-iPhone 15}"
BUNDLE_ID="$(grep -E '^BUNDLE_ID' XcodeProject/Signing.local.xcconfig 2>/dev/null | awk -F= '{print $2}' | xargs || echo com.example.sshido)"

xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator
app_path="$(find build/Build/Products -maxdepth 3 -name '*.app' -type d | head -1)"
xcrun simctl install "$DEVICE" "$app_path"
xcrun simctl launch "$DEVICE" "$BUNDLE_ID"
