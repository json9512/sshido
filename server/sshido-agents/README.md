# sshido-agents

Host side of sshido agent mode ([ADR 0006](../../docs/adr/0006-agent-mode.md)).
One Go binary, three roles:

- `sshido-agents daemon` runs in its own container, owns the agents and the
  chat history, and starts agent containers through the Podman API socket.
- `sshido-agents attach` is what the app runs over SSH
  (`podman exec -i sshido-agents /usr/local/bin/sshido-agents attach`): JSON
  lines in and out.
- `agentctl` (the same binary under another name) is how agents talk to the
  daemon from inside their containers: `spawn`, `send`, `list`, `report`.

## Build the images on the host

Podman must be installed. From this directory:

```bash
podman build -f images/daemon/Containerfile -t localhost/sshido-agents:latest .
podman build -f images/agent/Containerfile  -t localhost/sshido-agent:latest .
```

The agent image carries Claude Code, Codex, Gemini CLI, Grok and `agentctl`.
Then open **Settings → Agent mode** in the app, pick the host, and tap
**Set up host**; the app creates the notify secret and starts the daemon.

## What the daemon container needs

| Mount / setting | Why |
| --- | --- |
| Podman API socket at `/run/podman.sock` (`podman info --format '{{.Host.RemoteSocket.Path}}'`) | start and stop agent containers; only the daemon gets it |
| `--user 0` | container root maps to your user in rootless Podman, which owns the socket |
| volume `sshido-agents-bus` at `/bus` | `bus.sock` and prompt files shared with agents |
| volume `sshido-agents-data` at `/data` | chat and agent database, `app.sock` for `attach` |
| secret `sshido-agents-notify` as `SSHIDO_NOTIFY_URL` (optional) | pushes through the sshido relay |
| `SSHIDO_ORCHESTRATOR`, `SSHIDO_WORKER_HARNESS` | `claude`, `codex`, `gemini`, `grok` or `local` |
| `SSHIDO_ORCHESTRATOR_MODEL`, `SSHIDO_WORKER_MODEL` | model names; required for `local` |
| `SSHIDO_LOCAL_URL` | OpenAI-compatible endpoint with the Responses API, as seen from a container, e.g. `http://host.containers.internal:8083/v1` |

Agents share one workspace volume (`sshido-agents-workspace` at `/workspace`).
Each harness keeps its login in its own volume (`sshido-auth-claude`,
`sshido-auth-codex`, `sshido-auth-gemini`, `sshido-auth-grok`); the app's
**Sign in** buttons open a terminal that runs the harness's own sign-in.

## Try it without the app

```bash
printf '{"op":"hello","since":0}\n{"op":"send","text":"Create hello.txt with one worker"}\n' \
  | podman exec -i sshido-agents /usr/local/bin/sshido-agents attach
```

## Tests

```bash
go test -race ./...
```

The Swift side has an opt-in end-to-end test against a real host; see
`Tests/sshidoCoreTests/AgentBridgeIntegrationTests.swift`.
