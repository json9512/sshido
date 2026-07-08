# App Store Optimization (ASO)

## The core problem

"sshido" is a coined word with **zero organic search volume**. The App Store
weights the **app name** highest in its search ranking, so today the single most
important ranking field is spent on a term nobody types. There is also no
subtitle or keyword copy version-controlled in this repo (metadata lives only in
App Store Connect; `fastlane/Fastfile` only uploads TestFlight builds, never
`deliver`). Net effect: the app matches almost no searched queries → no rankings.

Metadata is the fixable blocker. (Rankings also depend on installs, ratings, and
download velocity — metadata gets you *eligible* to rank; it is necessary, not
sufficient.)

## Hard constraint

**Do not use "mosh" as a keyword.** There is no Mosh implementation in the
codebase (transport is SSH via Citadel + tmux). Claiming it invites App Review
rejection and misleads users.

## Ready-to-paste copy (App Store Connect → App Information / Localization)

**App Name** (≤30 chars) — keep the brand first so existing searches still land,
then the top-intent keyword:
```
sshido: SSH Client & Terminal
```

**Subtitle** (≤30 chars) — different words from the name (Apple dedups stems):
```
tmux, push alerts & AI agents
```

**Keywords** (≤100 chars, comma-separated, no spaces, no words already in the
name/subtitle since Apple dedups them):
```
shell,console,sftp,scp,ssh keys,sysadmin,devops,remote server,unix,linux,claude code,codex,aider
```

**Promotional text** (≤170 chars, updatable without a review):
```
Drive Claude Code, Codex, or any SSH server from your phone. Persistent tmux sessions and a push alert the moment your agent needs you.
```

**Description** (≤4000 chars) — front-load the keywords in the first two lines
(the only part shown before "more"):
```
sshido is a fast, private SSH client and terminal for iPhone and iPad, built for
driving AI coding agents — Claude Code, Codex, aider — from anywhere.

• SSH & tmux — real xterm-256color terminal, Metal-rendered for speed, with
  persistent tmux sessions that survive reconnects and network drops.
• Push notifications — get an APNs alert the instant your agent finishes a task
  or needs input, via a free open-source relay you can self-host.
• Private by design — Ed25519/RSA keys stored in the iOS Keychain, host-key
  TOFU verification, and no audio or terminal data sent to any third party.
• Built for developers — customizable hotkey bar (Esc, Ctrl-C, arrows, newline),
  one-tap OAuth sign-in helper, image upload, and smart copy of URLs and output.

Self-hosting the push relay is free and always will be.
```

## Repo-side actions

1. **Set an explicit display name.** `Sources/AppUI/Info.plist` has no
   `CFBundleDisplayName`, so the home-screen name defaults to `sshido`. Decide it
   deliberately (the App Store name and home-screen name are separate fields).

2. **Version-control the metadata (recommended).** Add a `fastlane/metadata/`
   tree (name, subtitle, keywords, description, promotional_text, urls) and a
   `deliver` lane so ASO copy is reviewed in git instead of edited blind in App
   Store Connect. This is currently a gap called out in `TESTFLIGHT.md:55-60`.
   The strings above are the seed content for that tree.

3. **Support/marketing URL** — `TESTFLIGHT.md` lists Support URL as still-needed.
   Point it at the existing site (`sshido.com` / status page) so the listing is
   complete (incomplete listings can suppress ranking eligibility).

## Screenshots (App Store Connect only, not in repo)

The first two screenshots drive conversion and indirectly ranking. Caption them
with keyword phrases users search: "SSH terminal with tmux," "Push alerts from
your coding agent," "Ed25519 keys in the Keychain." (The `app-store-screenshots`
skill can generate these.)
