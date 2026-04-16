# sshido-relay

Tiny Go binary that forwards HTTP POSTs from your dev server (Claude Code hooks,
Codex, aider, etc.) to APNs so your phone gets a push when the agent needs your
attention.

```
┌────────────────┐         ┌──────────────┐         ┌──────────────┐         ┌────────┐
│ Claude Code    │ ──curl─►│ sshido-relay │ ──HTTP2─►│    APNs      │ ─push──►│ iPhone │
│ ~/.claude/     │         │  (this bin)  │         │              │         │        │
│ hooks/notify   │         └──────────────┘         └──────────────┘         └────────┘
└────────────────┘
```

## Deployment paths

Two supported modes, picked via `-storage` / `STORAGE` env var:

| Mode | Best for | Store | Hosting |
|---|---|---|---|
| `sqlite` (default) | Local self-host on your own dev box / home server | Local SQLite file | systemd / launchd / `docker run` |
| `firestore` | Public hosted relay for App Store users | GCP Firestore | Cloud Run (serverless, free tier) |

## Quick start

```sh
git clone https://github.com/json9512/sshido.git
cd sshido/server/sshido-relay
go build -o sshido-relay .

./sshido-relay \
  -addr 0.0.0.0:8787 \
  -public-url http://your-host:8787 \
  -bundle-id com.sshido.app \
  -key ~/pass/apns/AuthKey_XXXXXXXXXX.p8 \
  -key-id XXXXXXXXXX \
  -team-id XXXXXXXXXX
```

On a real server use a systemd unit (Linux) or launchd (macOS). Reference
example in `../install.sh`.

## APIs

- `POST /subscribe` — body `{"deviceToken":"..."}` → returns `{"id":"...","notifyURL":"..."}`.
  Called by the sshido iPhone app after APNs registration.
- `POST /n/<id>` — body `{"title":"...", "body":"...", "priority":"normal|high", "sessionRef":"...", "hostRef":"..."}`.
  Called by your Claude Code hook (or any CLI wrapper) to push an alert.

## Required flags

| Flag            | What | How to get it |
|-----------------|------|---------------|
| `-bundle-id`    | App bundle id  | `com.sshido.app` (don't change unless you've rebuilt the app with your own id) |
| `-key`          | APNs `.p8` file path | Apple Developer → Certificates → Keys → `+` → "Apple Push Notifications service (APNs)" → download the `.p8` (one-time download) |
| `-key-id`       | 10-char key id | Shown next to the `.p8` in the Apple Developer portal |
| `-team-id`      | 10-char team id | Apple Developer → Membership |
| `-public-url`   | Base URL the phone posts to | Your server's reachable URL (Tailscale hostname, Cloudflare tunnel, LAN IP) |

Optional:
- `-production` — use APNs production environment (required for TestFlight /
  App Store builds). Omit for dev builds signed with `aps-environment=development`.
- `-db` — SQLite path (default `./sshido-relay.db`)

## Claude Code hook example

Install the hook in `~/.claude/hooks/notify.sh`:

```sh
#!/usr/bin/env bash
URL="$SSHIDO_NOTIFY_URL"   # the URL the app gave you after subscribe
case "$CLAUDE_HOOK_EVENT" in
  AskUserQuestion) TITLE="Claude needs input"; PRIO="high" ;;
  Stop)            TITLE="Task complete";      PRIO="normal" ;;
  Error)           TITLE="Error";              PRIO="high" ;;
  *)               TITLE="Claude";             PRIO="normal" ;;
esac
curl -fsS -X POST "$URL" -H 'content-type: application/json' \
  -d "$(jq -n --arg t "$TITLE" --arg b "$CLAUDE_HOOK_MESSAGE" --arg p "$PRIO" \
       '{title:$t, body:$b, priority:$p}')"
```

Then merge the relevant entries into `~/.claude/settings.json` (see the
example in `../claude-settings.json`).

## Security

- The relay listens on whatever `-addr` you give it. Default `127.0.0.1:8787`
  keeps it local; bind to `0.0.0.0` only if you understand the exposure.
- Each subscription gets a random 32-byte token in its URL (effectively a
  bearer secret). If you rotate devices, re-subscribe to invalidate the old
  URL.
- The `.p8` never leaves your server. Only the sshido app's device token
  is stored in the local SQLite.

## Cloud Run (hosted relay)

For running the relay as a free-tier hosted service on GCP (Firestore-backed):

```sh
# one-time
gcloud auth login
gcloud config set project YOUR_GCP_PROJECT
gcloud services enable run.googleapis.com firestore.googleapis.com \
  secretmanager.googleapis.com artifactregistry.googleapis.com
gcloud firestore databases create --location=us-central1
gcloud artifacts repositories create sshido \
  --repository-format=docker --location=us-central1
gcloud secrets create sshido-apns-key --data-file=$HOME/AuthKey_XXXXXXXXXX.p8

# deploy
cd server/sshido-relay
GCP_PROJECT=YOUR_GCP_PROJECT \
  APNS_KEY_ID=XXXXXXXXXX \
  APNS_TEAM_ID=XXXXXXXXXX \
  APNS_PRODUCTION=true \
  ./deploy-cloud-run.sh
```

Redeploy with the same script after code changes. Cloud Run auto-scales to
zero when idle — no cost unless requests arrive.

## Building for Linux (if your dev box is remote)

```
GOOS=linux GOARCH=amd64 go build -o sshido-relay .     # Intel
GOOS=linux GOARCH=arm64 go build -o sshido-relay .     # ARM (Raspberry Pi etc.)
```

Ship the single binary; no runtime deps (modernc.org/sqlite is pure-Go).
