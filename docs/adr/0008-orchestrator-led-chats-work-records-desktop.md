# Agent mode: every chat is led by an orchestrator, agents keep work records, containers get a desktop

Builds on [0006](0006-agent-mode.md) and replaces the group chats of
[0007](0007-agent-chats-picker-host-folders.md). Shaped after personal agent
systems that plan, fan out to subagents and report back at milestones (Meta
Muse, xAI Grok Bot, OpenAI dots).

## Decisions

- **The person talks to one orchestrator per chat.** The orchestrator works
  out what the person needs from first principles, plans, and keeps going
  until those needs are met. It does small work itself and spawns subagents
  when work takes time or can run in parallel. Only the orchestrator spawns;
  subagents report back to it. A chat holds at most 12 subagents that are not
  stopped, and the orchestrator can stop the ones it no longer needs.
- **Picker group chats are removed.** The member list, the picker, the picker
  model setting and the turn limit are gone. On first start, the daemon turns
  existing group chats into orchestrator chats and stops their member agents;
  their history stays. The app↔daemon protocol breaks again (chats lose
  `kind` and `turnCap`); the app and the daemon image ship together.
- **Every agent keeps a work record.** It has a goal, a status (`in_progress`,
  `blocked`, `done`), a verification (what was checked and the evidence), a
  verdict (`pass` or `fail` with a reason) and a track record (a log of what
  was done). The daemon is the only writer. It keeps the fields in its
  database and writes them as files under
  `/workspace/.sshido/records/<agent id>/`; agents change them only through
  `agentctl`. Every turn starts with the agent's own record, so resumed work
  always begins from it, even after a lost harness session.
- **The orchestrator gives the verdicts.** A subagent sets its goal, status
  and verification. When it finishes a turn, the orchestrator gets its record
  and report, checks the evidence and writes a pass or fail verdict. On a
  fail it sends the subagent more work or spawns another. The orchestrator
  also judges its own work against the person's request before it answers.
- **Model choice is set by the person.** The orchestrator runs on a frontier
  harness (Claude Code, Codex, Gemini CLI, Grok) or a local model. Subagents
  run on a fixed frontier harness, a fixed local model, or "orchestrator
  decides": the person ticks which harnesses are allowed and the orchestrator
  picks one per subagent.
- **Every agent has a computer.** Besides the shell, the internet and the
  headless browser, each container has a virtual desktop (Xvfb, a window
  manager, x11vnc and noVNC). It starts on first use. Agents drive it with the
  `desktop` command: screenshot, click, type, key, scroll, run a program. The
  person watches or takes over from the phone: the container publishes noVNC
  on a random port on the host's 127.0.0.1, and the app reaches it through an
  SSH port forward and opens it in the in-app browser, with a per-container
  password.

## Consequences

- Existing agent containers are recreated once on daemon start so they get
  the published desktop port; they keep their sessions (logins and sessions
  live in named volumes).
- The daemon now mounts the shared workspace read-write, to write the record
  files. Agents cannot change those files: they are owned by the daemon's
  user and agents run as a different one.
- A desktop costs memory while it runs. Podman on macOS gives its VM 2 GiB
  by default; many agents on the desktop at once need more.
- Local models without vision cannot use desktop screenshots. They can still
  use the shell and the browser's text snapshot.

## Open

- The loop "until the needs are met" is bounded by the 12-subagent limit and
  the per-turn timeout, not by a budget. A spending limit per chat may be
  needed once frontier subagents run for long.
