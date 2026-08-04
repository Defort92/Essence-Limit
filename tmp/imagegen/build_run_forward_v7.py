from pathlib import Path

from PIL import Image


SOURCE = Path("tmp/imagegen/run_forward_v7_half_alpha.png")
PALETTE_SOURCE = Path("assets/sprites/characters/base/front.png")
OUTPUT_DIR = Path("assets/sprites/characters/base/frames/front/run_v7")
FRAME_SIZE = 128
TARGET_HEIGHT = 116
BOTTOM_Y = 121


def split_half_cycle(source: Image.Image) -> list[Image.Image]:
    frames: list[Image.Image] = []
    for index in range(4):
        left = round(source.width * index / 4)
        right = round(source.width * (index + 1) / 4)
        cell = source.crop((left, 0, right, source.height))
        bbox = cell.getbbox()
        if bbox is None:
            raise RuntimeError(f"Generated cell {index + 1} is empty")
        frames.append(cell.crop(bbox))
    return frames


def fit_to_frame(sprite: Image.Image) -> Image.Image:
    width = round(sprite.width * TARGET_HEIGHT / sprite.height)
    sprite = sprite.resize((width, TARGET_HEIGHT), Image.Resampling.NEAREST)
    frame = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    frame.alpha_composite(sprite, ((FRAME_SIZE - width) // 2, BOTTOM_Y - TARGET_HEIGHT))
    return frame


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


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    palette_source = Image.open(PALETTE_SOURCE).convert("RGBA")
    first_half = [match_project_palette(fit_to_frame(sprite), palette_source) for sprite in split_half_cycle(source)]
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
    strip.save(OUTPUT_DIR / "run_forward_v7_strip_8x1.png", optimize=True)
    grid.save(OUTPUT_DIR / "run_forward_v7_grid_4x2.png", optimize=True)

    preview = [frame.resize((512, 512), Image.Resampling.NEAREST) for frame in frames]
    preview[0].save(
        OUTPUT_DIR / "run_forward_v7_preview.gif",
        save_all=True,
        append_images=preview[1:],
        duration=90,
        loop=0,
        disposal=2,
    )


if __name__ == "__main__":
    main()
