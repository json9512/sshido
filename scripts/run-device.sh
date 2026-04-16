#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

PROJECT="XcodeProject/sshido.xcodeproj"
SCHEME="sshido"
CONFIG="${CONFIG:-Debug}"

device_id="$(xcrun devicectl list devices 2>/dev/null \
  | grep -Ei 'iPhone|iPad' \
  | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
  | head -1)"
if [[ -z "${device_id:-}" ]]; then
    device_id="$(xcrun devicectl list devices 2>/dev/null \
      | grep -Ei 'iPhone|iPad' \
      | grep -oE '[0-9a-fA-F]{40}' | head -1)"
fi

if [[ -z "${device_id:-}" ]]; then
    echo "✗ No tethered iPhone/iPad found. Plug in, unlock, trust this Mac." >&2
    echo "  Also ensure Developer Mode is enabled (Settings → Privacy & Security → Developer Mode)." >&2
    exit 1
fi

team="$(awk -F= '/^DEVELOPMENT_TEAM/ {gsub(/ /,"",$2); print $2}' XcodeProject/Signing.local.xcconfig)"
bundle="$(awk -F= '/^BUNDLE_ID/ {gsub(/ /,"",$2); print $2}' XcodeProject/Signing.local.xcconfig)"

echo "▶ Building for device ${device_id} (team=$team bundle=$bundle)..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination "id=$device_id" -derivedDataPath build \
  DEVELOPMENT_TEAM="$team" PRODUCT_BUNDLE_IDENTIFIER="$bundle" \
  CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates build

app_path="$(find build/Build/Products -maxdepth 3 -name '*.app' -type d | head -1)"
if [[ -z "$app_path" ]]; then echo "✗ .app not produced"; exit 1; fi

echo "▶ Installing + launching $app_path on ${device_id}..."
xcrun devicectl device install app --device "$device_id" "$app_path"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app_path/Info.plist" 2>/dev/null || echo "$bundle")"
xcrun devicectl device process launch --device "$device_id" "$bundle_id"
