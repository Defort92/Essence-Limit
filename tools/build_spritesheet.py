#!/usr/bin/env python3
"""
Script 2: Build Animation Spritesheet from Pose Board
=======================================================
Run this after downloading an animation pose board PNG from Gemini.

Usage:
    python build_spritesheet.py <poseboard.png> --action <name> --dir <direction> [options]

    <poseboard.png>    - 2048x1536 pose board from Gemini (green background, 4x3 grid)
    --action <name>    - animation name: idle | walk | attack | hurt | jump | death
    --dir <direction>  - s | n | e | w | ne | nw | se | sw
    --frames <n>       - number of valid frames to use (default: all non-empty cells)
    --fps <n>          - frames per second in manifest (default: 10)
    --cell <size>      - native pixel size for snap (default: 10)
    --cols <n>         - columns in pose board grid (default: 4)
    --rows <n>         - rows in pose board grid (default: 3)

Outputs (in same folder as input, subfolder per action):
    spritesheet.png    - 1280x512, 5x2 cells of 256x256, foot-anchored
    manifest.json      - Godot-ready frame data

Example:
    python build_spritesheet.py human_attack_w_poseboard.png --action attack --dir w

Requirements:
    pip install Pillow numpy
"""

import sys
import json
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

# ─── CONFIG ───────────────────────────────────────────────────────────────────

CHROMA_TOLERANCE = 50
SHEET_COLS = 5
SHEET_ROWS = 2
CELL_SIZE = 256           # output cell size
MIN_CONTENT_PIXELS = 50  # cells with fewer non-green pixels are considered empty

# ──────────────────────────────────────────────────────────────────────────────


def pixel_snap(img: Image.Image, cell_size: int) -> Image.Image:
    w, h = img.size
    small_w = max(1, round(w / cell_size))
    small_h = max(1, round(h / cell_size))
    downscaled = img.resize((small_w, small_h), Image.NEAREST)
    return downscaled.resize((w, h), Image.NEAREST)


def remove_chroma(img: Image.Image, tolerance: int = CHROMA_TOLERANCE) -> Image.Image:
    rgba = img.convert("RGBA")
    arr = np.array(rgba, dtype=np.int32)
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    mask = (g - r > tolerance) & (g - b > tolerance)
    arr[:, :, 3] = np.where(mask, 0, arr[:, :, 3])
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def foot_normalize(img: Image.Image) -> Image.Image:
    """Place lowest pixel at y=CELL_SIZE-1, center at x=CELL_SIZE//2."""
    arr = np.array(img.convert("RGBA"))
    alpha = arr[:, :, 3]

    rows = np.where(alpha.max(axis=1) > 0)[0]
    cols = np.where(alpha.max(axis=0) > 0)[0]

    if len(rows) == 0 or len(cols) == 0:
        return None  # empty frame

    top, bottom = int(rows[0]), int(rows[-1])
    left, right = int(cols[0]), int(cols[-1])
    cropped = arr[top : bottom + 1, left : right + 1]

    sprite_h, sprite_w = cropped.shape[:2]
    scale = min(CELL_SIZE / sprite_w, CELL_SIZE / sprite_h, 1.0)
    new_w = max(1, int(sprite_w * scale))
    new_h = max(1, int(sprite_h * scale))

    sprite_img = Image.fromarray(cropped).resize((new_w, new_h), Image.NEAREST)

    cell = Image.new("RGBA", (CELL_SIZE, CELL_SIZE), (0, 0, 0, 0))
    paste_x = (CELL_SIZE - new_w) // 2
    paste_y = CELL_SIZE - new_h
    cell.paste(sprite_img, (paste_x, paste_y), sprite_img)
    return cell


def extract_frames(poseboard: Image.Image, grid_cols: int, grid_rows: int, native_cell: int) -> list:
    """
    Split pose board into cells, snap each, remove chroma, foot-normalize.
    Returns list of RGBA Image cells (skips empty cells).
    """
    board_w, board_h = poseboard.size
    cell_w = board_w // grid_cols
    cell_h = board_h // grid_rows

    frames = []

    for row in range(grid_rows):
        for col in range(grid_cols):
            x0 = col * cell_w
            y0 = row * cell_h
            cell_raw = poseboard.crop((x0, y0, x0 + cell_w, y0 + cell_h))

            # Check if cell has enough content (not just green background)
            arr = np.array(cell_raw)
            r, g, b = arr[:, :, 0].astype(int), arr[:, :, 1].astype(int), arr[:, :, 2].astype(int)
            content_mask = ~((g - r > CHROMA_TOLERANCE) & (g - b > CHROMA_TOLERANCE))
            content_pixels = content_mask.sum()

            if content_pixels < MIN_CONTENT_PIXELS:
                print(f"  Cell ({row},{col}) — empty, skipping")
                continue

            # Pixel snap
            snapped = pixel_snap(cell_raw, native_cell)

            # Remove chroma
            clean = remove_chroma(snapped)

            # Foot-normalize into CELL_SIZE × CELL_SIZE
            normalized = foot_normalize(clean)
            if normalized is None:
                print(f"  Cell ({row},{col}) — no content after chroma removal, skipping")
                continue

            frames.append(normalized)
            print(f"  Cell ({row},{col}) — extracted frame {len(frames)}")

    return frames


def pack_spritesheet(frames: list, max_frames: int | None) -> Image.Image:
    """Pack frames into 1280x512 (5x2, 256x256 cells) sheet."""
    sheet_w = SHEET_COLS * CELL_SIZE
    sheet_h = SHEET_ROWS * CELL_SIZE
    sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))

    frames_to_pack = frames[:max_frames] if max_frames else frames
    if len(frames_to_pack) > SHEET_COLS * SHEET_ROWS:
        print(f"  Warning: {len(frames_to_pack)} frames > sheet capacity ({SHEET_COLS * SHEET_ROWS}), truncating")
        frames_to_pack = frames_to_pack[: SHEET_COLS * SHEET_ROWS]

    for i, frame in enumerate(frames_to_pack):
        col = i % SHEET_COLS
        row = i // SHEET_COLS
        x = col * CELL_SIZE
        y = row * CELL_SIZE
        sheet.paste(frame, (x, y), frame)

    return sheet, len(frames_to_pack)


def generate_manifest(action: str, direction: str, frame_count: int, fps: int, output_dir: Path) -> dict:
    manifest = {
        "version": 1,
        "action": action,
        "direction": direction,
        "spritesheet": "spritesheet.png",
        "frameWidth": CELL_SIZE,
        "frameHeight": CELL_SIZE,
        "columns": SHEET_COLS,
        "rows": SHEET_ROWS,
        "frames": frame_count,
        "fps": fps,
        "anchor": {"x": CELL_SIZE // 2, "y": CELL_SIZE - 1},
    }
    out = output_dir / "manifest.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print(f"  Saved: {out}")
    return manifest


def process_poseboard(
    input_path: Path,
    action: str,
    direction: str,
    fps: int,
    native_cell: int,
    grid_cols: int,
    grid_rows: int,
    max_frames: int | None,
) -> None:
    print(f"Loading pose board: {input_path}")
    board = Image.open(input_path).convert("RGB")
    print(f"  Size: {board.size}, grid: {grid_cols}×{grid_rows}")

    expected_w = grid_cols * (board.size[0] // grid_cols)
    expected_h = grid_rows * (board.size[1] // grid_rows)
    if (expected_w, expected_h) != board.size:
        board = board.resize((expected_w, expected_h), Image.NEAREST)
        print(f"  Cropped to even grid: {board.size}")

    print("Extracting frames...")
    frames = extract_frames(board, grid_cols, grid_rows, native_cell)
    print(f"  Total frames found: {len(frames)}")

    if not frames:
        print("Error: no frames extracted. Check chroma tolerance or input image.")
        sys.exit(1)

    print("Packing spritesheet...")
    sheet, packed = pack_spritesheet(frames, max_frames)

    out_dir = input_path.parent / f"{action}_{direction}"
    out_dir.mkdir(exist_ok=True)

    sheet_path = out_dir / "spritesheet.png"
    sheet.save(sheet_path)
    print(f"  Saved: {sheet_path}  ({packed} frames)")

    generate_manifest(action, direction, packed, fps, out_dir)
    print(f"Done. Output folder: {out_dir}")


def main():
    parser = argparse.ArgumentParser(description="Build Godot spritesheet from Gemini pose board.")
    parser.add_argument("input", type=Path, help="Pose board PNG from Gemini")
    parser.add_argument("--action", required=True,
                        choices=["idle", "walk", "attack", "hurt", "jump", "death"],
                        help="Animation type")
    parser.add_argument("--dir", required=True,
                        choices=["s", "n", "e", "w", "ne", "nw", "se", "sw"],
                        help="Facing direction")
    parser.add_argument("--frames", type=int, default=None,
                        help="Max frames to use (default: all non-empty)")
    parser.add_argument("--fps", type=int, default=10, help="FPS in manifest (default: 10)")
    parser.add_argument("--cell", type=int, default=10,
                        help="Native pixel size for snap (default: 10)")
    parser.add_argument("--cols", type=int, default=4, help="Pose board grid columns (default: 4)")
    parser.add_argument("--rows", type=int, default=3, help="Pose board grid rows (default: 3)")
    args = parser.parse_args()

    if not args.input.exists():
        print(f"Error: file not found: {args.input}")
        sys.exit(1)

    process_poseboard(
        input_path=args.input,
        action=args.action,
        direction=args.dir,
        fps=args.fps,
        native_cell=args.cell,
        grid_cols=args.cols,
        grid_rows=args.rows,
        max_frames=args.frames,
    )


if __name__ == "__main__":
    main()
