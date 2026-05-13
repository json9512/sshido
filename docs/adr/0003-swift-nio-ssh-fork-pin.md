# swift-nio-ssh: pinned through Citadel's fork, audited at one point in time

sshido's SSH stack is `Citadel` (high-level client) on top of
`swift-nio-ssh` (wire protocol). Citadel's `Package.swift` does not
depend on `apple/swift-nio-ssh` — it pins
`https://github.com/Wellz26/swift-nio-ssh.git`, "0.3.4" ..< "0.4.0".
Our `Package.resolved` therefore records this URL and an exact
revision (`a05e6bbe6b141ee68da3030e00275504c0595d4d` as of writing).

## Why a fork

From Citadel issue #116 (closed 2024) the Citadel maintainer
Joannis Orlandos states verbatim:

> The official NIOSSH cannot be used as it misses some patches that
> have taken 4 years to review/discuss and counting.

The fork carries client-side features Citadel needs but Apple has not
merged: certificate authentication, RSA private-key support, multiple
MACs per transport, platform support for visionOS / Android / Musl /
Mac Catalyst, plus several bug fixes (debug crash in AES-GCM, `\r\n`
line-ending handling).

The fork chain is `apple/swift-nio-ssh → Joannis/swift-nio-ssh →
Wellz26/swift-nio-ssh`. Joannis's repo is the working copy (default
branch `citadel2`); Wellz26's is the release host that Citadel pins
against. The `jo-` prefixed branches on Wellz26's repo carry Joannis's
in-progress work. We have no relationship with either account beyond
what Citadel's Package.swift transitively gives us.

## Audit at the time of writing (2026-05-13)

`git diff apple/main...Wellz26/citadel2`, restricted to the pinned
revision, summarises as:

- 76 commits ahead of `apple/main`
- 84 files changed (+3,848, −527 lines)
- Themes from commit log:
  - certificate authentication
    (`Tests/NIOSSHTests/SSHConfigurationCertificateTests.swift`,
    `SSHKeyExchangeCertificateTests.swift`, related sources)
  - RSA private key support
  - multiple MACs per transport
  - platform support (visionOS, Android, Musl/Bionic, Mac Catalyst)
  - AES-GCM debug-crash fix and `\r\n` line-ending handling
- Contributors named in the commit log (Joannis, nedithgar,
  florentmorin, tkrajacic, tymscar) are recognisable Swift OSS
  handles.

We did **not** perform a byte-level wire-protocol audit of the
key-exchange or packet-parsing changes — that would require expert
SSH-protocol review (estimated half a day) and is deferred.

## Risk

Trusting `Wellz26/swift-nio-ssh` puts that GitHub account into the TCB
of every sshido build. If the account is compromised or hijacked, a
malicious release could land in our build the next time we run
`swift package update`. Mitigations in place:

- `Package.resolved` pins the exact revision hash. SPM honours the
  pinned revision indefinitely until `swift package update` is
  explicitly invoked, so an attacker publishing a new tag does not
  silently flow through.
- The pinned revision was audited at the level described above on
  2026-05-13.

The "fork through an org we control + commit-hash pin" path
(Wellz26 → json9512/swift-nio-ssh, plus a Citadel fork or SPM mirror
config) was considered and deferred. The maintenance burden of
keeping a personal swift-nio-ssh fork in sync with Joannis's
Citadel-track work, combined with the need to similarly host a
Citadel fork or maintain `.swiftpm/configuration/mirrors.json`,
exceeds the value of namespace control at sshido's current stage.

## Trigger to revisit

Re-audit:

1. **At every Citadel upgrade.** Don't accept a Citadel version bump
   without re-running `git log apple/main..Wellz26/citadel2` against
   the new pinned revision and updating this ADR.
2. **If the project gains a real userbase** (App Store install base
   beyond personal-use scale). At that point the lift of forking
   `Wellz26/swift-nio-ssh@<hash>` to `json9512/swift-nio-ssh`,
   configuring an SPM mirror, and shifting account-compromise risk
   onto an account we control becomes worth the ongoing work.
3. **If Apple merges Citadel's outstanding NIOSSH patches** — Joannis
   would presumably retire the fork, Citadel would re-pin to
   `apple/swift-nio-ssh`, and this ADR becomes obsolete.

Never run `swift package update` against this dependency without
re-doing the audit and updating this ADR.
