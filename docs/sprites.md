# Sprite assets

The animated mascot sprites that ship in the App Store build are not
included in this repository. They are licensed for use in the compiled
sshido app per their original itch.io creators but cannot be
redistributed through a public source tree.

## Behavior without sprites

The app builds and runs without them — `SpritePackManager` returns no
built-in packs, `activePack` becomes `nil`, and the mascot surfaces
render in their no-mascot fallback state. Everything else (SSH, tmux,
push notifications) is unaffected.

## If you want sprites in your build

Download the three packs from itch.io (each is free with a
name-your-own-price model — please pay the creators):

| Pack       | Creator     | itch.io URL                                                    |
|------------|-------------|----------------------------------------------------------------|
| otter      | RiLi_XL     | https://rili-xl.itch.io/otter-sprite-pack                      |
| sleepycat  | ToffeeCraft | https://toffeecraft.itch.io/cat-sleeping-animation-free        |
| peak       | quipinny    | https://quipinny.itch.io/pixelartpeakanimation                 |

Per their license terms, you may include them in your local sshido build
for personal use, but you may not redistribute the raw `.gif` files.

### Naming convention

After downloading, encode each mood as a separate animated GIF and place
them in `Sources/UI/Sprites/Assets/` using this filename pattern:

```
otter_<mood>.gif
sleepycat_1_<mood>.gif
sleepycat_3_<mood>.gif
sleepycat_5_<mood>.gif
```

…where `<mood>` is one of: `sitting`, `watching`, `excited`, `spooked`,
`happy`, `napping`.

The `scripts/prepare_sprites.py` helper expects the raw frames in
`~/Downloads/` and produces files matching this convention. See its
docstring for the directory layout it expects.

`server/sprite-assets/peak/` is the staging area for a future sprite
marketplace; it follows the same `peak_<color>_<mood>.gif` pattern but is
not loaded by the iOS app today.

## Why this is the way it is

All three packs are licensed roughly as "free to use in your own
commercial or non-commercial projects; do not redistribute the asset
pack itself." That license is compatible with shipping the assets inside
the compiled App Store binary (the user's intended use) but incompatible
with hosting the raw `.gif` files in a public MIT-licensed source repo.
See issue #12 for the full audit.
