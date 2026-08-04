from pathlib import Path
import shutil

from PIL import Image, ImageDraw


PAIR_SOURCE = Path("tmp/imagegen/run_forward_v5_leg_pair_alpha.png")
SOURCE_DIR = Path("assets/sprites/characters/base/frames/front/run_v4")
OUTPUT_DIR = Path("assets/sprites/characters/base/frames/front/run_v5")
FRAME_SIZE = 128
TARGET_HEIGHT = 116
BOTTOM_Y = 118


def prepare_generated_pair() -> tuple[Image.Image, Image.Image]:
    source = Image.open(PAIR_SOURCE).convert("RGBA")
    middle = source.width // 2
    cells = (source.crop((0, 0, middle, source.height)), source.crop((middle, 0, source.width, source.height)))
    prepared: list[Image.Image] = []

    for cell in cells:
        bbox = cell.getbbox()
        if bbox is None:
            raise RuntimeError("Generated correction cell is empty")
        sprite = cell.crop(bbox)
        width = round(sprite.width * TARGET_HEIGHT / sprite.height)
        sprite = sprite.resize((width, TARGET_HEIGHT), Image.Resampling.NEAREST)
        frame = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        frame.alpha_composite(sprite, ((FRAME_SIZE - width) // 2, BOTTOM_Y - TARGET_HEIGHT))
        prepared.append(frame)

    return prepared[0], prepared[1]


def replace_raised_leg(original: Image.Image, generated: Image.Image, left_side: bool) -> Image.Image:
    # Limit the edit to the raised thigh, shin, and boot. Everything outside
    # this polygon comes directly from run_v4 without any redraw.
    left_polygon = [(36, 59), (66, 59), (66, 72), (61, 83), (59, 104), (36, 104)]
    polygon = left_polygon if left_side else [(FRAME_SIZE - x, y) for x, y in left_polygon]

    region_mask = Image.new("L", original.size, 0)
    ImageDraw.Draw(region_mask).polygon(polygon, fill=255)

    generated_alpha = generated.getchannel("A")
    paste_mask = Image.new("L", original.size, 0)
    paste_mask.paste(generated_alpha)
    paste_mask = Image.composite(paste_mask, Image.new("L", original.size, 0), region_mask)

    result = original.copy()
    transparent = Image.new("RGBA", original.size, (0, 0, 0, 0))
    result.paste(transparent, (0, 0), region_mask)
    result.paste(generated, (0, 0), paste_mask)
    return result


def match_original_palette(generated: Image.Image, original: Image.Image) -> Image.Image:
    palette = sorted({pixel[:3] for pixel in original.getdata() if pixel[3] >= 192})
    cache: dict[tuple[int, int, int], tuple[int, int, int]] = {}
    matched = Image.new("RGBA", generated.size, (0, 0, 0, 0))
    output_pixels = []
    for red, green, blue, alpha in generated.getdata():
        if alpha == 0:
            output_pixels.append((0, 0, 0, 0))
            continue
        color = (red, green, blue)
        nearest = cache.get(color)
        if nearest is None:
            nearest = min(
                palette,
                key=lambda candidate: (
                    (candidate[0] - red) ** 2
                    + (candidate[1] - green) ** 2
                    + (candidate[2] - blue) ** 2
                ),
            )
            cache[color] = nearest
        output_pixels.append((*nearest, alpha))
    matched.putdata(output_pixels)
    return matched


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for index in range(1, 9):
        shutil.copy2(SOURCE_DIR / f"run_{index:02d}.png", OUTPUT_DIR / f"run_{index:02d}.png")

    generated_four, generated_eight = prepare_generated_pair()
    frame_four = Image.open(SOURCE_DIR / "run_04.png").convert("RGBA")
    frame_eight = Image.open(SOURCE_DIR / "run_08.png").convert("RGBA")
    generated_four = match_original_palette(generated_four, frame_four)
    generated_eight = match_original_palette(generated_eight, frame_eight)
    replace_raised_leg(frame_four, generated_four, left_side=True).save(OUTPUT_DIR / "run_04.png", optimize=True)
    replace_raised_leg(frame_eight, generated_eight, left_side=False).save(OUTPUT_DIR / "run_08.png", optimize=True)

    frames = [Image.open(OUTPUT_DIR / f"run_{index:02d}.png").convert("RGBA") for index in range(1, 9)]
    strip = Image.new("RGBA", (FRAME_SIZE * 8, FRAME_SIZE), (0, 0, 0, 0))
    grid = Image.new("RGBA", (FRAME_SIZE * 4, FRAME_SIZE * 2), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME_SIZE, 0))
        grid.alpha_composite(frame, ((index % 4) * FRAME_SIZE, (index // 4) * FRAME_SIZE))
    strip.save(OUTPUT_DIR / "run_forward_v5_strip_8x1.png", optimize=True)
    grid.save(OUTPUT_DIR / "run_forward_v5_grid_4x2.png", optimize=True)

    preview = [frame.resize((512, 512), Image.Resampling.NEAREST) for frame in frames]
    preview[0].save(
        OUTPUT_DIR / "run_forward_v5_preview.gif",
        save_all=True,
        append_images=preview[1:],
        duration=95,
        loop=0,
        disposal=2,
    )


if __name__ == "__main__":
    main()
