"""Build synchronized 128x128 iron-sword overlay frames for the base character."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
BASE_FRAMES = ROOT / "assets/sprites/characters/base/frames"
EQUIPMENT_ROOT = ROOT / "assets/sprites/equipment/iron_sword"
OUTPUT_FRAMES = EQUIPMENT_ROOT / "frames"
MASTER_PATH = EQUIPMENT_ROOT / "master.png"
PREVIEW_PATH = EQUIPMENT_ROOT / "iron_sword_animation_preview.png"

DIRECTIONS = ("front", "front-right", "full-right", "rear-right", "back")

# Attachment point of the character's weapon hand in each 128x128 source frame.
# Angles are measured from a blade pointing straight down; negative angles trail left.
POSES: dict[str, dict[str, list[tuple[int, int, float]]]] = {
    "front": {
        "idle": [(41, 81, -18), (40, 80, -18), (41, 79, -18), (40, 80, -18)],
        "run": [
            (48, 56, -38), (48, 72, -24), (50, 56, -38), (55, 51, -42),
            (42, 67, -30), (48, 70, -25), (48, 65, -30), (54, 51, -42),
        ],
    },
    "front-right": {
        "idle": [(43, 79, -28), (43, 78, -28), (43, 77, -28), (43, 78, -28)],
        "run": [
            (42, 70, -42), (51, 65, -38), (43, 70, -42), (55, 53, -48),
            (41, 70, -42), (50, 58, -44), (42, 69, -42), (54, 54, -48),
        ],
    },
    "full-right": {
        "idle": [(58, 79, -25), (58, 78, -25), (58, 77, -25), (58, 78, -25)],
        "run": [
            (82, 58, -48), (68, 64, -42), (83, 59, -48), (76, 55, -46),
            (81, 58, -48), (67, 64, -42), (82, 59, -48), (76, 55, -46),
        ],
    },
    "rear-right": {
        "idle": [(85, 80, 22), (85, 79, 22), (85, 78, 22), (85, 79, 22)],
        "run": [
            (85, 59, 36), (84, 59, 34), (86, 62, 32), (82, 55, 38),
            (85, 60, 34), (86, 59, 36), (85, 62, 32), (83, 56, 38),
        ],
    },
    "back": {
        "idle": [(87, 81, 18), (87, 80, 18), (87, 79, 18), (87, 80, 18)],
        "run": [
            (87, 54, 34), (84, 63, 28), (88, 63, 28), (83, 53, 36),
            (87, 57, 32), (86, 61, 30), (88, 64, 28), (84, 53, 36),
        ],
    },
}


def _rotated_weapon(master: Image.Image, angle: float) -> Image.Image:
    canvas = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    # The hand closes around the upper third of the leather grip.
    grip_anchor = (master.width // 2, 8)
    pivot = (64, 64)
    canvas.alpha_composite(master, (pivot[0] - grip_anchor[0], pivot[1] - grip_anchor[1]))
    return canvas.rotate(angle, resample=Image.Resampling.NEAREST, center=pivot)


def _make_layer(master: Image.Image, pose: tuple[int, int, float]) -> Image.Image:
    hand_x, hand_y, angle = pose
    rotated = _rotated_weapon(master, angle)
    layer = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    layer.alpha_composite(rotated, (hand_x - 64, hand_y - 64))
    return layer


def _base_frame_path(direction: str, animation: str, index: int) -> Path:
    if animation == "idle":
        return BASE_FRAMES / direction / f"idle_{index:02}.png"
    run_dir = (
        BASE_FRAMES / direction / "run_v10_source_exact"
        if direction == "front"
        else BASE_FRAMES / direction / "run_v1"
    )
    return run_dir / f"run_{index:02}.png"


def build() -> None:
    master = Image.open(MASTER_PATH).convert("RGBA")
    if master.getbbox() is None:
        raise ValueError(f"Weapon master has no visible pixels: {MASTER_PATH}")

    # Keep Godot's sibling .import files intact on rebuild; frame names are stable.
    OUTPUT_FRAMES.mkdir(parents=True, exist_ok=True)
    for old_frame in OUTPUT_FRAMES.rglob("*.png"):
        old_frame.unlink()

    preview = Image.new("RGBA", (12 * 128, len(DIRECTIONS) * 148), (28, 24, 29, 255))
    preview_draw = ImageDraw.Draw(preview)

    for row, direction in enumerate(DIRECTIONS):
        preview_draw.text(
            (4, row * 148 + 2),
            f"{direction}: idle 1-4 | run 1-8",
            fill=(235, 218, 170, 255),
        )
        column = 0
        for animation, poses in POSES[direction].items():
            output_dir = OUTPUT_FRAMES / direction
            output_dir.mkdir(parents=True, exist_ok=True)
            for index, pose in enumerate(poses, start=1):
                layer = _make_layer(master, pose)
                layer.save(output_dir / f"{animation}_{index:02}.png", optimize=True)

                body = Image.open(_base_frame_path(direction, animation, index)).convert("RGBA")
                composite = Image.alpha_composite(layer, body)
                preview.alpha_composite(composite, (column * 128, row * 148 + 20))
                column += 1

    PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
    preview.save(PREVIEW_PATH, optimize=True)
    print(f"Built {len(DIRECTIONS) * 12} weapon frames in {OUTPUT_FRAMES}")
    print(f"Preview: {PREVIEW_PATH}")


if __name__ == "__main__":
    build()
