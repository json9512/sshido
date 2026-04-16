# TestFlight submission

## One-time setup

1. **App Store Connect** — create a new app record:
   - Bundle ID: `com.sshido.app`
   - SKU: `sshido`
   - Primary language: English (U.S.)
   - Platforms: iOS, iPadOS

2. **Apple Developer portal** — verify capabilities on the App ID:
   - Push Notifications ✅
   - Keychain Sharing (if we add it later)
   - Background Modes: Remote notifications ✅

3. **APNs key** — your `.p8` lives somewhere on disk (e.g. `~/pass/apns/AuthKey_XXXXXXXXXX.p8`).
   Key id + team id are configured in the relay's launch flags, not bundled
   with the app.

4. **App-specific password** for `altool` (optional — only if uploading via CLI):
   https://appleid.apple.com → Sign-In and Security → App-Specific Passwords.

## Per-submission flow

### Option A — fastlane (recommended)

One-time:
```
bundle install
echo 'apple_id("you@example.com")' > fastlane/Appfile.local
```

Each release:
```
make beta   # bump + archive + upload_to_testflight
```

fastlane prompts for the 2FA code the first time; subsequent runs reuse the
session (`FASTLANE_SESSION` env var or `fastlane spaceauth`).

### Option B — raw xcodebuild

```
make bump      # increments Info.plist CFBundleVersion
make archive   # Release archive → IPA under build/ipa/sshido.ipa
```

Then either:
- **CLI**: `xcrun altool --upload-app -f build/ipa/sshido.ipa -t ios -u <apple-id> -p <app-specific-password>`
- **Xcode**: open `build/sshido.xcarchive` → Organizer → Distribute App → App Store Connect

Processing on Apple's side takes 10-30 minutes. Then add build to a TestFlight
group in App Store Connect and invite testers.

## Required App Store Connect content

Fill before first submission:
- **App Description** (4000 char max)
- **Keywords** (100 char)
- **Support URL** (your docs or a tailscale'd page for now)
- **Screenshots** — 6.7" (iPhone 15 Pro Max), 6.1" (iPhone 15), iPad 12.9"
  - Provide at least 1 per required size.
- **Privacy Nutrition Labels**:
  - Data Not Linked to You: Diagnostics (crash reports via MetricKit, opt-in)
  - Permissions: Microphone (voice dictation), Speech Recognition (on-device),
    Notifications, Local Network (push relay)
- **Encryption export compliance** — "Uses standard encryption (SSH)". Answer
  "Yes, uses exempt standard encryption" in the ITSAppUsesNonExemptEncryption
  question.
- **Review notes** — include a test SSH host credential, or the note "Requires
  a user-supplied SSH host. Reviewer may use a temporary Tailscale node at
  `reviewer-mac.tail-xxxx.ts.net`, password `redacted`." if you set one up.

## Checklist before each submission

- [ ] `make bump` (build number increment)
- [ ] Launch on device, walk Help → FAQ, confirm links render
- [ ] Verify no `development` strings in Release entitlements
- [ ] `make archive` succeeds
- [ ] Upload via Organizer or `altool`
- [ ] Monitor email for "Invalid binary" rejections
