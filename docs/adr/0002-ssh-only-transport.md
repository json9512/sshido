# SSH-only transport; mosh deferred

sshido uses SSH (via Citadel) as its only transport. mosh is not
supported despite earlier docs claiming "SSH/Mosh transport" — those
were aspirational and never implemented.

mosh on iOS requires either porting mosh's C++ client (UDP + AES-OCB
SSP roaming protocol) or reimplementing SSP in Swift. Both Blink Shell
and ShellFish have done the work; it took meaningful engineering
effort. sshido cannot justify that cost while the product is single-
maintainer and the SSH path covers the dominant use case (a phone
parked next to or inside a Tailscale-connected dev box, where roaming
is rare and tmux already handles "session survives reconnect").

The `Host.useMosh: Bool` field was removed (commit that introduces this
ADR). It was persisted but never read — `decodeIfPresent` handles
existing user data gracefully (the key is silently ignored).

Reconsider mosh if:
  - cellular-roaming UX becomes a frequent complaint, AND
  - the project has more than one maintainer or budget for a
    contracted Swift port of `mosh-client`.
