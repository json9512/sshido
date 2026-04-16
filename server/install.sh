#!/usr/bin/env bash
set -euo pipefail

# sshido server-side installer.
#
# Usage:
#   bash install.sh                              # interactive
#   SSHIDO_NOTIFY_URL=https://push.sshido.com/n/<id> bash install.sh
#
# Installs:
#   - tmux, mosh (if missing)
#   - ~/.sshido/notify.url               (capability URL the iOS app issued)
#   - ~/.claude/hooks/notify.sh          (Claude Code hook)
#   - merges into ~/.claude/settings.json
#   - ~/.local/bin/sshido-notify         (generic CLI for any agent/script)

PREFIX="${HOME}/.sshido"
CLAUDE_DIR="${HOME}/.claude"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

say()  { printf "\033[1;34m▶\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m!\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m✗\033[0m %s\n" "$*" >&2; exit 1; }

install_pkg() {
    if [[ "$(uname)" == "Darwin" ]] && command -v brew >/dev/null; then
        brew install "$@"
    elif command -v apt-get >/dev/null; then sudo apt-get update && sudo apt-get install -y "$@"
    elif command -v dnf >/dev/null; then sudo dnf install -y "$@"
    elif command -v pacman >/dev/null; then sudo pacman -Sy --noconfirm "$@"
    elif command -v brew >/dev/null; then brew install "$@"
    else die "no supported package manager"
    fi
}

mkdir -p "$PREFIX" "$CLAUDE_DIR/hooks" "$HOME/.local/bin"

say "Ensuring tmux + mosh are installed…"
command -v tmux >/dev/null || install_pkg tmux
command -v mosh-server >/dev/null || install_pkg mosh

NOTIFY_URL="${SSHIDO_NOTIFY_URL:-}"
if [[ -z "$NOTIFY_URL" ]]; then
    if [[ -f "$PREFIX/notify.url" ]]; then
        NOTIFY_URL="$(tr -d '[:space:]' < "$PREFIX/notify.url")"
        say "Using existing $PREFIX/notify.url"
    else
        echo
        echo "Open sshido on your iPhone → Settings → enter your push server URL → Save & subscribe."
        echo "Then copy or scan the 'Notify URL' shown there."
        echo
        read -r -p "Paste notify URL (leave empty to skip push setup): " NOTIFY_URL || true
    fi
fi

if [[ -n "$NOTIFY_URL" ]]; then
    printf '%s\n' "$NOTIFY_URL" > "$PREFIX/notify.url"
    chmod 600 "$PREFIX/notify.url"
    say "Notify URL stored at $PREFIX/notify.url"
else
    warn "No notify URL — push notifications are disabled. Re-run with SSHIDO_NOTIFY_URL=… to enable."
fi

say "Installing Claude Code notify hook…"
cp "$SCRIPT_DIR/hooks/notify.sh" "$CLAUDE_DIR/hooks/notify.sh"
chmod +x "$CLAUDE_DIR/hooks/notify.sh"

if [[ ! -f "$CLAUDE_DIR/settings.json" ]]; then
    cp "$SCRIPT_DIR/claude-settings.json" "$CLAUDE_DIR/settings.json"
    say "Wrote $CLAUDE_DIR/settings.json"
else
    say "$CLAUDE_DIR/settings.json exists — merge hooks manually from claude-settings.json if needed"
fi

say "Installing sshido-notify CLI to ~/.local/bin/sshido-notify…"
cp "$SCRIPT_DIR/sshido-notify" "$HOME/.local/bin/sshido-notify"
chmod +x "$HOME/.local/bin/sshido-notify"

say "Skipping tmux auto-attach in shell rc — sshido manages its own per-session tmux."
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f "$rc" ]] || continue
    if grep -q 'sshido: auto-attach tmux' "$rc"; then
        say "Removing existing sshido auto-attach from $rc"
        awk 'BEGIN{skip=0} /# sshido: auto-attach tmux on ssh login/{skip=1; next} skip && /^fi$/{skip=0; next} !skip' "$rc" > "$rc.sshido-tmp" && mv "$rc.sshido-tmp" "$rc"
    fi
done

say "Configuring ~/.tmux.conf for sshido…"
tmux_marker="# sshido-managed"
tmux_block="$tmux_marker
set -g aggressive-resize on
$tmux_marker"
if [[ -f "$HOME/.tmux.conf" ]] && grep -q "$tmux_marker" "$HOME/.tmux.conf"; then
    :
else
    printf "\n%s\n" "$tmux_block" >> "$HOME/.tmux.conf"
fi

echo
say "Done."
if [[ -n "$NOTIFY_URL" ]]; then
    echo "Test push: ~/.local/bin/sshido-notify 'Hello' 'It works' (add ~/.local/bin to PATH if needed)"
fi
