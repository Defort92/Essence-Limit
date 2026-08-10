"""Build synchronized 128x128 equipment overlay frames for the base character.

The optional source image is cropped to its alpha bounds and converted into a
small pixel-art master first. Subsequent runs can rebuild the animation frames
directly from ``assets/sprites/equipment/<weapon_id>/master.png``.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

from build_iron_sword_layers import BASE_FRAMES, DIRECTIONS, POSES


ROOT = Path(__file__).resolve().parents[1]
EQUIPMENT_ROOT = ROOT / "assets/sprites/equipment"


def _prepare_master(
    source_path: Path,
    master_path: Path,
    target_width: int,
    target_height: int,
) -> None:
    source = Image.open(source_path).convert("RGBA")
    bbox = source.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError(f"Weapon source has no visible pixels: {source_path}")
    cropped = source.crop(bbox)
    scale = min(target_width / cropped.width, target_height / cropped.height)
    size = (
        max(1, round(cropped.width * scale)),
        max(1, round(cropped.height * scale)),
    )
    master = cropped.resize(size, Image.Resampling.NEAREST)
    # Equipment frames use hard pixel edges; discard the soft chroma-key matte
    # after the large source has been reduced to its in-game dimensions.
    alpha = master.getchannel("A").point(lambda value: 255 if value >= 96 else 0)
    master.putalpha(alpha)
    master_path.parent.mkdir(parents=True, exist_ok=True)
    master.save(master_path, optimize=True)


def _rotated_weapon(master: Image.Image, angle: float, grip_y: int) -> Image.Image:
    canvas = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    grip_anchor = (master.width // 2, grip_y)
    pivot = (64, 64)
    canvas.alpha_composite(
        master,
        (pivot[0] - grip_anchor[0], pivot[1] - grip_anchor[1]),
    )
    return canvas.rotate(
        angle,
        resample=Image.Resampling.NEAREST,
        center=pivot,
    )


def _make_layer(
    master: Image.Image,
    pose: tuple[int, int, float],
    grip_y: int,
) -> Image.Image:
    hand_x, hand_y, angle = pose
    rotated = _rotated_weapon(master, angle, grip_y)
    layer = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    layer.alpha_composite(rotated, (hand_x - 64, hand_y - 64))
    # Let the body's glove close around the weapon instead of drawing the grip
    # over the hand. Keep the opening small enough for narrow staff shafts.
    draw = ImageDraw.Draw(layer)
    draw.rectangle(
        (hand_x - 1, hand_y - 2, hand_x + 1, hand_y + 1),
        fill=(0, 0, 0, 0),
    )
    return layer


def _base_frame_path(direction: str, animation: str, index: int) -> Path:
    return BASE_FRAMES / direction / animation / "default" / f"frame_{index:02}.png"


def build(
    weapon_id: str,
    grip_y: int,
    source_path: Path | None,
    target_width: int,
    target_height: int,
) -> None:
    weapon_root = EQUIPMENT_ROOT / weapon_id
    master_path = weapon_root / "master.png"
    output_frames = weapon_root / "frames"
    preview_path = weapon_root / f"{weapon_id}_animation_preview.png"

    if source_path is not None:
        _prepare_master(
            source_path,
            master_path,
            target_width,
            target_height,
        )
    if not master_path.is_file():
        raise FileNotFoundError(
            f"Missing {master_path}; pass --source to create it first."
        )

    master = Image.open(master_path).convert("RGBA")
    if master.getbbox() is None:
        raise ValueError(f"Weapon master has no visible pixels: {master_path}")
    if grip_y < 0 or grip_y >= master.height:
        raise ValueError(f"Grip y={grip_y} is outside master height {master.height}.")

    output_frames.mkdir(parents=True, exist_ok=True)
    for old_frame in output_frames.rglob("*.png"):
        old_frame.unlink()

    preview = Image.new(
        "RGBA",
        (12 * 128, len(DIRECTIONS) * 148),
        (28, 24, 29, 255),
    )
    preview_draw = ImageDraw.Draw(preview)

    frame_count = 0
    for row, direction in enumerate(DIRECTIONS):
        preview_draw.text(
            (4, row * 148 + 2),
            f"{direction}: idle 1-4 | run 1-8",
            fill=(235, 218, 170, 255),
        )
        column = 0
        for animation, poses in POSES[direction].items():
            output_dir = output_frames / direction / animation / "default"
            output_dir.mkdir(parents=True, exist_ok=True)
            for index, pose in enumerate(poses, start=1):
                layer = _make_layer(master, pose, grip_y)
                layer.save(output_dir / f"frame_{index:02}.png", optimize=True)

                body = Image.open(
                    _base_frame_path(direction, animation, index)
                ).convert("RGBA")
                preview.alpha_composite(
                    Image.alpha_composite(body, layer),
                    (column * 128, row * 148 + 20),
                )
                column += 1
                frame_count += 1

    preview_path.parent.mkdir(parents=True, exist_ok=True)
    preview.save(preview_path, optimize=True)
    print(f"Built {frame_count} weapon frames in {output_frames}")
    print(f"Master: {master_path} ({master.width}x{master.height}, grip y={grip_y})")
    print(f"Preview: {preview_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build idle/run overlay frames for a weapon master sprite."
    )
    parser.add_argument("weapon_id", help="Equipment asset folder name")
    parser.add_argument("--grip-y", type=int, required=True)
    parser.add_argument(
        "--source",
        type=Path,
        help="Optional transparent source image used to create master.png",
    )
    parser.add_argument("--target-width", type=int, default=24)
    parser.add_argument("--target-height", type=int, default=60)
    args = parser.parse_args()

    build(
        args.weapon_id,
        args.grip_y,
        args.source,
        args.target_width,
        args.target_height,
    )


if __name__ == "__main__":
    main()
