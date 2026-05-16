#!/usr/bin/env python3
"""
Script 1: Process South Anchor
=================================
Run this immediately after downloading a raw PNG from Gemini.

Usage:
    python process_anchor.py <input.png> [--cell <size>]

    <input.png>   - raw 1024x1024 PNG from Gemini (green background)
    --cell <size> - native pixel size for snap (default: 10, try 8/10/12/16)

Outputs (next to input file):
    *_snapped.png  - pixel-snapped, green background kept (use as Image Prompt for next directions)
    *_clean.png    - transparent background, foot-normalized 256x256 (for preview / Paper Doll)

Requirements:
    pip install Pillow numpy
"""

import sys
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

# ─── CONFIG ───────────────────────────────────────────────────────────────────

CHROMA_COLOR = (0, 255, 0)
CHROMA_TOLERANCE = 50    # how aggressively to remove green fringe (0-255)
CELL_SIZE = 256          # output cell size for normalized clean version
OUTPUT_ANCHOR_SIZE = 1024

# ──────────────────────────────────────────────────────────────────────────────


def pixel_snap(img: Image.Image, cell_size: int) -> Image.Image:
    """Nearest-neighbor downscale then upscale to recover native pixel grid."""
    w, h = img.size
    small_w = max(1, round(w / cell_size))
    small_h = max(1, round(h / cell_size))
    downscaled = img.resize((small_w, small_h), Image.NEAREST)
    snapped = downscaled.resize((w, h), Image.NEAREST)
    return snapped


def remove_chroma(img: Image.Image, tolerance: int = CHROMA_TOLERANCE) -> Image.Image:
    """Replace green background with transparency."""
    rgba = img.convert("RGBA")
    arr = np.array(rgba, dtype=np.int32)

    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]

    # pixel is green if green channel dominates both red and blue by tolerance
    mask = (
        (g - r > tolerance) &
        (g - b > tolerance)
    )
    arr[:, :, 3] = np.where(mask, 0, arr[:, :, 3])

    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def foot_normalize(img: Image.Image, cell_w: int = CELL_SIZE, cell_h: int = CELL_SIZE) -> Image.Image:
    """
    Normalize sprite into a cell:
    - Lowest non-transparent pixel → y = cell_h - 1
    - Horizontally centered at x = cell_w // 2
    - Scale down if sprite is larger than cell (preserve aspect, nearest-neighbor)
    """
    arr = np.array(img.convert("RGBA"))
    alpha = arr[:, :, 3]

    rows = np.where(alpha.max(axis=1) > 0)[0]
    cols = np.where(alpha.max(axis=0) > 0)[0]

    if len(rows) == 0 or len(cols) == 0:
        return Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))

    top, bottom = int(rows[0]), int(rows[-1])
    left, right = int(cols[0]), int(cols[-1])
    cropped = arr[top : bottom + 1, left : right + 1]

    sprite_h, sprite_w = cropped.shape[:2]

    # Scale down to fit cell if needed (never upscale — preserve native grid)
    scale = min(cell_w / sprite_w, cell_h / sprite_h, 1.0)
    new_w = max(1, int(sprite_w * scale))
    new_h = max(1, int(sprite_h * scale))

    sprite_img = Image.fromarray(cropped).resize((new_w, new_h), Image.NEAREST)

    cell = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
    paste_x = (cell_w - new_w) // 2          # center horizontally
    paste_y = cell_h - new_h                  # foot at bottom
    cell.paste(sprite_img, (paste_x, paste_y), sprite_img)
    return cell


def process_anchor(input_path: Path, native_cell: int) -> None:
    print(f"Loading: {input_path}")
    img = Image.open(input_path).convert("RGB")

    if img.size != (OUTPUT_ANCHOR_SIZE, OUTPUT_ANCHOR_SIZE):
        print(f"  Resizing from {img.size} → ({OUTPUT_ANCHOR_SIZE}, {OUTPUT_ANCHOR_SIZE})")
        img = img.resize((OUTPUT_ANCHOR_SIZE, OUTPUT_ANCHOR_SIZE), Image.NEAREST)

    # Step 1 — Pixel snap
    print(f"  Pixel snapping (native cell = {native_cell}px)...")
    snapped = pixel_snap(img, native_cell)

    out_snapped = input_path.with_name(input_path.stem + "_snapped.png")
    snapped.save(out_snapped)
    print(f"  Saved: {out_snapped.name}  ← use this as Image Prompt for other directions")

    # Step 2 — Remove chroma + foot-normalize
    print("  Removing green background...")
    clean_rgba = remove_chroma(snapped)

    print(f"  Normalizing to {CELL_SIZE}×{CELL_SIZE} cell (foot-baseline lock)...")
    normalized = foot_normalize(clean_rgba)

    out_clean = input_path.with_name(input_path.stem + "_clean.png")
    normalized.save(out_clean)
    print(f"  Saved: {out_clean.name}  ← preview / Paper Doll reference")

    print("Done.")


def main():
    parser = argparse.ArgumentParser(description="Process South Anchor sprite from Gemini.")
    parser.add_argument("input", type=Path, help="Raw PNG file from Gemini")
    parser.add_argument("--cell", type=int, default=10,
                        help="Native pixel size for snap (default 10; try 8/10/12/16)")
    args = parser.parse_args()

    if not args.input.exists():
        print(f"Error: file not found: {args.input}")
        sys.exit(1)

    process_anchor(args.input, args.cell)


if __name__ == "__main__":
    main()
