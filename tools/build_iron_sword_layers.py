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
# The master points down: about -135 degrees raises the tip up-left, +135 up-right.
POSES: dict[str, dict[str, list[tuple[int, int, float]]]] = {
    "front": {
        "idle": [(41, 81, -48), (40, 80, -46), (41, 79, -50), (40, 80, -47)],
        "run": [
            (48, 56, -140), (48, 72, -132), (50, 56, -145), (55, 51, -136),
            (42, 67, -128), (48, 70, -134), (48, 65, -142), (54, 51, -136),
        ],
    },
    "front-right": {
        "idle": [(43, 79, -54), (43, 78, -51), (43, 77, -56), (43, 78, -53)],
        "run": [
            (42, 70, 132), (51, 65, 139), (43, 70, 135), (55, 53, 145),
            (41, 70, 128), (50, 58, 141), (42, 69, 134), (54, 54, 144),
        ],
    },
    "full-right": {
        "idle": [(58, 79, -46), (58, 78, -43), (58, 77, -48), (58, 78, -45)],
        "run": [
            (58, 65, 132), (61, 64, 138), (60, 62, 142), (61, 58, 136),
            (58, 65, 128), (63, 64, 137), (60, 61, 144), (61, 58, 135),
        ],
    },
    "rear-right": {
        "idle": [(85, 80, 47), (85, 79, 44), (85, 78, 49), (85, 79, 46)],
        "run": [
            (85, 59, 136), (84, 59, 142), (86, 62, 132), (82, 55, 145),
            (85, 60, 134), (86, 59, 140), (85, 62, 130), (83, 56, 144),
        ],
    },
    "back": {
        "idle": [(87, 81, 45), (87, 80, 42), (87, 79, 47), (87, 80, 44)],
        "run": [
            (87, 54, 138), (84, 63, 132), (88, 63, 135), (83, 53, 145),
            (87, 57, 136), (86, 61, 130), (88, 64, 134), (84, 53, 143),
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
    # The body sprite remains visible through this small opening, so the glove
    # closes around the grip instead of the weapon looking pasted over the hand.
    draw = ImageDraw.Draw(layer)
    draw.rectangle((hand_x - 2, hand_y - 3, hand_x + 2, hand_y + 2), fill=(0, 0, 0, 0))
    return layer


def _base_frame_path(direction: str, animation: str, index: int) -> Path:
    return BASE_FRAMES / direction / animation / "default" / f"frame_{index:02}.png"


def build() -> None:
    master = Image.open(MASTER_PATH).convert("RGBA")
    if master.getbbox() is None:
        raise ValueError(f"Weapon master has no visible pixels: {MASTER_PATH}")

    # Keep Godot's sibling .import files intact; regenerated frame paths are stable.
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
            output_dir = OUTPUT_FRAMES / direction / animation / "default"
            output_dir.mkdir(parents=True, exist_ok=True)
            for index, pose in enumerate(poses, start=1):
                layer = _make_layer(master, pose)
                layer.save(output_dir / f"frame_{index:02}.png", optimize=True)

                body = Image.open(_base_frame_path(direction, animation, index)).convert("RGBA")
                composite = Image.alpha_composite(body, layer)
                preview.alpha_composite(composite, (column * 128, row * 148 + 20))
                column += 1

    PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
    preview.save(PREVIEW_PATH, optimize=True)
    print(f"Built {len(DIRECTIONS) * 12} weapon frames in {OUTPUT_FRAMES}")
    print(f"Preview: {PREVIEW_PATH}")


if __name__ == "__main__":
    build()
