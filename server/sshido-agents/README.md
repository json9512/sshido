# sshido-agents

Host side of sshido agent mode ([ADR 0006](../../docs/adr/0006-agent-mode.md),
[ADR 0008](../../docs/adr/0008-orchestrator-led-chats-work-records-desktop.md)).
One Go binary, three roles:

- `sshido-agents daemon` runs in its own container, owns the agents and the
  chat history, and starts agent containers through the Podman API socket.
- `sshido-agents attach` is what the app runs over SSH
  (`podman exec -i sshido-agents /usr/local/bin/sshido-agents attach`): JSON
  lines in and out.
- `agentctl` (the same binary under another name) is how agents talk to the
  daemon from inside their containers. Every agent keeps its work record with
  `goal`, `log`, `verify`, `status` and `record`, and talks to the person with
  `report` and `attach`. Only the orchestrator runs `spawn`, `send`, `verdict`,
  `stop` and `list`.

## Build the images on the host

Podman must be installed. From this directory:

```bash
podman build -f images/daemon/Containerfile -t localhost/sshido-agents:latest .
podman build -f images/agent/Containerfile  -t localhost/sshido-agent:latest .
```

The agent image carries Claude Code, Codex, Gemini CLI, Grok, `agentctl`, a
browser (`agent-browser`) and a virtual desktop driven by the `desktop` command
(Xvfb, Openbox, x11vnc, noVNC). The `agent-browser` in the image is a wrapper:
the browser opens on the desktop, so the person can watch it.
Then open **Settings → Agent mode** in the app, pick the host, and tap
**Set up host**; the app creates the notify secret and starts the daemon.

## What the daemon container needs

| Mount / setting | Why |
| --- | --- |
| Podman API socket at `/run/podman.sock` (`podman info --format '{{.Host.RemoteSocket.Path}}'`) | start and stop agent containers; only the daemon gets it |
| `--user 0` | container root maps to your user in rootless Podman, which owns the socket |
| volume `sshido-agents-bus` at `/bus` | `bus.sock` and prompt files shared with agents |
| volume `sshido-agents-data` at `/data` | chat and agent database, `app.sock` for `attach` |
| volume `sshido-agents-workspace` at `/workspace` (read-write) | the daemon writes each agent's work record under `.sshido/records/<agent id>/` and serves attachments |
| secret `sshido-agents-notify` as `SSHIDO_NOTIFY_URL` (optional) | pushes through the sshido relay |
| `SSHIDO_ORCHESTRATOR` | `claude`, `codex`, `gemini`, `grok` or `local` |
| `SSHIDO_ORCHESTRATOR_MODEL` | model name; required for `local` |
| `SSHIDO_WORKER_CHOICE` | `fixed` (every subagent uses `SSHIDO_WORKER_HARNESS` and `SSHIDO_WORKER_MODEL`) or `orchestrator` (the orchestrator picks from `SSHIDO_WORKER_HARNESSES`) |
| `SSHIDO_WORKER_HARNESS`, `SSHIDO_WORKER_MODEL` | the fixed subagent harness and model; the model is required for `local` |
| `SSHIDO_WORKER_HARNESSES`, `SSHIDO_WORKER_LOCAL_MODEL` | comma-separated harnesses the orchestrator may pick, and the model for `local` among them |
| `SSHIDO_LOCAL_URL` | OpenAI-compatible endpoint with the Responses API, as seen from a container, e.g. `http://host.containers.internal:8083/v1` |
| `SSHIDO_HOST_DIRS` | JSON array of absolute host paths, e.g. `["/Users/me/code"]`. Every agent gets each one read-only at `/host/<folder name>`. On macOS the Podman VM only sees `/Users`, `/private` and `/var/folders` |
| `SSHIDO_HOST_CLAUDE_HOME` | the host user's home directory, e.g. `/home/me`, to give Claude agents the host's Claude Code config (see below). The app sets it only on Linux hosts that have both `~/.claude` and `~/.claude.json`; empty turns it off |

Every chat has its own orchestrator, subagents and history. The orchestrator
plans from the person's request, starts subagents when the work calls for them
(at most 12 running per chat), checks their verification and gives each a pass
or fail verdict. Every turn of every agent starts with its own work record.

Each agent container publishes its desktop viewer (noVNC, container port 6080)
on a random port of the host's `127.0.0.1`; `podman port <container> 6080/tcp`
shows it and `desktop serve` inside the container prints its password.

When `SSHIDO_HOST_DIRS` changes, or after upgrading to an image with a new
container setup, restart the daemon: existing agents are recreated and keep
their sessions.

Agents share one workspace volume (`sshido-agents-workspace` at `/workspace`).
Each harness keeps its login in its own volume (`sshido-auth-claude`,
`sshido-auth-codex`, `sshido-auth-gemini`, `sshido-auth-grok`); the app's
**Sign in** buttons open a terminal that runs the harness's own sign-in.
On a Linux host with its own Claude Code config, Claude agents use that
config instead of `sshido-auth-claude`.

## Host Claude Code config: MCP servers and plugins (Linux hosts)

On a Linux host, Claude agents (orchestrator and subagents) run on the host
user's own Claude Code config. Each Claude agent mounts, read-write:

| Host path | In the agent |
| --- | --- |
| `~/.claude` | the same absolute path, as `CLAUDE_CONFIG_DIR` |
| `~/.claude.json` | `~/.claude/.claude.json`, where Claude Code reads it when `CLAUDE_CONFIG_DIR` is set |

So agents get the host's claude.ai sign-in, claude.ai connectors, plugins,
user-scoped MCP servers and the MCP sign-ins in `~/.claude/.credentials.json`,
and token refreshes land in the same file the host uses. Plugins need the same
absolute path because `~/.claude/plugins/installed_plugins.json` records them
that way. Agents run with `--dangerously-skip-permissions`, so they use every
connector and MCP server in that config without asking.

What to know before you rely on it:

- **macOS hosts get none of this.** Claude Code on macOS keeps its live
  sign-ins in the Keychain, which containers cannot read; the
  `~/.claude/.credentials.json` there can be stale, and refreshing from it can
  sign the Mac out of claude.ai or a connector. On a Mac, Claude agents keep
  their own sign-in in `sshido-auth-claude` and get no host plugins or MCP
  servers.
- **Only Claude agents.** Codex, Gemini, Grok and local-model agents keep their
  own login volumes and get no MCP servers from the host.
- **Every agent maps to your user.** With the config shared, every agent
  container on the host runs with `--userns keep-id:uid=1001,gid=1001`, so the
  agent user is your host user and files agents write in `~/.claude` stay
  yours. On the first start in this mode, each agent takes ownership of
  `/workspace` and its login volume (`find … ! -user agent -exec chown …`).
- **`127.0.0.1` is the container, not the host.** An MCP server the host
  reaches at `http://127.0.0.1:<port>` fails inside agents. Point it at
  `host.containers.internal`, or listen on an address the container network
  reaches.
- **Environment variables do not travel.** A plugin that reads a token from
  the host shell (for example the GitHub plugin's
  `GITHUB_PERSONAL_ACCESS_TOKEN`) fails inside agents. Put the variable under
  `"env"` in `~/.claude/settings.json` if agents should have it.
- **Hooks run inside agents too.** Hooks in `~/.claude/settings.json` that call
  host-only paths fail in agents; the turn still runs.
- **A placeholder file appears.** Podman creates an empty `~/.claude/.claude.json`
  on the host as the mount point for `~/.claude.json`. Host Claude Code ignores
  it unless you set `CLAUDE_CONFIG_DIR` yourself.
- **Sign in on the host.** The app's Claude **Sign in** button runs
  `claude auth login --claudeai` against the shared config on Linux hosts,
  which signs in the host's Claude Code too.

To turn it on for an existing host, update the images, update the app, then
tap the box button under **Settings › Agents › Host** again: the daemon
restarts with `SSHIDO_HOST_CLAUDE_HOME` set and recreates existing agents with
the new mounts. The app has no switch for it; a daemon started by hand with
`SSHIDO_HOST_CLAUDE_HOME` empty runs without it.

Website sign-ins live in the volume `sshido-browser-logins` at
`/home/agent/.logins`. An agent that hits a login page runs
`agentctl report --sign-in "<site and why>"`; the app shows a card that opens
the agent's desktop, and when the person taps Done the daemon runs
`browser-logins save` in that container (merging its cookies and storage into
`browser.json`) and tells the agent to continue. Every agent's browser loads
`browser.json` when it starts. Remove agents keeps this volume.

## Try it without the app

```bash
printf '{"op":"createChat","title":"Try it"}\n{"op":"hello","since":0}\n' \
  | podman exec -i sshido-agents /usr/local/bin/sshido-agents attach
# take the chat id from the "chat" event, then:
printf '{"op":"send","chatId":"<chat id>","text":"Create hello.txt with one subagent"}\n' \
  | podman exec -i sshido-agents /usr/local/bin/sshido-agents attach
```

## Tests

```bash
go test -race ./...
```

Opt-in tests run against a real Podman (host folders, and the desktop on a
loopback port):

```bash
SSHIDO_TEST_PODMAN_SOCKET=<Podman API socket> SSHIDO_TEST_AGENT_IMAGE=localhost/sshido-agent:latest go test -run Podman ./...
```

The Swift side has an opt-in end-to-end test against a real host; see
`Tests/sshidoCoreTests/AgentBridgeIntegrationTests.swift`.
