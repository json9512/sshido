# Agent mode: many chats, group chats with a picker, and host folders

Its group chats (a picker choosing among fixed members) were replaced by
orchestrator-led chats in [0008](0008-orchestrator-led-chats-work-records-desktop.md).

Builds on [0006](0006-agent-mode.md). Agent mode had a single chat with one
orchestrator, and agents saw only the shared `/workspace` volume.

## Decisions

- **Many chats.** Every chat has its own agents and history, and all chats
  share one `/workspace`. An *orchestrated* chat works as in 0006 and gets
  its own orchestrator. `agentctl list` and `agentctl send` only reach
  agents in the caller's chat.
- **The app↔daemon protocol breaks, and history is migrated.** Messages and
  agents carry a `chatId`, and `send` names one. The only consumer is the
  sshido app, so no compatibility path was kept. The app and the daemon
  image are updated together. On first start, the daemon moves existing
  history and agents into a chat titled "Agents".
- **A group chat is chosen by a picker, not by an orchestrator.** Its members
  are fixed when the chat is created. After each message from the person, a
  local "pick from a list" scorer chooses the next speaker, in the style of
  TypeSafe's Jev. It gets the chat and a lettered list of members plus
  "stop", and the answer is read from the letter logprobs of one token. It
  runs on the user's own OpenAI-compatible endpoint (`SSHIDO_PICKER_MODEL`
  on `SSHIDO_LOCAL_URL`), so sshido still never pays for or proxies a model
  (0001, 0005). Without a picker model, group chats are refused.
- **Guards around the picker:**
  - The first pick after the person speaks cannot be "stop", so a message
    always gets a reply.
  - Each chat has a turn limit (default 6, at most 50).
  - A picker failure is posted in the chat.
  - The prompt quotes the person's latest message and names the last
    speaker. On a real transcript this took the "stop" decisions from
    about 0.4 to 0.9 or higher.
- **Host folders are read-only, for every agent.** The user lists absolute
  host paths. Each one is bind-mounted `ro` at `/host/<folder name>`, and
  agents copy what they change into `/workspace`. When the list changes, the
  daemon recreates the agent containers and they keep their sessions (the
  logins and sessions live in named volumes). Each agent is told about the
  change once, on its next turn. SELinux labeling is turned off only for
  containers that have host folders.

## Consequences

- On macOS, Podman's VM shares only `/Users`, `/private` and `/var/folders`,
  so host folders must be under those.
- Changing host folders or the picker restarts the daemon ("Apply
  settings"), and turns that are running are interrupted.
- The picker is uncalibrated: it has been measured on a few real
  transcripts, not across many. The turn limit is the hard bound.

## Open

- Linux hosts with SELinux enforcing are not tested yet.
