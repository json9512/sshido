# App Store Optimization (ASO)

## The core problem

"sshido" is a coined word with **zero organic search volume**. The App Store
weights the **app name** and **subtitle** far above the keyword field, so today
the two highest-weighted ranking slots are spent on a term nobody types. Metadata
is the fixable blocker. (Rankings also depend on installs, ratings, and download
velocity — metadata gets you *eligible* to rank; it is necessary, not sufficient.)

## Hard constraints

- **Do not use "mosh" as a keyword.** There is no Mosh implementation (transport
  is SSH via Citadel + tmux). Claiming it invites App Review rejection.
- **Do not advertise voice/AI dictation** on any public surface (listing,
  screenshots, description) until the feature is device-validated — see
  [ADR 0001](adr/0001-voice-input-deferred.md).
- No competitor trademarks as keywords (e.g. "putty," "termius").

## How the fields combine (why the copy below is coordinated)

The App Store indexes **name + subtitle + keywords as one combined bag of words**
and **dedupes** — a word in the name is wasted if repeated in keywords, and it
already combines across fields (e.g. "ssh" in the name + "keys" in keywords lets
you rank for "ssh keys"). So the three fields below deliberately share **no
words**: the name/subtitle take the high-volume category terms, and the keyword
field spends its 100 chars entirely on *new* terms.

## Ready-to-paste copy (App Store Connect → App Information / Localization)

**App Name** (≤30 chars) — brand first so existing searches still land, then the
two highest-volume category terms:
```
sshido: SSH Client & Terminal
```
Alternates: `sshido — SSH Terminal & tmux` · `sshido: SSH Client, Terminal`

**Subtitle** (≤30 chars) — different words from the name:
```
tmux & push for coding agents
```
Alternates: `tmux, SSH keys & push alerts` · `Shell, tmux & remote servers`

**Keywords** (≤100 chars, comma-separated, no spaces, no words already in the
name/subtitle):
```
shell,console,sftp,scp,ssh keys,sysadmin,devops,remote,server,linux,unix,claude code,codex,aider
```

**Promotional text** (≤170 chars, updatable without a review):
```
Drive Claude Code, Codex, or any SSH server from your phone. Persistent tmux sessions and a push alert the moment your agent needs you.
```

**Description** (≤4000 chars) — front-load keywords in the first two lines (the
only part shown before "more"):
```
sshido is a fast, private SSH client and terminal for iPhone and iPad, built for
driving AI coding agents — Claude Code, Codex, aider — from anywhere.

• SSH & tmux — real xterm-256color terminal, Metal-rendered for speed, with
  persistent tmux sessions that survive reconnects and network drops.
• Push notifications — get an APNs alert the instant your agent finishes a task
  or needs input, via a free open-source relay you can self-host.
• Private by design — Ed25519/RSA keys stored in the iOS Keychain, host-key
  TOFU verification, and no terminal data sent to any third party.
• Built for developers — customizable hotkey bar (Esc, Ctrl-C, arrows, newline,
  word-delete), one-tap OAuth sign-in helper, image upload, and smart copy of
  URLs and output.

Self-hosting the push relay is free and always will be.
```

## Non-metadata levers (metadata gets you eligible; these get you ranked)

1. **Screenshots + preview video** — the first two drive tap-through/conversion,
   which feeds ranking. Caption them with searched phrases: "SSH terminal with
   tmux," "Alerts from your coding agent," "Ed25519 keys in the Keychain."
2. **Ratings & review velocity** — a tasteful in-app rate prompt after a few
   successful sessions.
3. **Install velocity** in the first days after each release.

## Korean localization (the App Store Connect account is Korean)

Add a Korean localization for a whole extra keyword field aimed at Korean search:
- Subtitle idea: `개발자를 위한 SSH 터미널`
- Keywords idea: `터미널,ssh,서버,원격,쉘,개발자,클로드,코덱스`

## Repo-side actions

1. **Set an explicit display name.** `Sources/AppUI/Info.plist` has no
   `CFBundleDisplayName`, so the home-screen name defaults to `sshido` (separate
   from the App Store name).
2. **Version-control the metadata (recommended).** Add a `fastlane/metadata/`
   tree + a `deliver` lane so ASO copy is reviewed in git, not edited blind in
   App Store Connect. The strings above are the seed content.
3. **Support URL** is set to `https://sshido.com`. Fill the **Marketing URL**
   too (an incomplete listing can suppress ranking eligibility).
