#!/usr/bin/env python3
"""
Converts raw sprite assets from ~/Downloads into per-mood animated GIFs
matching the {prefix}_{mood}.gif convention used by sshido's sprite system.

Usage: python3 scripts/prepare_sprites.py [output_dir]
Default output: Sources/UI/Sprites/Assets/
"""

import os
import sys
import shutil
from pathlib import Path
from PIL import Image

DOWNLOADS = Path.home() / "Downloads"
DEFAULT_OUT = Path(__file__).parent.parent / "Sources" / "UI" / "Sprites" / "Assets"

MOODS = ["sitting", "watching", "excited", "spooked", "happy", "napping"]
FPS = {"sitting": 4, "watching": 6, "excited": 12, "spooked": 10, "happy": 8, "napping": 2}


def frames_to_gif(frames: list, fps: float, output_path: Path, loop: bool = True):
    """Combine PIL Image frames into an animated GIF."""
    if not frames:
        return
    duration_ms = int(1000 / fps)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if len(frames) == 1:
        frames[0].save(str(output_path), format="GIF", save_all=False,
                       transparency=frames[0].info.get("transparency", 255))
    else:
        frames[0].save(
            str(output_path),
            format="GIF",
            save_all=True,
            append_images=frames[1:],
            duration=duration_ms,
            loop=0 if loop else 1,
            transparency=frames[0].info.get("transparency", 255),
            disposal=2,
        )
    print(f"  -> {output_path.name} ({len(frames)}f, {fps}fps, {output_path.stat().st_size}B)")


def extract_strip(image: Image.Image, frame_w: int, frame_h: int = None, num_frames: int = None, skip_empty: bool = True) -> list:
    """Extract frames from a horizontal strip. Optionally skip fully-transparent frames."""
    if frame_h is None:
        frame_h = image.height
    if num_frames is None:
        num_frames = image.width // frame_w
    frames = []
    for i in range(num_frames):
        box = (i * frame_w, 0, (i + 1) * frame_w, frame_h)
        frame = image.crop(box).convert("RGBA")
        if skip_empty:
            alpha = frame.getchannel("A")
            if alpha.getbbox() is None:
                continue  # fully transparent, skip
        frames.append(frame)
    return frames


def extract_grid_row(image: Image.Image, row: int, frame_w: int, frame_h: int, num_cols: int) -> list:
    """Extract one row of frames from a grid spritesheet."""
    frames = []
    for col in range(num_cols):
        box = (col * frame_w, row * frame_h, (col + 1) * frame_w, (row + 1) * frame_h)
        frame = image.crop(box).convert("RGBA")
        frames.append(frame)
    return frames


def extract_grid_cell(image: Image.Image, col: int, row: int, cell_w: int, cell_h: int) -> Image.Image:
    """Extract a single cell from a grid."""
    box = (col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h)
    return image.crop(box).convert("RGBA")


def pad_to_square(frame: Image.Image) -> Image.Image:
    """Pad a non-square frame to square, centered."""
    w, h = frame.size
    if w == h:
        return frame
    size = max(w, h)
    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    result.paste(frame, ((size - w) // 2, (size - h) // 2))
    return result


def crop_to_content(frame: Image.Image, padding: int = 2) -> Image.Image:
    """Crop frame to its content bounding box with padding."""
    alpha = frame.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        return frame
    left, top, right, bottom = bbox
    left = max(0, left - padding)
    top = max(0, top - padding)
    right = min(frame.width, right + padding)
    bottom = min(frame.height, bottom + padding)
    cropped = frame.crop((left, top, right, bottom))
    return pad_to_square(cropped)


def extract_gif_frames(gif_path: Path, start: int = 0, end: int = None) -> list:
    """Extract frame range from an animated GIF."""
    gif = Image.open(str(gif_path))
    frames = []
    try:
        i = 0
        while True:
            if end is not None and i > end:
                break
            if i >= start:
                frames.append(gif.convert("RGBA").copy())
            i += 1
            gif.seek(gif.tell() + 1)
    except EOFError:
        pass
    return frames


def rgba_to_gif_frame(frame: Image.Image) -> Image.Image:
    """Convert RGBA to palette mode with transparency for GIF output."""
    # Create a new image with a transparent background
    alpha = frame.getchannel("A")
    # Convert to palette
    p = frame.convert("RGB").quantize(colors=255, method=2)
    # Set transparency
    mask = Image.eval(alpha, lambda a: 255 if a < 128 else 0)
    p.paste(255, mask)  # index 255 = transparent
    p.info["transparency"] = 255
    return p


def save_mood_gifs(prefix: str, mood_frames: dict, out: Path, extras: dict = None):
    """Save per-mood GIFs. mood_frames: {mood_name: (frames_list, fps)}"""
    for mood in MOODS:
        if mood in mood_frames:
            raw_frames, fps = mood_frames[mood]
            gif_frames = [rgba_to_gif_frame(f) for f in raw_frames]
            frames_to_gif(gif_frames, fps, out / f"{prefix}_{mood}.gif")
    if extras:
        for name, (raw_frames, fps) in extras.items():
            gif_frames = [rgba_to_gif_frame(f) for f in raw_frames]
            frames_to_gif(gif_frames, fps, out / f"{prefix}_{name}.gif")


# ─── Asset processors ────────────────────────────────────────────────

def process_pet_dogs(out: Path):
    """Pet Dogs Pack — 6 breeds, horizontal strips, 100x100 frames."""
    print("\n=== Pet Dogs ===")
    breeds = {
        "golden": ("Dog-1-Golden-Retriever", "Golden-Retriever"),
        "akita": ("Dog-2-Akita", "Akita"),
        "greatdane": ("Dog-3-Great-Dane", "Great-Dane"),
        "schnauzer": ("Dog-4-Schnauzer", "Schnauzer"),
        "saintbernard": ("Dog-5-Saint-Bernard", "Saint-Bernard"),
        "husky": ("Dog-6-Siberian-Husky", "Siberian-Husky"),
    }
    for slug, (folder, file_prefix) in breeds.items():
        print(f"\n  {slug}:")
        src = DOWNLOADS / "Pet Dogs Pack" / folder
        if not src.exists():
            print(f"  SKIP: {src} not found")
            continue
        prefix = f"dog_{slug}"

        def load(name):
            p = src / f"{file_prefix}-{name}.png"
            if p.exists():
                img = Image.open(str(p))
                return extract_strip(img, 100)
            return []

        mood_frames = {
            "sitting":  (load("idle"), 3),
            "watching": (load("walk"), 5),
            "excited":  (load("run"), 10),
            "spooked":  (load("bark"), 8),
            "happy":    (load("stretching"), 6),
            "napping":  (load("lying-down"), 3),
        }
        extras = {
            "walk":       (load("walk"), 8),
            "licking":    (load("licking1"), 6),
            "lying_down": (load("lying-down"), 4),
        }
        # Filter out empty
        mood_frames = {k: v for k, v in mood_frames.items() if v[0]}
        extras = {k: v for k, v in extras.items() if v[0]}
        save_mood_gifs(prefix, mood_frames, out, extras)


def process_minibear(out: Path):
    """MiniBear — 46-frame GIF per variant, extract frame ranges."""
    print("\n=== MiniBear ===")
    base = DOWNLOADS / "MiniBear_LYASeek_mod_by_LapizWCG"
    if not base.exists():
        print(f"  SKIP: {base} not found")
        return

    variants = {
        "piggypink": "PiggyPink",
        "molten": "Molten",
        "tsunami": "Tsunami",
        "emeraldvision": "EmeraldVision",
        "softgameboy": "SoftGameboy",
        "arcticdust": "ArcticDust",
    }

    frame_ranges = {
        "sitting":  (12, 15, 2),   # resting on belly (calm idle)
        "watching": (21, 26, 4),   # slow walk (alert)
        "excited":  (30, 35, 8),   # standing/waving
        "spooked":  (4, 8, 8),     # running
        "happy":    (16, 20, 6),   # jumping
        "napping":  (42, 45, 1),   # lying/sleeping (very slow)
    }
    extra_ranges = {
        "tumble":   (9, 11, 6),
        "walk":     (0, 3, 5),
        "sniffing": (39, 41, 4),
    }

    for slug, display_name in variants.items():
        print(f"\n  {slug}:")
        gif_path = base / f"MiniBear [{display_name}]" / f"MiniBear [{display_name}].gif"
        if not gif_path.exists():
            print(f"  SKIP: {gif_path} not found")
            continue

        # Extract all frames once
        all_frames = extract_gif_frames(gif_path)
        prefix = f"bear_{slug}"

        mood_frames = {}
        for mood, (start, end, fps) in frame_ranges.items():
            mood_frames[mood] = (all_frames[start:end+1], fps)

        extras = {}
        for name, (start, end, fps) in extra_ranges.items():
            extras[name] = (all_frames[start:end+1], fps)

        save_mood_gifs(prefix, mood_frames, out, extras)


def process_capybara(out: Path):
    """Capybara — 576x576 labeled sheet with irregular row layout."""
    print("\n=== Capybara ===")
    src = DOWNLOADS / "charlieTheCapybaraAnimationSheet.png"
    if not src.exists():
        print(f"  SKIP: {src} not found")
        return
    img = Image.open(str(src))

    # Actual row positions found by pixel scanning:
    # (y_start, y_end, num_frames, name)
    row_defs = [
        (84,  120, 8, "sitting_idle"),     # Row 0
        (148, 184, 3, "sit_down"),         # Row 1
        (213, 248, 8, "sitting_idle_2"),   # Row 2
        (276, 312, 3, "stand_up"),         # Row 3
        (340, 376, 4, "lean_down"),        # Row 4
        (404, 443, 8, "munch_grass"),      # Row 5
        (468, 505, 4, "lean_up"),          # Row 6
        (533, 576, 8, "walk"),             # Row 7
    ]
    fw = 64  # frame width is consistent

    def get_row(idx):
        y_start, y_end, nf, _ = row_defs[idx]
        fh = y_end - y_start
        frames = []
        for i in range(nf):
            box = (i * fw, y_start, (i + 1) * fw, y_end)
            frame = img.crop(box).convert("RGBA")
            frames.append(pad_to_square(frame))  # pad to 64x64
        return frames

    prefix = "capybara"
    mood_frames = {
        "sitting":  (get_row(0), 3),   # calm idle
        "watching": (get_row(2), 4),   # alert sitting
        "excited":  (get_row(7), 8),   # walking
        "spooked":  (get_row(3), 8),   # stand up
        "happy":    (get_row(5), 5),   # munch grass
        "napping":  (get_row(1), 1),   # sit down (very slow)
    }
    extras = {
        "lean_down": (get_row(4), 4),
        "lean_up":   (get_row(6), 4),
    }
    save_mood_gifs(prefix, mood_frames, out, extras)


def process_pengu(out: Path):
    """Pengu — horizontal strips, 128x128 frames."""
    print("\n=== Pengu ===")
    src = DOWNLOADS / "Pengu"
    if not src.exists():
        print(f"  SKIP: {src} not found")
        return

    def load(name):
        p = src / f"pengu_{name}.png"
        if p.exists():
            img = Image.open(str(p))
            return extract_strip(img, 128)
        return []

    prefix = "pengu"
    idle_frames = load("idle")
    mood_frames = {
        "sitting":  (idle_frames, 3),
        "watching": (idle_frames, 4),
        "excited":  (load("move"), 8),
        "spooked":  (load("hurt"), 6),
        "happy":    (load("attack_peck"), 6),
        "napping":  (idle_frames, 1),
    }
    extras = {
        "attack_ice": (load("attack_ice"), 8),
        "attack_ray": (load("attack_ray"), 8),
    }
    mood_frames = {k: v for k, v in mood_frames.items() if v[0]}
    extras = {k: v for k, v in extras.items() if v[0]}
    save_mood_gifs(prefix, mood_frames, out, extras)


def process_frog(out: Path):
    """Frog — 256x128, 4x2 grid, 64x64 cells, 8 costumes."""
    print("\n=== Frog ===")
    src = DOWNLOADS / "frog_spritesheets"
    if not src.exists():
        print(f"  SKIP: {src} not found")
        return

    costumes = ["green", "clown", "pirate", "cowboy", "tan_pirate", "tophat", "viking", "funnyglasses"]

    # Only 6 valid cells (cells (3,0) and (3,1) are empty)
    # Map moods to grid cells (col, row), crop to content for larger display
    mood_cells = {
        "sitting":  (0, 0),
        "watching": (1, 0),
        "excited":  (2, 0),
        "spooked":  (2, 1),   # small frog pose (was empty cell, now use pose7)
        "happy":    (0, 1),
        "napping":  (1, 1),
    }

    for costume in costumes:
        print(f"\n  {costume}:")
        p = src / f"frog_{costume}_spritesheet.png"
        if not p.exists():
            print(f"  SKIP: {p} not found")
            continue
        img = Image.open(str(p))
        prefix = f"frog_{costume}"

        mood_frames = {}
        for mood, (col, row) in mood_cells.items():
            cell = extract_grid_cell(img, col, row, 64, 64)
            # Crop to content so frog fills the frame better
            cropped = crop_to_content(cell, padding=3)
            mood_frames[mood] = ([cropped], 2)

        save_mood_gifs(prefix, mood_frames, out)


def process_bunny(out: Path):
    """Bunny — 220x444, ~55x55 frames, 4 cols x 8 rows."""
    print("\n=== Bunny ===")
    src = DOWNLOADS / "bunny-Sheet.png"
    if not src.exists():
        print(f"  SKIP: {src} not found")
        return
    img = Image.open(str(src))
    fw = img.width // 4   # 55
    fh = img.height // 8  # 55

    prefix = "bunny"
    mood_rows = {
        "sitting":  (0, 4),
        "watching": (1, 4),
        "excited":  (3, 3),
        "spooked":  (4, 3),
        "happy":    (5, 3),
        "napping":  (6, 3),
    }
    mood_frames = {}
    for mood, (row, nf) in mood_rows.items():
        frames = extract_grid_row(img, row, fw, fh, nf)
        # Crop frames to content for better visibility
        frames = [crop_to_content(f, padding=2) for f in frames]
        fps = {"sitting": 3, "watching": 4, "excited": 8, "spooked": 6, "happy": 5, "napping": 2}
        mood_frames[mood] = (frames, fps[mood])

    save_mood_gifs(prefix, mood_frames, out)


def process_crow(out: Path):
    """Crow — 192x192, 4x4 grid of 48x48. Skip cell (3,3) watermark."""
    print("\n=== Crow ===")
    src = DOWNLOADS / "Crow.png"
    if not src.exists():
        print(f"  SKIP: {src} not found")
        return
    img = Image.open(str(src))
    fw, fh = 48, 48

    prefix = "crow"
    mood_frames = {
        "sitting":  (extract_grid_row(img, 0, fw, fh, 4), 3),
        "watching": (extract_grid_row(img, 1, fw, fh, 4), 4),
        "excited":  (extract_grid_row(img, 2, fw, fh, 4), 8),
        "spooked":  (extract_grid_row(img, 3, fw, fh, 3), 6),  # skip cell (3,3)
        "happy":    (extract_grid_row(img, 1, fw, fh, 4), 5),
        "napping":  ([extract_grid_cell(img, 0, 0, fw, fh)], 1),
    }
    save_mood_gifs(prefix, mood_frames, out)


def process_porcupine(out: Path):
    """Porcupine — 160x160, 4x4 grid of 40x40."""
    print("\n=== Porcupine ===")
    src = DOWNLOADS / "Porcupine Sprite Sheet.png"
    if not src.exists():
        print(f"  SKIP: {src} not found")
        return
    img = Image.open(str(src))
    fw, fh = 40, 40

    prefix = "porcupine"
    mood_frames = {
        "sitting":  (extract_grid_row(img, 0, fw, fh, 4), 3),
        "watching": (extract_grid_row(img, 1, fw, fh, 4), 4),
        "excited":  (extract_grid_row(img, 2, fw, fh, 4), 8),
        "spooked":  (extract_grid_row(img, 3, fw, fh, 4), 6),
        "happy":    (extract_grid_row(img, 1, fw, fh, 4), 5),
        "napping":  ([extract_grid_cell(img, 0, 0, fw, fh)], 1),
    }
    save_mood_gifs(prefix, mood_frames, out)


def process_crab(out: Path):
    """Crab — individual frames, 18-20px."""
    print("\n=== Crab ===")
    base = DOWNLOADS / "Crab Enemy Camacebra Games"
    if not base.exists():
        print(f"  SKIP: {base} not found")
        return

    def load_frames(subdir, pattern, count):
        frames = []
        d = base / subdir
        if not d.exists():
            return frames
        for i in range(1, count + 1):
            p = d / pattern.format(i)
            if p.exists():
                frames.append(Image.open(str(p)).convert("RGBA"))
        return frames

    idle = load_frames("Idle", "Crab{}.png", 5)
    moving = load_frames("Moving", "CrabMoving{}.png", 4)
    attack = load_frames("Attack", "Crab_Attack{}.png", 4)

    prefix = "crab"
    mood_frames = {
        "sitting":  (idle, 3),
        "watching": (idle, 4),
        "excited":  (moving, 6),
        "spooked":  (attack, 6),
        "happy":    (moving, 5),
        "napping":  (idle[:1] if idle else [], 1),
    }
    mood_frames = {k: v for k, v in mood_frames.items() if v[0]}
    save_mood_gifs(prefix, mood_frames, out)


def process_horse(out: Path):
    """Horse — horizontal strips, 32x32 frames."""
    print("\n=== Horse ===")
    src = DOWNLOADS / "FarmHorsePack"
    if not src.exists():
        print(f"  SKIP: {src} not found")
        return

    def load(name):
        p = src / f"{name}.png"
        if p.exists():
            img = Image.open(str(p))
            return extract_strip(img, 32)
        return []

    idle = load("Idle")
    eating = load("Eating")
    sleeping = load("Sleeping")

    prefix = "horse"
    laydown = load("LayDown")
    mood_frames = {
        "sitting":  (idle, 3),
        "watching": (idle, 4),
        "excited":  (eating, 6),
        "spooked":  (idle, 6),
        "happy":    (eating, 4),
        "napping":  (sleeping, 1),
    }
    mood_frames = {k: v for k, v in mood_frames.items() if v[0]}
    save_mood_gifs(prefix, mood_frames, out)


def process_sleeping_cat(out: Path):
    """SleepingCat — horizontal strips, 64x64, 5 variants (use 3)."""
    print("\n=== SleepingCat ===")
    src = DOWNLOADS / "SleepingCatFree"
    if not src.exists():
        print(f"  SKIP: {src} not found")
        return

    variants = {"1": "sleepingcat1", "3": "sleepingcat3", "5": "sleepingcat5"}

    for num, filename in variants.items():
        print(f"\n  variant {num}:")
        p = src / f"{filename}.png"
        if not p.exists():
            print(f"  SKIP: {p} not found")
            continue
        img = Image.open(str(p))
        raw_frames = extract_strip(img, 64)
        prefix = f"sleepycat_{num}"

        # Duplicate frames for slow breathing: 0,0,1,1,2,2,3,3,4,4,5,5
        # This effectively halves the visual speed at any given FPS
        breathing = []
        for f in raw_frames:
            breathing.append(f)
            breathing.append(f)
            breathing.append(f)

        # All moods use same sleeping animation
        sleepy_fps = {"sitting": 3, "watching": 3, "excited": 4, "spooked": 4, "happy": 3, "napping": 2}
        mood_frames = {}
        for mood in MOODS:
            mood_frames[mood] = (breathing, sleepy_fps[mood])
        save_mood_gifs(prefix, mood_frames, out)


def process_otter(out: Path):
    """Otter — individual frames, 200x200."""
    print("\n=== Otter ===")
    src = DOWNLOADS / "otter_sprite_pack"
    if not src.exists():
        print(f"  SKIP: {src} not found")
        return

    def load_frames(pattern, count):
        frames = []
        for i in range(1, count + 1):
            p = src / pattern.format(i)
            if p.exists():
                frames.append(Image.open(str(p)).convert("RGBA"))
        return frames

    prefix = "otter"
    mood_frames = {
        "sitting":  (load_frames("otter_idle_{}.png", 4), 3),
        "watching": (load_frames("otter_idle_alt_{}.png", 12), 4),
        "excited":  (load_frames("otter_run_{}.png", 3), 8),
        "spooked":  (load_frames("otter_jump_{}.png", 4), 6),
        "happy":    (load_frames("otter_spin_{}.png", 3), 5),
        "napping":  (load_frames("otter_sleep_{}.png", 6), 1),
    }
    mood_frames = {k: v for k, v in mood_frames.items() if v[0]}
    save_mood_gifs(prefix, mood_frames, out)


# ─── Main ─────────────────────────────────────────────────────────────

def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    out.mkdir(parents=True, exist_ok=True)
    print(f"Output directory: {out}")

    processors = [
        process_pet_dogs,
        process_minibear,
        process_capybara,
        process_pengu,
        process_crow,
        process_crab,
        process_horse,
        process_sleeping_cat,
        process_otter,
    ]

    for proc in processors:
        try:
            proc(out)
        except Exception as e:
            print(f"\n  ERROR in {proc.__name__}: {e}")
            import traceback
            traceback.print_exc()

    # Count output files
    gifs = list(out.glob("*.gif"))
    # Filter to only new ones (not existing wolf/fox/etc)
    new_prefixes = [
        "dog_", "german_shepherd_", "bear_", "capybara_", "pengu_",
        "frog_", "bunny_", "ducky_", "crow_", "porcupine_", "pigeon_",
        "crab_", "horse_", "sleepycat_", "otter_",
    ]
    new_gifs = [g for g in gifs if any(g.name.startswith(p) for p in new_prefixes)]
    print(f"\n{'='*60}")
    print(f"Done! Generated {len(new_gifs)} new GIF files in {out}")


if __name__ == "__main__":
    main()
