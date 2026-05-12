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

On a real server use a systemd unit (Linux) or launchd (macOS).

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

End users don't do this by hand — the iOS app's Settings screen ships a
one-shot agent-setup prompt that makes Claude Code write the hook and
settings itself (see the root README). The manual equivalent is below,
for anyone who wants to understand what it produces or set it up without
the app.

Only three Claude Code events are valid for our case: `Notification`,
`Stop`, `StopFailure`. `AskUserQuestion` and `Error` are not Claude Code
events — they're silently ignored with a warning.

The hook gates on `$SSHIDO_SESSION`, an env var sshido exports in every
shell it opens (plain SSH and inside its tmux sessions). Without the
gate, Claude Code running locally on your dev box would also push.

Install the hook in `~/.claude/hooks/notify.sh` (`chmod +x`):

```sh
#!/usr/bin/env bash
set -eu

EVENT="${1:-}"
TITLE="${2:-Claude}"
BODY="${3:-}"

URL="${SSHIDO_NOTIFY_URL:-}"
if [ -z "$URL" ] && [ -r "$HOME/.sshido/notify.url" ]; then
  read -r URL < "$HOME/.sshido/notify.url"
fi
if [ -z "$URL" ]; then
  exit 0
fi

case "$EVENT" in
  Notification|StopFailure) PRIO="high" ;;
  *)                        PRIO="normal" ;;
esac

SESSION_REF=""
if [ -n "${TMUX:-}" ]; then
  SESSION_REF=$(tmux display-message -p '#S' 2>/dev/null || true)
fi
HOST_REF=$(hostname -s)

curl -fsS -m 5 -X POST "$URL" -H 'content-type: application/json' \
  -d "$(jq -n \
    --arg t "$TITLE" --arg b "$BODY" --arg p "$PRIO" \
    --arg s "$SESSION_REF" --arg h "$HOST_REF" \
    '{title:$t, body:$b, priority:$p, sessionRef:$s, hostRef:$h}')"
```

Optionally write the Notify URL to `~/.sshido/notify.url` (chmod 600) so
the hook works even when `$SSHIDO_NOTIFY_URL` isn't set.

Then merge into `~/.claude/settings.json` (preserve any existing keys):

```json
{
  "hooks": {
    "Notification": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "[ -z \"$SSHIDO_SESSION\" ] || ~/.claude/hooks/notify.sh Notification \"Claude needs input\" \"Check your session\"" } ] }
    ],
    "Stop": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "[ -z \"$SSHIDO_SESSION\" ] || ~/.claude/hooks/notify.sh Stop \"Task complete\" \"Claude finished\"" } ] }
    ],
    "StopFailure": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "[ -z \"$SSHIDO_SESSION\" ] || ~/.claude/hooks/notify.sh StopFailure \"Claude error\" \"Claude stopped with an error\"" } ] }
    ]
  }
}
```

Verify end-to-end:

```sh
curl -fsS -X POST -H 'content-type: application/json' \
  -d '{"title":"test","body":"hello","priority":"high"}' \
  "$SSHIDO_NOTIFY_URL"
# expect HTTP 204
```

## Security

- The relay listens on whatever `-addr` you give it. Default `127.0.0.1:8787`
  keeps it local; bind to `0.0.0.0` only if you understand the exposure.
- Each subscription gets a 32-character random token (128 bits of entropy)
  in its URL (effectively a bearer secret). If you rotate devices,
  re-subscribe to invalidate the old URL.
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
