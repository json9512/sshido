# Server metrics over SSH exec channels, not an installed agent

The "Server performance" view shows live CPU, load, memory, disk and
network rates for a remote host. It samples the server by running
short shell command bundles over a Citadel `SSHClient.executeCommand`
channel — a second channel on the same SSH connection, opened and
closed per sample — and parsing the output in Swift on the device.

## Why not push an agent binary

The first design we considered was an `sshido-agentd` binary the app
would `scp` into `~/.sshido/` on first connection and exec for each
sample. Rejected:

- Binary distribution per (OS × arch) is a real ongoing cost. Linux
  alone splits into glibc / musl / Alpine, plus arm64 / amd64 /
  armv7. macOS adds arm64e and x86_64. We would be shipping six-plus
  binaries from the iOS bundle and writing them into the user's home
  directory without their having asked.
- TestFlight / App Store review surface widens — uploading executables
  to remote hosts is non-trivial to explain in a privacy nutrition
  label, and the entitlement story is unclear.
- The current alternative is "POSIX shell + tools already on the box."
  `/proc`, `sysctl`, `vm_stat`, `df`, `netstat`, and `top` are
  installed everywhere the user already has an SSH login. We don't
  have to apologise for installing software.

The door for an opt-in agent is left open: anyone who wants
sub-100 ms cadence or per-process metrics can later add a
`Sources/Core/MetricsAgentChannel.swift` next to
`MetricsOnlySSHChannel.swift`. The collector dispatches on
`ServerOSFamily`, so plugging in a new transport means adding a
fourth case.

## Why a separate channel, not the user's PTY

`CitadelSSHChannel` already holds an interactive PTY for the user's
shell — that PTY is where the user is typing and where `tmux` (when
enabled) lives. Stealing it for `cat /proc/stat` would interleave
shell prompts with metrics output and confuse `bash`'s line editor.

SSH multiplexes channels. Citadel's `SSHClient.executeCommand`
(`.build/checkouts/Citadel/.../TTY/Client/TTY.swift:201`) opens a
fresh `session` channel for each command and tears it down on EOF.
The interactive PTY is untouched. The cost is one round-trip of SSH
channel-open/close per sample, which on a LAN is microseconds and on
the worst LTE we've seen is ~50 ms — well under the 1 s minimum
cadence.

`MetricsOnlySSHChannel` exists for the host-scope path
(`Sources/AppUI/SessionsListView.swift` → "Server performance" row)
where there is no interactive session to piggyback on. It is a
Citadel `SSHClient` connection with the PTY task simply not started;
the same TOFU host-key validator runs.

## Why sentinel-delimited bundles, not one command per metric

A single bundled command per sample (`echo '=STAT='; head -n 1
/proc/stat; echo '=MEMINFO='; cat /proc/meminfo; ...`) costs one SSH
channel round-trip. Running each sub-command in its own
`executeCommand` would cost N round-trips. The bundle is parsed in
Swift via `SentinelBlocks` — a stupid splitter that demarcates blocks
on lines matching `^=[A-Z0-9_]+=$`.

Single-line sentinels were chosen over JSON or other structured
output because:

- Every shell on every supported OS can produce them. `jq` is not
  installed everywhere, and the kernel's `/proc` files emit
  whitespace-separated text already — converting to JSON would be
  pure cost.
- Parser bugs are visible and testable from canned fixtures. The
  per-OS parser tests (`Tests/sshidoCoreTests/MetricsParserTests.swift`
  and `MetricsParserDarwinTests.swift`) check exact byte-level inputs
  copied from real `/proc/stat`, `vm_stat`, etc. against expected
  numeric output.
- If a sub-command fails — `vm.swapusage` requires permissions on
  some macOS versions, `/proc/diskstats` can be hidden inside some
  containers — only the affected block is missing from the parse, and
  the UI degrades to "—" for that field instead of dropping the whole
  sample.

The sentinel namespace (`=NAME=`) was chosen because it is unlikely
to collide with shell output: `/proc/*` files don't produce such
lines, and `/etc/os-release` uses `KEY="value"` (no leading `=`).

## OS dispatch

`ServerMetricsCollector.ensureHostInfo` runs `uname -s` once per
host (cached) and dispatches `sample()` to the matching family:

- `.linux` → `/proc/stat`, `/proc/loadavg`, `/proc/uptime`,
  `/proc/meminfo`, `/proc/net/dev`, `df -PkT`
- `.darwin` → `sysctl vm.loadavg`, `sysctl kern.boottime`, `vm_stat`,
  `sysctl hw.memsize`, `sysctl vm.swapusage`, `top -l 2 -s 1 -n 0`
  for instantaneous CPU%, `netstat -ibn`, `df -Pk`
- everything else → `SSHError.transport("not yet implemented")`

On Linux the CPU sample needs two snapshots of `/proc/stat` to
diff jiffies; the collector retains the previous `cpu` line and
emits `nil` for `CPUSample` on the first tick. On macOS `top -l 2`
returns instantaneous percentages from kernel-side accounting, so no
state is needed but the sample blocks for one second per tick — the
real cadence on macOS is therefore `intervalSeconds + 1`.

## Cadence

`MetricsSettings.intervalKey` (`"sshido.metrics.intervalSeconds"`,
default 2) is shared between Settings and the view via `@AppStorage`.
Allowed values are 1, 2, 5 seconds. The view drives its task with
`StreamKey(active:intervalSeconds:)` — when the user changes the
picker the task re-fires, the subscriber detaches, `MetricsStore`'s
last-subscriber teardown stops the existing pump, and a fresh pump
starts at the new interval. There is no separate "change interval"
API on the store.

`scenePhase != .active` is folded into the same key, so backgrounding
the app drops the subscriber and tears down the pump. Foregrounding
restarts it; the first post-resume sample emits zero net rates and
`nil` CPU% because the previous counter snapshot was discarded with
the pump. Re-baselining within ~2 s of resume is acceptable in
practice.

## Trigger to revisit

- A user reports that running metrics over their primary SSH
  connection causes noticeable lag in the interactive PTY. Investigate
  whether Citadel serializes channel writes on the underlying NIO
  event loop; if so, split metrics onto a separate SSHClient.
- A user wants per-process / per-container metrics that the shell
  bundle cannot reasonably produce. Build an opt-in agent binary at
  that point — do not creep features into the shell bundle.
- macOS sample latency becomes an annoyance. Replace `top -l 2 -s 1`
  with a tiny C helper using `host_processor_info` and ship it via
  the agent path above; do not invent a third channel type.
