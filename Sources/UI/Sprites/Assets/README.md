# Sprite assets — not committed

Built-in sprite GIFs (`otter_*.gif`, `sleepycat_{1,3,5}_*.gif`) live here at
build time but are not tracked in git. They are licensed for use in the
compiled sshido app per their original itch.io creators but cannot be
redistributed through a public repository.

See `docs/sprites.md` at the repo root for source URLs and the naming
convention. The app gracefully falls back to a no-mascot state when this
directory is empty.
