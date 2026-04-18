# sshido

An iOS/iPadOS terminal built for driving AI coding agents (Claude Code, Codex,
aider, etc.) from your phone. SSH/Mosh transport, tmux-per-session, and a
push-notification relay so you get an APNs alert the moment your agent finishes
a task or needs input.

## Architecture

Swift Package Manager multi-module, assembled into a single iOS target:

- **sshidoModels** — domain types (`Host`, `Identity`, `Session`, `PushSubscription`).
- **sshidoCore** — SSH channels (via Citadel), keychain, network monitoring, session orchestration (`SessionStore`).
- **sshidoUI** — terminal view wrapper (SwiftTerm), Metal chrome, command palette, agent bar.
- **AppUI** — SwiftUI app shell and settings surface.

The push path is a separate Go service in `server/sshido-relay/` deployed to
Cloud Run. It receives JSON POSTs from whatever machine your agent runs on and
fans them out to APNs.

```
┌────────────────┐   hook    ┌──────────────┐   APNs   ┌────────┐
│ Claude Code    │ ────────► │ sshido-relay │ ───────► │ iPhone │
│ on remote host │   (POST)  │ (Cloud Run)  │          │        │
└────────────────┘           └──────────────┘          └────────┘
```

## Push notification setup

The whole flow is driven from the iPhone app and a prompt you paste into your
agent. Users do **not** clone this repo or run an installer — the agent sets
itself up on the remote host.

### 1. Subscribe from the iPhone

Open sshido → **Settings** → paste a push server URL → **Save & subscribe**.

- Default hosted relay: `https://push.sshido.com` (free, runs on Cloud Run).
- Or self-hosted — see [Self-hosting the relay](#self-hosting-the-relay) below.

After subscribing, Settings shows a **Notify URL** (e.g.
`https://push.sshido.com/n/<capability-token>`). That URL is your personal push
endpoint — treat it like a secret.

### 2. Let your agent configure itself

SSH into your remote host from the sshido app, launch Claude Code, then:

1. In Settings, tap the copy icon next to your subscription — this copies a
   self-contained setup prompt with your Notify URL already inlined.
2. Paste into Claude Code and let it run.

The agent creates `~/.sshido/notify.url`, writes `~/.claude/hooks/notify.sh`,
merges three hooks (`Notification`, `Stop`, `StopFailure`) into
`~/.claude/settings.json`, and runs a verification `curl`. Expect HTTP 204 and
a test push on your phone when it finishes.

Every hook is gated on `$SSHIDO_SESSION`, which sshido exports in the shells
it opens. So pushes only fire from sessions launched through the iOS app —
never from local terminal work on the same host.

The exact prompt text lives in `SettingsView.agentSetupPrompt`
(`Sources/AppUI/SettingsView.swift`) if you want to audit what your agent will
do before pasting.

### 3. That's it

Start working. When Claude Code needs input or finishes, you get a push.

If nothing arrives after a real task:

- confirm `~/.sshido/notify.url` on the remote host matches your Notify URL,
- run `curl -fsS -X POST -H 'content-type: application/json' -d '{"title":"x","body":"y"}' "$(cat ~/.sshido/notify.url)"` and expect HTTP 204,
- check **Settings → Notifications → sshido** on the iPhone is enabled.

## Self-hosting the relay

`push.sshido.com` is a single Cloud Run service anyone can stand up. To run
your own, you need an Apple Developer account (for an APNs `.p8` key) and a
GCP project. Full walkthrough and the deploy script:
[`server/sshido-relay/README.md`](server/sshido-relay/README.md).

Short version:

```sh
cd server/sshido-relay
GCP_PROJECT=your-project \
  APNS_KEY_ID=XXXXXXXXXX \
  APNS_TEAM_ID=XXXXXXXXXX \
  APNS_PRODUCTION=true \
  ./deploy-cloud-run.sh
```

Use the resulting Cloud Run URL as your push server URL in the iOS app.

## Development

```sh
make generate   # regenerate Xcode project from XcodeProject/project.yml
open XcodeProject/sshido.xcodeproj
```

The app target pulls source from `Sources/{Models,Core,UI,AppUI}/`. The Go
relay in `server/sshido-relay/` is built entirely separately (Docker → Cloud
Run) and is not linked into the app binary.
