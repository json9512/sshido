# sshido

An iOS/iPadOS terminal built for driving AI coding agents (Claude Code, Codex,
aider, etc.) from your phone. SSH transport, tmux-per-session, a
push-notification relay so you get an APNs alert the moment your agent finishes
a task or needs input, and an optional agent mode: a chat with an orchestrator
that runs subagents in Podman on one of your own machines.

## Architecture

Swift Package Manager multi-module, assembled into a single iOS target:

- **sshidoModels**: domain types (`RemoteHost`, `Identity`, `Session`, `PushSubscription`, agent mode types).
- **sshidoCore**: SSH channels (via Citadel), keychain, push, session orchestration, and the service protocols in `Services.swift` (`HostRepository`, `SessionManaging`, `PushServicing`, …) with `AppServices.live` wiring the real stores.
- **sshidoUI**: the Metal terminal view (SwiftTerm), mascot sprites, the hotkey bar.
- **AppUI**: the SwiftUI app. Each feature (`Features/Servers`, `Terminal`, `Agents`, `Notifications`, `General`) is an `AppFeature` that contributes home sections and Settings entries; `FeatureSet.live` lists them, so a feature is added or removed in one place. Views read services from the environment, never from singletons directly.

Two Go services live under `server/`:

- `server/sshido-relay/` forwards JSON POSTs from your machines to APNs. Markdown in a message is turned into plain text before it reaches the lock screen.
- `server/sshido-agents/` is the agent mode daemon and agent image, run in Podman on your host.

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

Open sshido → **Settings › Notifications** and tap the send button.

The App Store build always uses the hosted relay at `https://push.sshido.com`
(free, runs on Cloud Run), and the address can't be changed there. A build you
sign yourself can point at a relay you run — see
[Running your own relay](#running-your-own-relay) below.

After subscribing, the app holds a **Notify URL** (e.g.
`https://push.sshido.com/n/<capability-token>`). That URL is your personal push
endpoint — treat it like a secret.

### 2. Let your agent configure itself

SSH into your remote host from the sshido app, launch Claude Code, then:

1. In **Settings › Notifications**, tap the copy button next to your
   subscription. This copies a self-contained setup prompt with your Notify
   URL already inlined.
2. Paste into Claude Code and let it run.

The agent creates `~/.sshido/notify.url`, writes `~/.claude/hooks/notify.sh`,
merges three hooks (`Notification`, `Stop`, `StopFailure`) into
`~/.claude/settings.json`, and runs a verification `curl`. Expect HTTP 204 and
a test push on your phone when it finishes.

Every hook is gated on `$SSHIDO_SESSION`, which sshido exports in the shells
it opens. So pushes only fire from sessions launched through the iOS app —
never from local terminal work on the same host.

The exact prompt text lives in `PushSetupPrompt`
(`Sources/AppUI/Features/Notifications/NotificationsFeature.swift`) if you want
to audit what your agent will do before pasting. The same steps are in the app
under **Settings › Notifications › How push works**.

### 3. That's it

Start working. When Claude Code needs input or finishes, you get a push.

If nothing arrives after a real task:

- confirm `~/.sshido/notify.url` on the remote host matches your Notify URL,
- run `curl -fsS -X POST -H 'content-type: application/json' -d '{"title":"x","body":"y"}' "$(cat ~/.sshido/notify.url)"` and expect HTTP 204,
- check **Settings → Notifications → sshido** on the iPhone is enabled.

## The hosted relay

The relay's source is public at [`server/sshido-relay/`](server/sshido-relay/),
so you can check what `push.sshido.com` does with your data: it keeps a random
subscriber ID, your APNs device token, a notification count and a mute flag.
Alert titles and text pass through to Apple's push service and are not stored.

Public status: [status.sshido.com](https://status.sshido.com) (uptime probe
against `push.sshido.com/health`).

## Running your own relay

`push.sshido.com` is a single Cloud Run service built from
`server/sshido-relay/`. Apple only accepts pushes for an app signed with the
key of the team that ships it, so a relay you run yourself can reach **your
own build** of sshido, not the App Store build, which is locked to
`push.sshido.com`. To run your own you need:

- an Apple Developer account and an APNs `.p8` key,
- sshido built with your own bundle id (`XcodeProject/Signing.local.xcconfig`),
- a place to run the relay: any machine (`sqlite` storage) or a GCP project (`firestore` on Cloud Run).

Full walkthrough and the deploy script:
[`server/sshido-relay/README.md`](server/sshido-relay/README.md).

Short version on Cloud Run:

```sh
cd server/sshido-relay
GCP_PROJECT=your-project \
  APNS_KEY_ID=XXXXXXXXXX \
  APNS_TEAM_ID=XXXXXXXXXX \
  APNS_PRODUCTION=true \
  ./deploy-cloud-run.sh
```

Use the resulting URL as the push server in **Settings › Notifications** of
your build.

## Agent mode

Agent mode turns one of your SSH hosts into a place where coding agents run.
You chat with an orchestrator; it works out what you need, starts subagents
when that helps, checks their evidence and gives each a pass or fail verdict.
Every agent has its own Podman container with a shell, the internet, a
browser and a virtual desktop you can watch from the phone. sshido never pays
for or proxies a model: frontier harnesses (Claude Code, Codex, Gemini CLI,
Grok) use your own logins, and local models use your own OpenAI-compatible
endpoint.

1. Install Podman on the host (`brew install podman && podman machine init --memory 8192 && podman machine start` on a Mac).
2. Build the two images:

   ```sh
   cd server/sshido-agents
   podman build -f images/daemon/Containerfile -t localhost/sshido-agents:latest .
   podman build -f images/agent/Containerfile  -t localhost/sshido-agent:latest .
   ```

3. In the app, open **Settings › Agents**, turn agents on, pick the host and tap the box button under Host.
4. Choose frontier or local models for the orchestrator and subagents, and sign in to the frontier harnesses you picked.

The app walks through the same steps under **Settings › Set up a host**.
Details, environment variables and tests:
[`server/sshido-agents/README.md`](server/sshido-agents/README.md) and
[ADR 0008](docs/adr/0008-orchestrator-led-chats-work-records-desktop.md).

## Development

```sh
make generate   # regenerate Xcode project from XcodeProject/project.yml
open XcodeProject/sshido.xcodeproj
```

The app target pulls source from `Sources/{Models,Core,UI,AppUI}/`. The Go
services in `server/` are built separately and are not linked into the app.

UI animations are Lottie files generated by `scripts/make_animations.py` into
`Sources/AppUI/Resources/Animations/`; rerun it after editing an animation.
App Store screenshots are captured by the `screenshots` scheme
(`ScreenshotTests/`).

Built-in mascot sprite GIFs are not committed to this repo (their itch.io
licenses don't permit redistribution). The app builds and runs without
them; if you want mascots in your local build, see `docs/sprites.md`.
