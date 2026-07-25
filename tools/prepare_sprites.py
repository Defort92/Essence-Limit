#!/usr/bin/env python3
"""
Script 0: Prepare raw AI-generated sprites for the animation pipeline
======================================================================
The one-command bridge from "folder of raw Gemini/Grok/PixelLab downloads"
to split parts + test animations. Chains into split_parts.py automatically.

Per image it performs:
  1. direction detection from the file name (front / s / south / front_left ...)
  2. optional pixel snap to the native pixel grid (--cell)
  3. background removal: green chroma key, auto-detected (skipped for
     images that are already transparent)
  4. alpha floor: barely-visible fringe pixels (alpha < --alpha-floor) dropped
  5. batch height normalization: every direction is scaled (NEAREST, no
     upscaling above --max-upscale) so silhouettes match one common height —
     AI generations of different directions never come out the same size
  6. placement on a 128x128 canvas with the shared foot anchor
  7. optional mirroring of missing directions from their left/right twin
  8. cross-direction consistency validation
  9. hands the normalized set to split_parts.py -> parts/ + frames/ +
     preview.png + report.txt

Usage:
    python prepare_sprites.py <raw_dir> [--out <dir>] [options]

    <raw_dir>            folder with raw PNGs, any size, green or transparent bg
    --out <dir>          output root (default: <raw_dir>/../_prepared)
    --height <n|auto>    target silhouette height in px on the 128 canvas
                         (default: auto = median of the batch, capped to fit)
    --cell <n>           pixel-snap cell in source pixels, 0 = off (default: 0)
    --mirror             synthesize missing directions by flipping their twin
                         (front-left <-> front-right, full-*, rear-*)
    --no-split           stop after normalization (skip parts/frames)
    --alpha-floor <n>    drop pixels with alpha below n (default: 24)
    --max-upscale <f>    max allowed upscale factor (default: 1.0 = never)
    plus all split_parts options: --bottom-margin, --head-frac, --torso-frac,
    --idle-amp, --walk-lift, --walk-bob

Example:
    python prepare_sprites.py _pixellab_out/base --mirror
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import split_parts as sp

# ─── CONFIG ───────────────────────────────────────────────────────────────────

CANVAS = sp.CANVAS
CHROMA_TOLERANCE = 50
# a raw image is considered green-screened when this share of it matches the key
CHROMA_MIN_SHARE = 0.10

# every alias (compass letters, words, underscores) -> canonical game folder name
DIRECTION_ALIASES = {
    "front": "front", "s": "front", "south": "front",
    "back": "back", "n": "back", "north": "back",
    "front-right": "front-right", "se": "front-right", "southeast": "front-right",
    "front-left": "front-left", "sw": "front-left", "southwest": "front-left",
    "rear-right": "rear-right", "ne": "rear-right", "northeast": "rear-right",
    "rear-left": "rear-left", "nw": "rear-left", "northwest": "rear-left",
    "full-right": "full-right", "e": "full-right", "east": "full-right", "right": "full-right",
    "full-left": "full-left", "w": "full-left", "west": "full-left", "left": "full-left",
}

MIRROR_TWIN = {
    "front-left": "front-right", "front-right": "front-left",
    "full-left": "full-right", "full-right": "full-left",
    "rear-left": "rear-right", "rear-right": "rear-left",
}

# ──────────────────────────────────────────────────────────────────────────────


def detect_direction(stem: str) -> str | None:
    """Match a file name to a canonical direction. Tries the whole normalized
    stem first, then trailing/leading tokens, so 'base_v2_front_left' works."""
    norm = stem.strip().lower().replace("_", "-").replace(" ", "-")
    if norm in DIRECTION_ALIASES:
        return DIRECTION_ALIASES[norm]
    tokens = norm.split("-")
    # try two-word directions from both ends, then single tokens
    for i in range(len(tokens) - 1):
        pair = f"{tokens[i]}-{tokens[i + 1]}"
        if pair in DIRECTION_ALIASES:
            return DIRECTION_ALIASES[pair]
    for tok in reversed(tokens):
        if tok in DIRECTION_ALIASES:
            return DIRECTION_ALIASES[tok]
    return None


def pixel_snap(img: Image.Image, cell: int) -> Image.Image:
    """NN-downscale + NN-upscale to recover the native pixel grid."""
    w, h = img.size
    small = img.resize((max(1, round(w / cell)), max(1, round(h / cell))), Image.NEAREST)
    return small.resize((w, h), Image.NEAREST)


def is_chroma_keyed(arr: np.ndarray) -> bool:
    r, g, b = arr[:, :, 0].astype(int), arr[:, :, 1].astype(int), arr[:, :, 2].astype(int)
    share = ((g - r > CHROMA_TOLERANCE) & (g - b > CHROMA_TOLERANCE)).mean()
    return share >= CHROMA_MIN_SHARE


def remove_chroma(arr: np.ndarray) -> np.ndarray:
    out = arr.copy()
    r, g, b = arr[:, :, 0].astype(int), arr[:, :, 1].astype(int), arr[:, :, 2].astype(int)
    mask = (g - r > CHROMA_TOLERANCE) & (g - b > CHROMA_TOLERANCE)
    out[:, :, 3] = np.where(mask, 0, arr[:, :, 3])
    return out


def apply_alpha_floor(arr: np.ndarray, floor: int) -> np.ndarray:
    """Kill near-invisible fringe pixels left by chroma removal / AA. A single
    alpha=2 speck below the feet would otherwise pull the baseline down."""
    out = arr.copy()
    out[out[:, :, 3] < floor] = 0
    return out


def silhouette_bbox(arr: np.ndarray) -> tuple[int, int, int, int] | None:
    """(top, bottom, left, right) of solid content, or None if empty."""
    mask = arr[:, :, 3] >= sp.ALPHA_SOLID
    rows = np.where(mask.any(axis=1))[0]
    cols = np.where(mask.any(axis=0))[0]
    if len(rows) == 0:
        return None
    return int(rows[0]), int(rows[-1]), int(cols[0]), int(cols[-1])


def normalize_one(arr: np.ndarray, target_height: int, max_upscale: float) -> np.ndarray:
    """Crop to content, scale the silhouette to target_height (NEAREST),
    return the sprite on a transparent 128x128 canvas (not yet anchored —
    split_parts re-anchors precisely)."""
    box = silhouette_bbox(arr)
    if box is None:
        raise ValueError("empty sprite after background removal")
    top, bottom, left, right = box
    content = arr[top:bottom + 1, left:right + 1]
    h, w = content.shape[:2]

    scale = target_height / h
    scale = min(scale, max_upscale)
    new_h = max(1, round(h * scale))
    new_w = max(1, round(w * scale))
    if new_w > CANVAS:  # extremely wide pose — fit by width instead
        new_w = CANVAS
        new_h = max(1, round(h * CANVAS / w))
    scaled = np.array(Image.fromarray(content).resize((new_w, new_h), Image.NEAREST))

    canvas = np.zeros((CANVAS, CANVAS, 4), dtype=np.uint8)
    x0 = (CANVAS - new_w) // 2
    y0 = CANVAS - new_h  # rough placement; exact anchor comes from split_parts
    canvas[y0:y0 + new_h, x0:x0 + new_w] = scaled
    return canvas


def load_raw(path: Path, cell: int, alpha_floor: int) -> np.ndarray:
    img = Image.open(path).convert("RGBA")
    if cell > 1:
        img = pixel_snap(img, cell)
    arr = np.array(img)
    if is_chroma_keyed(arr):
        arr = remove_chroma(arr)
    arr = apply_alpha_floor(arr, alpha_floor)
    return sp.sanitize(arr)


def main():
    parser = argparse.ArgumentParser(
        description="Prepare raw AI sprites: normalize, then split into parts/animations.")
    parser.add_argument("raw_dir", type=Path, help="Folder with raw AI-generated PNGs")
    parser.add_argument("--out", type=Path, default=None,
                        help="Output root (default: <raw_dir>/../_prepared)")
    parser.add_argument("--height", default="auto",
                        help="Target silhouette height px, or 'auto' (default)")
    parser.add_argument("--cell", type=int, default=0,
                        help="Pixel-snap cell in source px, 0 = off (default: 0)")
    parser.add_argument("--mirror", action="store_true",
                        help="Create missing directions by flipping their twin")
    parser.add_argument("--no-split", action="store_true",
                        help="Only normalize, skip parts/frames generation")
    parser.add_argument("--alpha-floor", type=int, default=24)
    parser.add_argument("--max-upscale", type=float, default=1.0)
    # passed through to split_parts
    parser.add_argument("--bottom-margin", type=int, default=8)
    parser.add_argument("--head-frac", type=float, default=0.30)
    parser.add_argument("--torso-frac", type=float, default=0.62)
    parser.add_argument("--idle-amp", type=int, default=2)
    parser.add_argument("--walk-lift", type=int, default=2)
    parser.add_argument("--walk-bob", type=int, default=1)
    args = parser.parse_args()

    if not args.raw_dir.is_dir():
        print(f"Error: not a directory: {args.raw_dir}")
        sys.exit(1)
    out_root = args.out or (args.raw_dir.parent / "_prepared")

    # ── collect raw images per direction ────────────────────────────────────
    raw: dict[str, np.ndarray] = {}
    for path in sorted(args.raw_dir.glob("*.png")):
        direction = detect_direction(path.stem)
        if direction is None:
            print(f"  Skipping {path.name}: can't detect direction from the name")
            continue
        if direction in raw:
            print(f"  Skipping {path.name}: direction '{direction}' already taken")
            continue
        try:
            raw[direction] = load_raw(path, args.cell, args.alpha_floor)
        except ValueError as e:
            print(f"  Skipping {path.name}: {e}")
            continue
        print(f"  {path.name} -> {direction}")

    if not raw:
        print("Error: no usable sprites found.")
        sys.exit(1)

    # ── mirror missing directions ───────────────────────────────────────────
    if args.mirror:
        for direction, twin in MIRROR_TWIN.items():
            if direction not in raw and twin in raw:
                raw[direction] = raw[twin][:, ::-1].copy()
                print(f"  {direction} <- mirrored from {twin}")

    missing = sorted(sp.KNOWN_DIRECTIONS - set(raw))
    if missing:
        print(f"  Note: directions still missing: {', '.join(missing)}")

    # ── pick the common silhouette height ───────────────────────────────────
    heights = {}
    for direction, arr in raw.items():
        box = silhouette_bbox(arr)
        heights[direction] = box[1] - box[0] + 1
    max_fit = CANVAS - args.bottom_margin - 4  # keep >=4px headroom
    if args.height == "auto":
        target_h = min(int(np.median(list(heights.values()))), max_fit)
    else:
        target_h = min(int(args.height), max_fit)
    print(f"\nSilhouette heights in batch: {dict(sorted(heights.items()))}")
    print(f"Common target height: {target_h}px (canvas {CANVAS}, margin {args.bottom_margin})")

    # ── normalize and save ──────────────────────────────────────────────────
    norm_dir = out_root / "normalized"
    norm_dir.mkdir(parents=True, exist_ok=True)
    consistency = ["CROSS-DIRECTION CONSISTENCY (after normalization)", "-" * 58]
    all_ok = True
    for direction, arr in sorted(raw.items()):
        normalized = normalize_one(arr, target_h, args.max_upscale)
        Image.fromarray(normalized).save(norm_dir / f"{direction}.png")
        box = silhouette_bbox(normalized)
        got_h = box[1] - box[0] + 1
        note = ""
        if abs(got_h - target_h) > 1:
            note = f"  <-- HEIGHT OFF (upscale capped? source {heights[direction]}px)"
            all_ok = False
        consistency.append(f"{direction:12s} height {got_h:3d}px (target {target_h}){note}")
    print("\n".join(consistency))
    (out_root / "consistency.txt").write_text("\n".join(consistency), encoding="utf-8")

    if args.no_split:
        print(f"\nNormalized sprites: {norm_dir}")
        return

    # ── split into parts + build animations ─────────────────────────────────
    print()
    split_ok = sp.run(norm_dir, out_root, args)

    print()
    if all_ok and split_ok:
        print("ALL CHECKS PASSED — see preview.png and report.txt in", out_root)
    else:
        print("FINISHED WITH WARNINGS — check consistency.txt / report.txt in", out_root)
        sys.exit(2)


if __name__ == "__main__":
    main()
