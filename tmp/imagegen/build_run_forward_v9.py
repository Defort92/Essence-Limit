from pathlib import Path

from PIL import Image


SOURCE = Path("tmp/imagegen/run_forward_v9_alpha.png")
PALETTE_SOURCE = Path("assets/sprites/characters/base/front.png")
OUTPUT_DIR = Path("assets/sprites/characters/base/frames/front/run_v9")
FRAME_SIZE = 128


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


def split_grid(source: Image.Image, palette_source: Image.Image) -> list[Image.Image]:
    frames: list[Image.Image] = []
    for row in range(2):
        top = round(source.height * row / 2)
        bottom = round(source.height * (row + 1) / 2)
        for column in range(4):
            left = round(source.width * column / 4)
            right = round(source.width * (column + 1) / 4)
            cell = source.crop((left, top, right, bottom))
            cell = cell.resize((FRAME_SIZE, FRAME_SIZE), Image.Resampling.NEAREST)
            frames.append(match_project_palette(cell, palette_source))
    return frames


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    palette_source = Image.open(PALETTE_SOURCE).convert("RGBA")
    frames = split_grid(source, palette_source)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(frames, start=1):
        frame.save(OUTPUT_DIR / f"run_{index:02d}.png", optimize=True)

    strip = Image.new("RGBA", (FRAME_SIZE * 8, FRAME_SIZE), (0, 0, 0, 0))
    grid = Image.new("RGBA", (FRAME_SIZE * 4, FRAME_SIZE * 2), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME_SIZE, 0))
        grid.alpha_composite(frame, ((index % 4) * FRAME_SIZE, (index // 4) * FRAME_SIZE))
    strip.save(OUTPUT_DIR / "run_forward_v9_strip_8x1.png", optimize=True)
    grid.save(OUTPUT_DIR / "run_forward_v9_grid_4x2.png", optimize=True)

    preview = [frame.resize((512, 512), Image.Resampling.NEAREST) for frame in frames]
    preview[0].save(
        OUTPUT_DIR / "run_forward_v9_preview.gif",
        save_all=True,
        append_images=preview[1:],
        duration=90,
        loop=0,
        disposal=2,
    )


if __name__ == "__main__":
    main()
