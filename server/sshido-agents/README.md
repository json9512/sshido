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
| `SSHIDO_PICKER_MODEL` | instruct (non-thinking) model on `SSHIDO_LOCAL_URL` that picks who speaks next in group chats; the endpoint must return logprobs from `/chat/completions`. Without it, group chats are refused |
| `SSHIDO_HOST_DIRS` | JSON array of absolute host paths, e.g. `["/Users/me/code"]`. Every agent gets each one read-only at `/host/<folder name>`. On macOS the Podman VM only sees `/Users`, `/private` and `/var/folders` |

Every chat has its own agents and history. An orchestrated chat has an
orchestrator that starts workers. A group chat has fixed members; after each
message from the person, the picker model chooses which member speaks next,
one at a time, until it hands the chat back or the chat's turn limit is hit.

When `SSHIDO_HOST_DIRS` changes, restart the daemon: existing agents are
recreated with the new folders and keep their sessions.

Agents share one workspace volume (`sshido-agents-workspace` at `/workspace`).
Each harness keeps its login in its own volume (`sshido-auth-claude`,
`sshido-auth-codex`, `sshido-auth-gemini`, `sshido-auth-grok`); the app's
**Sign in** buttons open a terminal that runs the harness's own sign-in.

## Try it without the app

```bash
printf '{"op":"createChat","title":"Try it","kind":"orchestrated"}\n{"op":"hello","since":0}\n' \
  | podman exec -i sshido-agents /usr/local/bin/sshido-agents attach
# take the chat id from the "chat" event, then:
printf '{"op":"send","chatId":"<chat id>","text":"Create hello.txt with one worker"}\n' \
  | podman exec -i sshido-agents /usr/local/bin/sshido-agents attach
```

## Tests

```bash
go test -race ./...
```

Two opt-in tests run against real services:

```bash
SSHIDO_TEST_PODMAN_SOCKET=<Podman API socket> SSHIDO_TEST_AGENT_IMAGE=localhost/sshido-agent:latest go test -run Podman ./...
SSHIDO_TEST_PICKER_URL=http://127.0.0.1:8083/v1 SSHIDO_TEST_PICKER_MODEL=qwen3.6:35b-instruct go test -run LivePicker ./...
```

The Swift side has an opt-in end-to-end test against a real host; see
`Tests/sshidoCoreTests/AgentBridgeIntegrationTests.swift`.
