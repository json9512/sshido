# Voice input deferred; if revived, use the user's own remote agent

Voice → command translation was prototyped against Apple's on-device
Foundation Models and removed in commit 47c23f0 because trivial inputs
("move to code directory") were echoed verbatim and "look for all cron
tasks" produced wrong commands.

The failure mode was prompt-structure / lack of grounding, not raw model
capacity, so swapping in a larger on-device model (e.g. Gemma 3n E4B
bundled in the binary) is unlikely to fix the root cause and would cost
~3 GB of binary size, raise the device floor to A17 Pro, and add App
Review risk.

The hosted relay (`push.sshido.com`) cannot proxy to a paid LLM API on
behalf of users — the operator (a single dev) cannot absorb Anthropic /
OpenAI token costs at any scale that would matter for a public iOS app.
That rules out a "relay → API" fallback.

When the feature is revived, the only viable path is:

  mic → SFSpeechRecognizer (on-device, Korean OK) → transcript →
  the user's *own* AI agent already running in their tmux pane
  (Claude Code, Codex, aider) — sshido just types the transcript into
  the active agent's stdin

This requires an active agent session on the remote host. If there
isn't one, the feature is unavailable; sshido does not silently fall
back to a paid API call. That tradeoff is acceptable because the entire
product is built around driving a remote agent — voice without an agent
session is out of scope.

Apple Foundation Models, held correctly (`@Generable` output struct,
real system instruction, few-shot grounded in the host's `uname` /
shell / installed binaries), remains the fallback to attempt before
declaring on-device inadequate. A bundled LLM is not on the table.

All user-facing surfaces (in-app privacy policy, relay's public privacy
page, App Store listing, screenshots) must not advertise voice input
or AI translation until the feature ships.
