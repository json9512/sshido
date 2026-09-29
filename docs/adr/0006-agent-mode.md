# Agent mode: a chat over agents that run in Podman on the user's host

Agent mode is an opt-in setting. When it is on, sshido opens a chat instead
of a terminal. A message goes to an orchestration agent. The orchestrator
splits the work across subagents, every agent runs in its own Podman
container on a host the user already reaches over SSH, and progress and
results come back into the chat and as push notifications. The terminal
stays available as a way to look inside a running agent; it is no longer
the main surface in this mode.

## Decisions

- **The orchestrator is new code in this repo** (`server/sshido-agents/`),
  not the user's crew engine and not one harness's built-in subagents.
  Every agent, the orchestrator included, gets its own container.
- **sshido still never pays for or proxies a model** (0001, 0005). Each
  agent runs a harness the user already owns, logged in inside its
  container:
  - cloud subscriptions: Claude Code, Codex CLI, Grok CLI, Gemini CLI;
  - local models: Codex CLI with a custom OpenAI-compatible provider
    pointed at an endpoint on the host (llama-swap, Ollama, LM Studio).

  Both kinds are supported from the first version, chosen per agent.
- **First slice is thin but end to end:** the settings toggle, the chat
  with voice input (0005's on-device dictation feeds the chat composer; the
  user still presses send), one orchestrator that spawns subagents, and
  progress/done messages in the chat and as pushes. Group chats between
  agents, browser use, computer use and the container desktop view
  (VNC through the existing SSH port forwarding) come later.

## Where things run

```
iPhone (sshido)                          user's host (Podman; a VM on macOS)
  chat + voice ── SSH exec channel ──►  podman exec -i sshido-agents attach
                                          │ JSON lines over stdio
                                          ▼
                                        sshido-agents  (orchestrator daemon,
                                          │             own container)
                        Podman API socket │  bus socket on a shared volume
                                          ▼
                              agent containers: orchestrator agent,
                              subagents (harness CLI + agentctl)
  push ◄── relay (0002 SSH-only transport untouched; push was never SSH)
```

- **The daemon runs in a container, not as a host process.** On macOS
  every container lives inside Podman's Linux VM, so a host process could
  not share sockets or volumes with them. In a container it can, and the
  same image works on macOS and Linux hosts.
- **Only the daemon gets the Podman API socket.** It starts, stops and
  removes agent containers through it. Agents never get it: the socket
  controls every container of that user.
- **Agents reach the daemon through `agentctl`,** a small client in the
  agent image, over a Unix socket on a shared volume. Each agent gets its
  own token so it can only report as itself.
- **Each harness run is headless** (`claude -p`, `codex exec`,
  `grok --prompt-file`, `gemini -p`) and resumes its session for the next
  turn, so a conversation survives the phone disconnecting.
- **Harness logins live in named volumes,** one per harness, mounted into
  that harness's agents. The user logs in once through the container
  terminal, which is also the "peek" view.

## Why not an installed binary (0004)

0004 rejected pushing an agent binary onto hosts: per-OS and per-arch
binaries, App Review surface, and software written into the user's home
without asking. A container image avoids all three. Podman only runs Linux
images, so arm64 and amd64 cover every host, including Macs. Nothing lands
in the home directory except what Podman keeps, and the user opts in by
turning agent mode on and installing Podman.

## Open

- Whether each vendor's terms allow a subscription login to run headless
  agents in parallel. Check before shipping, and say so in the setup screen.
- Where the images are published (a public registry is an outward-facing
  step and needs its own go-ahead).
- Recovery after the Podman VM restarts: sshido restarts an exited
  `sshido-agents` pod on connect (seen in the Mac test: the restart policy
  does not fire because `podman-restart.service` is off in the VM).
