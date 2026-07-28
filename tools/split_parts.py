#!/usr/bin/env python3
"""
Script 3: Split static direction sprites into body parts & build test animations
=================================================================================
Takes final 128x128 transparent-background direction sprites (front.png,
back.png, full_left.png, ...) and produces:

  parts/<direction>/    head / torso / legs_left / legs_right layers on the same
                        128x128 canvas (paper-doll style) + parts.json.
                        Bands are strictly disjoint, so composing all parts at
                        zero offsets rebuilds the anchored original EXACTLY
                        (verified automatically, see report.txt).
  frames/<direction>/   procedurally assembled idle_NN / walk_NN frames,
                        foot-baseline locked. Folder layout matches
                        assets/sprites/characters/base/frames/ (drop-in).
  preview.png           contact sheet: one row per direction, static + all frames
  report.txt            baseline / silhouette / center-of-mass drift validation

The walk cycle is a procedural placeholder (leg lift + torso bob) meant for
testing the animation pipeline; hand-made or generated frames can replace
individual PNG files later without changing the layout.

Usage:
    python split_parts.py <input_dir> [--out <dir>] [options]

    <input_dir>          folder with <direction>.png files (128x128 RGBA)
    --out <dir>          output folder (default: <input_dir>/../_animation_out)
    --bottom-margin <n>  feet baseline offset from canvas bottom (default: 8)
    --head-frac <f>      head/torso cut as fraction of silhouette height (default: 0.30)
    --torso-frac <f>     torso/legs cut as fraction of silhouette height (default: 0.62)
    --idle-amp <n>       idle breathing amplitude, px (default: 2)
    --walk-lift <n>      walk leg lift, px (default: 2)
    --walk-bob <n>       walk torso bob, px (default: 1)

Requirements:
    pip install Pillow numpy
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

# ─── CONFIG ───────────────────────────────────────────────────────────────────

CANVAS = 128
ALPHA_SOLID = 128        # alpha threshold: below this a pixel is ignored for geometry
MIN_FOOT_WIDTH = 3       # baseline = lowest row with at least this many solid pixels

# game folder names (scripts/components/directional_sprite.gd DIR_FOLDERS)
KNOWN_DIRECTIONS = {
    "front", "front-right", "full-right", "rear-right",
    "back", "rear-left", "full-left", "front-left",
}

# ──────────────────────────────────────────────────────────────────────────────


def canon_direction(stem: str) -> str:
    """front_left / full_left → front-left / full-left (game folders use dashes)."""
    return stem.strip().lower().replace("_", "-")


def solid_mask(arr: np.ndarray) -> np.ndarray:
    return arr[:, :, 3] >= ALPHA_SOLID


def sanitize(arr: np.ndarray) -> np.ndarray:
    """Zero the RGB of fully transparent pixels. Chroma removal leaves hidden
    color residue (e.g. [0,1,0,0]) under alpha=0; it is invisible but breaks
    exact comparisons and can bleed green fringes under texture filtering."""
    out = arr.copy()
    out[out[:, :, 3] == 0] = 0
    return out


def find_baseline(mask: np.ndarray) -> int | None:
    """Lowest row that holds a real foot (>= MIN_FOOT_WIDTH solid pixels),
    so a stray semi-transparent fringe pixel can't move the ground line."""
    widths = mask.sum(axis=1)
    rows = np.where(widths >= MIN_FOOT_WIDTH)[0]
    return int(rows[-1]) if len(rows) else None


def silhouette_top(mask: np.ndarray) -> int | None:
    rows = np.where(mask.any(axis=1))[0]
    return int(rows[0]) if len(rows) else None


def feet_center_x(mask: np.ndarray, top: int, baseline: int) -> float:
    """Center of mass of the bottom quarter of the silhouette (feet/pelvis).
    More stable than bbox center: an extended arm doesn't shift the anchor."""
    band_top = baseline - max(1, round((baseline - top) * 0.25))
    band = mask[band_top: baseline + 1]
    xs = np.where(band.any(axis=0))[0]
    if len(xs) == 0:
        xs = np.where(mask.any(axis=0))[0]
    return float(xs.mean())


def shift_clip(arr: np.ndarray, dx: int, dy: int) -> np.ndarray:
    """Translate a full-canvas RGBA array; pixels shifted outside are dropped."""
    h, w = arr.shape[:2]
    out = np.zeros_like(arr)
    src_x0, src_x1 = max(0, -dx), min(w, w - dx)
    src_y0, src_y1 = max(0, -dy), min(h, h - dy)
    if src_x0 >= src_x1 or src_y0 >= src_y1:
        return out
    out[src_y0 + dy: src_y1 + dy, src_x0 + dx: src_x1 + dx] = \
        arr[src_y0:src_y1, src_x0:src_x1]
    return out


def re_anchor(arr: np.ndarray, bottom_margin: int) -> tuple[np.ndarray, dict]:
    """Move the sprite so feet sit at a fixed baseline Y and the feet band is
    horizontally centered. This is what makes all 8 directions agree."""
    mask = solid_mask(arr)
    baseline = find_baseline(mask)
    top = silhouette_top(mask)
    if baseline is None or top is None:
        raise ValueError("empty sprite (no solid pixels)")

    target_baseline = CANVAS - 1 - bottom_margin
    dy = target_baseline - baseline
    dx = CANVAS // 2 - round(feet_center_x(mask, top, baseline))

    anchored = shift_clip(arr, dx, dy)
    info = {
        "shift": [dx, dy],
        "baseline_y": target_baseline,
        "anchor": {"x": CANVAS // 2, "y": target_baseline},
    }
    return anchored, info


def feet_split_x(mask: np.ndarray, baseline: int, band_h: int = 6) -> int:
    """X where the legs layer is cut into left/right. Looks at the bottom rows
    of the silhouette: if the two feet form separate column groups, cut through
    the widest gap between them (a centroid cut can put both feet on one side
    in 3/4 views, and lifting that side would break the baseline). Falls back
    to the feet-band centroid when feet overlap (profile views)."""
    band = mask[max(0, baseline - band_h + 1): baseline + 1]
    cols = band.any(axis=0)
    xs = np.where(cols)[0]
    if len(xs) == 0:
        return CANVAS // 2
    # widest run of empty columns strictly between the leftmost and rightmost feet pixels
    best_gap, best_mid = 0, None
    run_start = None
    for x in range(xs[0], xs[-1] + 1):
        if not cols[x]:
            if run_start is None:
                run_start = x
        elif run_start is not None:
            gap = x - run_start
            if gap > best_gap:
                best_gap, best_mid = gap, (run_start + x) // 2
            run_start = None
    if best_mid is not None and best_gap >= 2:
        return best_mid
    return int(round(xs.mean()))


def band_layer(arr: np.ndarray, row0: int, row1: int,
               col0: int = 0, col1: int = CANVAS) -> np.ndarray:
    """Copy of the canvas keeping only rows [row0, row1) and cols [col0, col1)."""
    out = np.zeros_like(arr)
    row0, row1 = max(0, row0), min(CANVAS, row1)
    col0, col1 = max(0, col0), min(CANVAS, col1)
    out[row0:row1, col0:col1] = arr[row0:row1, col0:col1]
    return out


def split_parts(arr: np.ndarray, head_frac: float,
                torso_frac: float) -> tuple[dict, dict]:
    """Cut the anchored sprite into paper-doll layers. Bands are strictly
    disjoint: every source pixel lands in exactly one part, so composing the
    parts at zero offsets reproduces the original pixel-for-pixel (an overlap
    would double-composite the ~600 semi-transparent edge pixels)."""
    mask = solid_mask(arr)
    top = silhouette_top(mask)
    baseline = find_baseline(mask)
    height = baseline - top + 1

    head_end = top + round(height * head_frac)
    torso_end = top + round(height * torso_frac)

    legs_cx = feet_split_x(mask, baseline)

    parts = {
        "head": band_layer(arr, 0, head_end),
        "torso": band_layer(arr, head_end, torso_end),
        "legs_left": band_layer(arr, torso_end, CANVAS, 0, legs_cx),
        "legs_right": band_layer(arr, torso_end, CANVAS, legs_cx, CANVAS),
    }
    meta = {
        "silhouette": {"top": top, "baseline": baseline, "height": height},
        "cuts": {"head_end": head_end, "torso_end": torso_end, "legs_split_x": legs_cx},
        "draw_order": ["legs_left", "legs_right", "torso", "head"],
    }
    return parts, meta


def compose(parts: dict, offsets: dict) -> Image.Image:
    """Stack part layers bottom-to-top with per-part (dx, dy) offsets."""
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    for name in ("legs_left", "legs_right", "torso", "head"):
        dx, dy = offsets.get(name, (0, 0))
        layer = Image.fromarray(shift_clip(parts[name], dx, dy))
        canvas = Image.alpha_composite(canvas, layer)
    return canvas


def squash_down(layer: np.ndarray, k: int, at_row: int) -> np.ndarray:
    """Compress a part vertically: rows above `at_row` shift down k px, rows
    below stay put. The k rows right above `at_row` (smooth waist shading)
    collapse. Unlike a plain shift, the part's bottom edge never moves, so the
    seam with the layer below (torso/legs crotch line) can't open a hole."""
    if k <= 0:
        return layer
    out = layer.copy()
    out[k:at_row] = layer[:at_row - k]
    out[:k] = 0
    return out


def torso_sink(parts: dict, k: int, head_end: int, torso_end: int) -> tuple[dict, dict]:
    """(offsets, replaced-layers) for 'chest sinks by k px': the head translates
    down, the torso squashes at the waist, hips and legs stay locked."""
    if k <= 0:
        return {}, {}
    waist = torso_end - (torso_end - head_end) // 3
    return {"head": (0, k)}, {"torso": squash_down(parts["torso"], k, waist)}


def build_idle(parts: dict, amp: int, head_end: int, torso_end: int,
               n_frames: int = 4) -> list[Image.Image]:
    """Breathing: chest and head sink and rise by up to `amp` px, hips and legs
    never move — the baseline and the crotch seam stay locked by construction."""
    if amp <= 1:
        pattern = [0, 1, 1, 0]
    else:
        pattern = [0, amp - 1, amp, amp - 1]
    frames = []
    for i in range(n_frames):
        offsets, replaced = torso_sink(parts, pattern[i % len(pattern)], head_end, torso_end)
        frames.append(compose({**parts, **replaced}, offsets))
    return frames


def part_bottom(layer: np.ndarray) -> int | None:
    """Lowest solid row of a single part layer (its own foot ground contact)."""
    mask = solid_mask(layer)
    rows = np.where(mask.sum(axis=1) >= 1)[0]
    return int(rows[-1]) if len(rows) else None


def stretch_down(layer: np.ndarray, k: int, at_row: int) -> np.ndarray:
    """Lengthen a leg by k px: everything below `at_row` shifts down, the gap is
    filled by repeating the row at `at_row` (a shin row — near-uniform shading,
    so the duplication is invisible). Unlike a plain shift, the top of the leg
    stays attached to the hip, so no gap opens under the torso."""
    if k <= 0:
        return layer
    out = layer.copy()
    out[at_row + k:] = layer[at_row: CANVAS - k]
    for i in range(k):
        out[at_row + i] = layer[at_row]
    return out


def grounded(parts: dict, leg: str, baseline: int, torso_end: int) -> np.ndarray:
    """Leg layer with its foot pressed to the baseline (weight transfer for 3/4
    views, where the far foot is drawn a couple px above the ground line)."""
    layer = parts[leg]
    bottom = part_bottom(layer)
    if bottom is None or bottom >= baseline:
        return layer
    shin_row = torso_end + 2 * (baseline - torso_end) // 3
    return stretch_down(layer, baseline - bottom, shin_row)


def build_walk(parts: dict, lift: int, bob: int, baseline: int,
               head_end: int, torso_end: int,
               direction: str = "") -> list[Image.Image]:
    """Eight-frame placeholder step cycle.

    The extra passing poses make diagonal/profile motion readable at the game's
    small render size. Profile views also receive a one-pixel upper-body sway;
    their legs overlap in the source image, so a vertical lift alone is nearly
    invisible.
    """
    half_lift = max(1, round(lift * 0.5))
    profile_sway = 1 if direction.startswith("full-") else 0
    phase_specs = [
        ("legs_left", lift, 0, profile_sway),
        ("legs_left", half_lift, 0, profile_sway),
        ("", 0, bob, 0),
        ("legs_right", half_lift, 0, -profile_sway),
        ("legs_right", lift, 0, -profile_sway),
        ("legs_right", half_lift, 0, -profile_sway),
        ("", 0, bob, 0),
        ("legs_left", half_lift, 0, profile_sway),
    ]
    frames = []
    for lifted_leg, leg_lift, body_bob, sway in phase_specs:
        offsets = {}
        replaced = {}
        if lifted_leg:
            grounded_leg = "legs_right" if lifted_leg == "legs_left" else "legs_left"
            offsets[lifted_leg] = (0, -leg_lift)
            replaced[grounded_leg] = grounded(
                parts, grounded_leg, baseline, torso_end)
        if body_bob:
            bob_offsets, bob_replaced = torso_sink(
                parts, body_bob, head_end, torso_end)
            offsets.update(bob_offsets)
            replaced.update(bob_replaced)
        if sway:
            head_dx, head_dy = offsets.get("head", (0, 0))
            offsets["head"] = (head_dx + sway, head_dy)
            offsets["torso"] = (sway, 0)
        layers = {**parts, **replaced}
        frames.append(compose(layers, offsets))
    return frames


# ─── VALIDATION ───────────────────────────────────────────────────────────────


def verify_split(source: np.ndarray, anchored: np.ndarray, parts: dict) -> dict:
    """Integrity of the split against the original image:
    - the anchor shift must not clip a single visible pixel;
    - parts composed at zero offsets must equal the anchored sprite exactly."""
    src_visible = int((source[:, :, 3] > 0).sum())
    anc_visible = int((anchored[:, :, 3] > 0).sum())

    recon = np.array(compose(parts, {}))
    diff_px = int((recon != anchored).any(axis=2).sum())

    return {
        "pixels_source": src_visible,
        "pixels_after_anchor": anc_visible,
        "pixels_clipped": src_visible - anc_visible,
        "reconstruction_diff_px": diff_px,
        "exact": src_visible == anc_visible and diff_px == 0,
    }


def measure(img: Image.Image) -> tuple[int, int, float]:
    """(baseline, top, feet_cx) of a frame for drift checks."""
    arr = np.array(img)
    mask = solid_mask(arr)
    baseline = find_baseline(mask)
    top = silhouette_top(mask)
    cx = feet_center_x(mask, top, baseline)
    return baseline, top, cx


def drift_report(all_frames: dict) -> list[str]:
    """all_frames: {(direction, anim): [Image, ...]} → human-readable drift table."""
    lines = ["direction    anim  baseline    top-drift  feet-cx-drift", "-" * 58]
    ok = True
    for (direction, anim), frames in sorted(all_frames.items()):
        ms = [measure(f) for f in frames]
        bottoms = [m[0] for m in ms]
        tops = [m[1] for m in ms]
        cxs = [m[2] for m in ms]
        b_drift = max(bottoms) - min(bottoms)
        flag = ""
        if b_drift > 0:
            flag = "  <-- BASELINE DRIFT"
            ok = False
        if max(cxs) - min(cxs) > 2:
            flag += "  <-- CX DRIFT"
            ok = False
        lines.append(
            f"{direction:12s} {anim:5s} y={min(bottoms)}-{max(bottoms)}"
            f"   {max(tops) - min(tops):>2d}px       {max(cxs) - min(cxs):>4.1f}px{flag}"
        )
    lines.append("")
    lines.append("OK: baseline locked in every animation" if ok
                 else "WARNING: drift detected, see flags above")
    return lines


# ─── PREVIEW ──────────────────────────────────────────────────────────────────


def make_preview(rows: list[tuple[str, list[Image.Image]]], scale: int = 2) -> Image.Image:
    """Contact sheet on a dark checkerboard: one row per direction."""
    cell = CANVAS * scale
    label_w = 110
    n_cols = max(len(frames) for _, frames in rows)
    sheet = Image.new("RGBA", (label_w + n_cols * cell, len(rows) * cell), (40, 40, 46, 255))
    draw = ImageDraw.Draw(sheet)
    # checkerboard so transparency is visible
    for y in range(0, sheet.height, 16):
        for x in range(label_w, sheet.width, 16):
            if (x // 16 + y // 16) % 2 == 0:
                draw.rectangle([x, y, x + 15, y + 15], fill=(52, 52, 60, 255))
    for r, (label, frames) in enumerate(rows):
        draw.text((8, r * cell + cell // 2 - 6), label, fill=(230, 230, 230, 255))
        for c, frame in enumerate(frames):
            big = frame.resize((cell, cell), Image.NEAREST)
            sheet.alpha_composite(big, (label_w + c * cell, r * cell))
    return sheet


# ─── MAIN ─────────────────────────────────────────────────────────────────────


def process_direction(path: Path, out_root: Path, args) -> tuple[str, dict, list, list]:
    direction = canon_direction(path.stem)
    img = Image.open(path).convert("RGBA")
    if img.size != (CANVAS, CANVAS):
        print(f"  Resizing {path.name}: {img.size} -> {CANVAS}x{CANVAS}")
        img = img.resize((CANVAS, CANVAS), Image.NEAREST)

    arr = sanitize(np.array(img))
    anchored, anchor_info = re_anchor(arr, args.bottom_margin)
    parts, meta = split_parts(anchored, args.head_frac, args.torso_frac)
    meta.update(anchor_info)
    meta["integrity"] = verify_split(arr, anchored, parts)

    parts_dir = out_root / "parts" / direction
    parts_dir.mkdir(parents=True, exist_ok=True)
    for name, layer in parts.items():
        Image.fromarray(layer).save(parts_dir / f"{name}.png")
    with open(parts_dir / "parts.json", "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

    head_end, torso_end = meta["cuts"]["head_end"], meta["cuts"]["torso_end"]
    idle = build_idle(parts, args.idle_amp, head_end, torso_end)
    walk = build_walk(parts, args.walk_lift, args.walk_bob,
                      meta["baseline_y"], head_end, torso_end, direction)

    frames_dir = out_root / "frames" / direction
    frames_dir.mkdir(parents=True, exist_ok=True)
    for i, frame in enumerate(idle, 1):
        frame.save(frames_dir / f"idle_{i:02d}.png")
    for i, frame in enumerate(walk, 1):
        frame.save(frames_dir / f"walk_{i:02d}.png")

    integrity = meta["integrity"]
    integrity_note = "parts reassemble EXACTLY" if integrity["exact"] else (
        f"INTEGRITY FAIL: clipped={integrity['pixels_clipped']}px, "
        f"recon diff={integrity['reconstruction_diff_px']}px")
    print(f"  {direction:12s} baseline y={meta['baseline_y']}, "
          f"cuts head/torso={meta['cuts']['head_end']}, torso/legs={meta['cuts']['torso_end']}, "
          f"shift={meta['shift']}, {integrity_note}")
    return direction, meta, idle, walk


def run(input_dir: Path, out_root: Path, args) -> bool:
    """Full pipeline over a folder of normalized 128x128 direction sprites.
    `args` is any object with bottom_margin / head_frac / torso_frac /
    idle_amp / walk_lift / walk_bob attributes. Returns True when every
    integrity and drift check passed."""
    out_root.mkdir(parents=True, exist_ok=True)

    selected = getattr(args, "directions", None)
    selected_directions = (
        {canon_direction(item) for item in selected.split(",") if item.strip()}
        if selected else None
    )
    pngs = [
        path for path in sorted(input_dir.glob("*.png"))
        if selected_directions is None
        or canon_direction(path.stem) in selected_directions
    ]
    if not pngs:
        print(f"Error: no PNG files in {input_dir}")
        return False

    print(f"Input:  {input_dir}  ({len(pngs)} sprites)")
    print(f"Output: {out_root}")

    all_frames: dict = {}
    preview_rows: list = []
    integrity: dict = {}
    for path in pngs:
        direction = canon_direction(path.stem)
        if direction not in KNOWN_DIRECTIONS:
            print(f"  Skipping {path.name}: '{direction}' is not a known direction")
            continue
        direction, meta, idle, walk = process_direction(path, out_root, args)
        all_frames[(direction, "idle")] = idle
        all_frames[(direction, "walk")] = walk
        integrity[direction] = meta["integrity"]
        static = Image.open(path).convert("RGBA")
        preview_rows.append((direction, [static] + idle + walk))

    if not all_frames:
        print("Error: nothing processed.")
        return False

    report = ["SPLIT INTEGRITY (parts vs original)", "-" * 58]
    for direction, res in sorted(integrity.items()):
        status = "EXACT" if res["exact"] else (
            f"FAIL (clipped {res['pixels_clipped']}px, recon diff {res['reconstruction_diff_px']}px)")
        report.append(f"{direction:12s} {res['pixels_source']:5d} px -> {status}")
    report += ["", "FRAME DRIFT"] + drift_report(all_frames)
    report_path = out_root / "report.txt"
    report_path.write_text("\n".join(report), encoding="utf-8")
    print()
    print("\n".join(report))

    preview = make_preview(preview_rows)
    preview_path = out_root / "preview.png"
    preview.save(preview_path)
    print(f"\nPreview: {preview_path}")
    print(f"Frames layout matches the game loader — copy {out_root / 'frames'} "
          f"over assets/sprites/characters/base/frames/ when satisfied.")

    all_exact = all(res["exact"] for res in integrity.values())
    no_drift = "WARNING" not in "\n".join(report)
    return all_exact and no_drift


def main():
    parser = argparse.ArgumentParser(
        description="Split static direction sprites into parts and build test animations.")
    parser.add_argument("input_dir", type=Path, help="Folder with <direction>.png files")
    parser.add_argument("--out", type=Path, default=None,
                        help="Output folder (default: <input_dir>/../_animation_out)")
    parser.add_argument("--bottom-margin", type=int, default=8)
    parser.add_argument("--head-frac", type=float, default=0.30)
    parser.add_argument("--torso-frac", type=float, default=0.62)
    parser.add_argument("--idle-amp", type=int, default=2)
    parser.add_argument("--walk-lift", type=int, default=2)
    parser.add_argument("--walk-bob", type=int, default=1)
    parser.add_argument(
        "--directions",
        default="",
        help="Optional comma-separated subset, e.g. back,front-right,full-right",
    )
    args = parser.parse_args()

    if not args.input_dir.is_dir():
        print(f"Error: not a directory: {args.input_dir}")
        sys.exit(1)

    out_root = args.out or (args.input_dir.parent / "_animation_out")
    run(args.input_dir, out_root, args)


if __name__ == "__main__":
    main()
