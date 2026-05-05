# Voice input deferred; if revived, route through the remote agent

Voice → command translation was prototyped against Apple's on-device
Foundation Models and removed in commit 47c23f0 because trivial inputs
("move to code directory") were echoed verbatim and "look for all cron
tasks" produced wrong commands.

The failure mode was prompt-structure / lack of grounding, not raw model
capacity, so swapping in a larger on-device model (e.g. Gemma 3n E4B
bundled in the binary) is unlikely to fix the root cause and would cost
~3 GB of binary size, raise the device floor to A17 Pro, and add App
Review risk.

When the feature is revived, the default path is:

  mic → SFSpeechRecognizer (on-device, Korean OK) → transcript →
  remote agent (Claude Code / Codex session, or relay → Anthropic API)

This keeps audio on-device, ships zero extra weight in the binary, runs
on every iPhone, and produces commands from a model that is materially
better at command synthesis than anything that fits in RAM.

On-device translation only gets reconsidered if "transcript leaves the
device" becomes a hard no. In that case the first attempt should be
Apple Foundation Models held correctly (`@Generable` output struct, real
system instruction, few-shot grounded in the host's `uname` / shell /
installed binaries) — not a bundled LLM.

All user-facing surfaces (in-app privacy policy, relay's public privacy
page, App Store listing, screenshots) must not advertise voice input
or AI translation until the feature ships.
