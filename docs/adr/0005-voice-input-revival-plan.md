# Voice input revival: transcribe-and-type, no local translation

Supersedes the "deferred" stance of [0001](0001-voice-input-deferred.md) with a
concrete plan. The core decision from 0001 stands: **sshido does not translate
speech into commands locally.** It transcribes on-device and types the raw
transcript into the active pane. Any natural-language → command translation is
done by the AI agent already running in that pane (Claude Code, Codex, aider),
which has the grounding sshido lacks.

## Why not local translation (recap of 0001)

On-device translation was removed in 47c23f0 because trivial inputs were echoed
verbatim and non-trivial ones produced wrong commands — a grounding problem, not
a model-size problem. A bundled LLM (~3 GB, A17-Pro floor, App Review risk) does
not fix grounding. The relay cannot proxy a paid LLM API at public-app scale.
So the only translator we trust is the user's own agent in the pane.

This directly answers the "go to my code files" → `cd ~/code` example: that
translation happens because **Claude Code** hears "go to my code files" on its
stdin and, knowing the host's filesystem, emits `cd ~/code`. sshido's job is to
get the words onto that stdin accurately.

## Scope decision: routing (command vs. LLM prompt)

The request asked sshido to "decide whether it is a terminal command or raw
input for LLMs." That routing decision **is** the local-translation problem 0001
rejected: deciding correctly requires knowing the shell, the installed binaries,
and whether an agent is listening — i.e. grounding. So routing is **explicitly
out of scope**. The active pane already routes: if an agent is running, natural
language is interpreted; if a bare shell is running, the user dictates literal
commands. sshido stays a dumb, accurate pipe.

## Architecture

```
mic → AVAudioEngine → SFSpeechRecognizer (on-device) → transcript
    → inserted into the active pane's stdin via channel.send(...)
    → user reviews, then presses ⏎ (we do NOT auto-submit)
```

## Implementation plan

1. **Permissions** (`Sources/AppUI/Info.plist`)
   - `NSMicrophoneUsageDescription` — "Dictate into your terminal session."
   - `NSSpeechRecognitionUsageDescription` — "Transcribe your speech on-device
     so you can talk to your agent."
   - Request at first mic tap via `SFSpeechRecognizer.requestAuthorization` and
     `AVAudioApplication.requestRecordPermission`.

2. **Recognizer wrapper** (new `Sources/UI/Voice/SpeechDictator.swift`, `@MainActor`)
   - `SFSpeechRecognizer(locale:)` using the user's preferred locale (Korean is
     supported on-device per 0001). Fall back to `Locale.current`.
   - Set `recognitionRequest.requiresOnDeviceRecognition = true` — hard
     requirement; no audio leaves the device. If
     `recognizer.supportsOnDeviceRecognition == false` for the locale, the
     feature is unavailable (surface a one-line reason, never silently send
     audio to Apple's servers).
   - `AVAudioEngine` tap → append buffers → publish `partialTranscript` and a
     final transcript. Push-to-talk: recognize while held/toggled, stop on
     release.

3. **UI: mic button in the AgentBar** (`Sources/UI/AgentBar.swift`)
   - Add a mic button next to the existing keyboard toggle (the leading button
     at `AgentBar.swift:63`). States: idle (`mic`), listening
     (`mic.fill` + level animation), unavailable (disabled + reason on tap).
   - While listening, show the live partial transcript as an overlay strip so
     the user sees what will be typed.
   - On stop: `channel.send(Array(finalTranscript.utf8))` — the same sink the
     hotkey buttons use (`AgentBar.send(bytes:)` at `:175`). Do **not** append
     `\r`; leave submission to the user (they may edit, or hit the new ⌃J / ⏎).

4. **Audio session** — activate `.record`/`.playAndRecord` only while listening,
   deactivate after, and restore on interruption (calls, Siri). Must not fight
   the terminal's keyboard or leave the session hot.

5. **Deactivation guarantees** — stop the engine and release the audio session
   on: session teardown, backgrounding (`scenePhase`), and view disappear.
   Tie into `SessionView`'s existing lifecycle.

## Explicitly out of scope (do not build)

- Any on-device or relay-hosted LLM that turns speech into commands.
- Any heuristic that guesses "command vs. prompt" before typing.
- Auto-submitting the transcript (no implicit `\r`).
- Advertising voice/AI-translation on any user-facing surface until it ships
  (privacy policy, relay privacy page, App Store listing, screenshots) — the
  0001 constraint still holds.

## Open question for the product owner

0001 said the feature is "unavailable" without an agent session. With
transcribe-and-type it technically works into any pane (you'd dictate literal
commands into a bare shell). Decide: gate the mic on "an agent looks active," or
allow dictation into any pane and let the user own the outcome. Recommendation:
**allow into any pane** — it's a dumb pipe; gating adds grounding logic we just
said we won't build.
