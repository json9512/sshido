#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT=XcodeProject/sshido.xcodeproj
SCHEME=sshido
ARCHIVE=build/sshido.xcarchive
EXPORT_DIR=build/ipa
EXPORT_PLIST=XcodeProject/ExportOptions.plist

make generate

TEAM=$(awk -F= '/^DEVELOPMENT_TEAM/{gsub(/ /,"",$2); print $2}' XcodeProject/Signing.local.xcconfig 2>/dev/null || true)
if [[ -z "$TEAM" ]]; then
  echo "❌ DEVELOPMENT_TEAM not set. Put it in XcodeProject/Signing.local.xcconfig"
  exit 1
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  archive

TMP_EXPORT_PLIST=$(mktemp -t sshido-export.XXXXXX.plist)
cp "$EXPORT_PLIST" "$TMP_EXPORT_PLIST"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM" "$TMP_EXPORT_PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :teamID $TEAM" "$TMP_EXPORT_PLIST"

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$TMP_EXPORT_PLIST" \
  -allowProvisioningUpdates
rm -f "$TMP_EXPORT_PLIST"

echo
echo "✅ Archive:  $ARCHIVE"
echo "✅ IPA:      $EXPORT_DIR/sshido.ipa"
echo
echo "Next: xcrun altool --upload-app -f $EXPORT_DIR/sshido.ipa -t ios -u <your-apple-id> -p <app-specific-password>"
echo "  or: open $ARCHIVE  (Xcode Organizer → Distribute App → App Store Connect)"
