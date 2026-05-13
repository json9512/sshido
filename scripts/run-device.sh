#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

PROJECT="XcodeProject/sshido.xcodeproj"
SCHEME="sshido"
CONFIG="${CONFIG:-Debug}"

# Pull the device's hardware UDID via `xctrace`, which formats it as
# `8hex-16hex` (e.g. 00008130-001A755E20EB8D3A) — the format xcodebuild's
# `id=` destination accepts. `devicectl list devices` reports a different
# CoreDevice UUID that xcodebuild rejects as not matching any destination.
# Older devices use a 40-char hex UDID; fall back to that.
device_lines="$(xcrun xctrace list devices 2>&1 \
  | awk '/^== Simulators ==/{exit} /iPhone|iPad/{print}')"
device_id="$(echo "$device_lines" \
  | grep -oE '\([0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\)' \
  | tail -1 \
  | tr -d '()')"
if [[ -z "${device_id:-}" ]]; then
    device_id="$(echo "$device_lines" \
      | grep -oE '\([0-9A-Fa-f]{40}\)' \
      | tail -1 \
      | tr -d '()')"
fi

if [[ -z "${device_id:-}" ]]; then
    echo "✗ No tethered iPhone/iPad found." >&2
    echo "  • Plug in, unlock, trust this Mac." >&2
    echo "  • Enable Developer Mode (Settings → Privacy & Security → Developer Mode)." >&2
    echo "  • Verify with: xcrun xctrace list devices" >&2
    exit 1
fi

team="$(awk -F= '/^DEVELOPMENT_TEAM/ {gsub(/ /,"",$2); print $2}' XcodeProject/Signing.local.xcconfig)"
bundle="$(awk -F= '/^BUNDLE_ID/ {gsub(/ /,"",$2); print $2}' XcodeProject/Signing.local.xcconfig)"

echo "▶ Building for device ${device_id} (team=$team bundle=$bundle)..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination "id=$device_id" -derivedDataPath build \
  DEVELOPMENT_TEAM="$team" PRODUCT_BUNDLE_IDENTIFIER="$bundle" \
  CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates build

# Scope to Debug-iphoneos/Release-iphoneos so a stale simulator-build
# .app doesn't get picked up and installed instead — that path would
# fail with the install-time codesign error 0xe8008014 ("invalid
# signature") because simulator binaries aren't signed for device.
app_path="$(find "build/Build/Products/${CONFIG}-iphoneos" -maxdepth 2 -name '*.app' -type d 2>/dev/null | head -1)"
if [[ -z "$app_path" ]]; then echo "✗ device .app not produced under build/Build/Products/${CONFIG}-iphoneos"; exit 1; fi

echo "▶ Installing + launching $app_path on ${device_id}..."
xcrun devicectl device install app --device "$device_id" "$app_path"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app_path/Info.plist" 2>/dev/null || echo "$bundle")"
xcrun devicectl device process launch --device "$device_id" "$bundle_id"
