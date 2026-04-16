#!/usr/bin/env bash
set -euo pipefail

EVENT="${1:-event}"
TITLE="${2:-Claude Code}"
BODY="${3:-${CLAUDE_HOOK_BODY:-}}"

NOTIFY_URL="${SSHIDO_NOTIFY_URL:-}"
if [[ -z "$NOTIFY_URL" && -f "$HOME/.sshido/notify.url" ]]; then
    NOTIFY_URL="$(tr -d '[:space:]' < "$HOME/.sshido/notify.url")"
fi
if [[ -z "$NOTIFY_URL" ]]; then
    exit 0
fi

priority="normal"
case "$EVENT" in
    AskUserQuestion|Error|Notification) priority="high" ;;
esac

session_ref=""
if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null; then
    session_ref="$(tmux display-message -p '#S' 2>/dev/null || echo '')"
fi
host_ref="$(hostname -s 2>/dev/null || echo '')"

json_encode() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }

payload="$(printf '{"title":%s,"body":%s,"priority":"%s","sessionRef":%s,"hostRef":%s}' \
    "$(printf '%s' "$TITLE"       | json_encode)" \
    "$(printf '%s' "$BODY"        | json_encode)" \
    "$priority" \
    "$(printf '%s' "$session_ref" | json_encode)" \
    "$(printf '%s' "$host_ref"    | json_encode)")"

curl -fsS -m 5 -H 'Content-Type: application/json' -d "$payload" "$NOTIFY_URL" >/dev/null || true
