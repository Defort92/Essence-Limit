from pathlib import Path

from PIL import Image


SOURCE = Path("tmp/imagegen/back_run_v1_source_alpha.png")
OUTPUT_DIR = Path("assets/sprites/characters/base/frames/back/run_v1")
FRAME_SIZE = 128
SOURCE_CROP = (75, 145, 360, 700)
TARGET_CROP_SIZE = (60, 116)
TARGET_POSITION = ((FRAME_SIZE - TARGET_CROP_SIZE[0]) // 2, 4)


def extract_first_half(source: Image.Image) -> list[Image.Image]:
    frames: list[Image.Image] = []
    for index in range(4):
        left = round(source.width * index / 4)
        right = round(source.width * (index + 1) / 4)
        cell = source.crop((left, 0, right, source.height))
        sprite = cell.crop(SOURCE_CROP).resize(TARGET_CROP_SIZE, Image.Resampling.NEAREST)
        frame = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        frame.alpha_composite(sprite, TARGET_POSITION)
        frames.append(frame)
    return frames


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    first_half = extract_first_half(source)
    opposite_half = [frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for frame in first_half]
    frames = first_half + opposite_half

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(frames, start=1):
        frame.save(OUTPUT_DIR / f"run_{index:02d}.png", optimize=True)

    strip = Image.new("RGBA", (FRAME_SIZE * 8, FRAME_SIZE), (0, 0, 0, 0))
    grid = Image.new("RGBA", (FRAME_SIZE * 4, FRAME_SIZE * 2), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME_SIZE, 0))
        grid.alpha_composite(frame, ((index % 4) * FRAME_SIZE, (index // 4) * FRAME_SIZE))
    strip.save(OUTPUT_DIR / "back_run_v1_strip_8x1.png", optimize=True)
    grid.save(OUTPUT_DIR / "back_run_v1_grid_4x2.png", optimize=True)

    preview = [frame.resize((512, 512), Image.Resampling.NEAREST) for frame in frames]
    preview[0].save(
        OUTPUT_DIR / "back_run_v1_preview.gif",
        save_all=True,
        append_images=preview[1:],
        duration=90,
        loop=0,
        disposal=2,
    )


if __name__ == "__main__":
    main()
