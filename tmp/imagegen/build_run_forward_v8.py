from pathlib import Path

from PIL import Image


SOURCE_PATTERN = "tmp/imagegen/run_forward_v8_phase_{index:02d}_alpha.png"
PALETTE_SOURCE = Path("assets/sprites/characters/base/front.png")
OUTPUT_DIR = Path("assets/sprites/characters/base/frames/front/run_v8")
FRAME_SIZE = 128

# All four generations use the same 1254x1254 canvas. Keeping one fixed crop
# preserves the authored compression and flight height instead of normalizing
# every silhouette to the same total height.
SOURCE_CROP = (340, 60, 914, 1120)
TARGET_CROP_SIZE = (63, 116)
TARGET_POSITION = ((FRAME_SIZE - TARGET_CROP_SIZE[0]) // 2, 4)


def match_project_palette(image: Image.Image, palette_source: Image.Image) -> Image.Image:
    palette = sorted({pixel[:3] for pixel in palette_source.get_flattened_data() if pixel[3] >= 192})
    cache: dict[tuple[int, int, int], tuple[int, int, int]] = {}
    output = []
    for red, green, blue, alpha in image.get_flattened_data():
        if alpha < 24:
            output.append((0, 0, 0, 0))
            continue
        color = (red, green, blue)
        if color not in cache:
            cache[color] = min(
                palette,
                key=lambda candidate: sum((candidate[channel] - color[channel]) ** 2 for channel in range(3)),
            )
        output.append((*cache[color], 255 if alpha >= 224 else alpha))
    result = Image.new("RGBA", image.size)
    result.putdata(output)
    return result


def prepare_phase(index: int, palette_source: Image.Image) -> Image.Image:
    source = Image.open(SOURCE_PATTERN.format(index=index)).convert("RGBA")
    sprite = source.crop(SOURCE_CROP).resize(TARGET_CROP_SIZE, Image.Resampling.NEAREST)
    sprite = match_project_palette(sprite, palette_source)
    frame = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    frame.alpha_composite(sprite, TARGET_POSITION)
    return frame


def main() -> None:
    palette_source = Image.open(PALETTE_SOURCE).convert("RGBA")
    first_half = [prepare_phase(index, palette_source) for index in range(1, 5)]
    second_half = [frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for frame in first_half]
    frames = first_half + second_half

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(frames, start=1):
        frame.save(OUTPUT_DIR / f"run_{index:02d}.png", optimize=True)

    strip = Image.new("RGBA", (FRAME_SIZE * 8, FRAME_SIZE), (0, 0, 0, 0))
    grid = Image.new("RGBA", (FRAME_SIZE * 4, FRAME_SIZE * 2), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME_SIZE, 0))
        grid.alpha_composite(frame, ((index % 4) * FRAME_SIZE, (index // 4) * FRAME_SIZE))
    strip.save(OUTPUT_DIR / "run_forward_v8_strip_8x1.png", optimize=True)
    grid.save(OUTPUT_DIR / "run_forward_v8_grid_4x2.png", optimize=True)

    preview = [frame.resize((512, 512), Image.Resampling.NEAREST) for frame in frames]
    preview[0].save(
        OUTPUT_DIR / "run_forward_v8_preview.gif",
        save_all=True,
        append_images=preview[1:],
        duration=90,
        loop=0,
        disposal=2,
    )


if __name__ == "__main__":
    main()
