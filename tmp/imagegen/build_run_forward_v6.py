from pathlib import Path
import shutil

from PIL import Image, ImageDraw


PAIR_SOURCE = Path("tmp/imagegen/run_forward_v6_leg_pair_alpha.png")
SOURCE_DIR = Path("assets/sprites/characters/base/frames/front/run_v4")
OUTPUT_DIR = Path("assets/sprites/characters/base/frames/front/run_v6")
FRAME_SIZE = 128
TARGET_HEIGHT = 116
BOTTOM_Y = 118


def prepare_pair() -> tuple[Image.Image, Image.Image]:
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


def match_palette(generated: Image.Image, original: Image.Image) -> Image.Image:
    palette = sorted({pixel[:3] for pixel in original.getdata() if pixel[3] >= 192})
    cache: dict[tuple[int, int, int], tuple[int, int, int]] = {}
    pixels = []
    for red, green, blue, alpha in generated.getdata():
        if alpha == 0:
            pixels.append((0, 0, 0, 0))
            continue
        color = (red, green, blue)
        if color not in cache:
            cache[color] = min(
                palette,
                key=lambda candidate: sum((candidate[channel] - color[channel]) ** 2 for channel in range(3)),
            )
        pixels.append((*cache[color], alpha))
    result = Image.new("RGBA", generated.size)
    result.putdata(pixels)
    return result


def replace_leg(original: Image.Image, generated: Image.Image, left_side: bool) -> Image.Image:
    # Includes the complete hip-to-toe silhouette so the shin keeps its full
    # anatomical length and diagonal recovery angle.
    left_polygon = [(35, 57), (66, 57), (66, 72), (63, 88), (61, 110), (33, 110)]
    polygon = left_polygon if left_side else [(FRAME_SIZE - x, y) for x, y in left_polygon]
    region = Image.new("L", original.size, 0)
    ImageDraw.Draw(region).polygon(polygon, fill=255)

    paste_mask = Image.composite(generated.getchannel("A"), Image.new("L", original.size, 0), region)
    result = original.copy()
    result.paste(Image.new("RGBA", original.size, (0, 0, 0, 0)), (0, 0), region)
    result.paste(generated, (0, 0), paste_mask)
    return result


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for index in range(1, 9):
        shutil.copy2(SOURCE_DIR / f"run_{index:02d}.png", OUTPUT_DIR / f"run_{index:02d}.png")

    generated_four, generated_eight = prepare_pair()
    frame_four = Image.open(SOURCE_DIR / "run_04.png").convert("RGBA")
    frame_eight = Image.open(SOURCE_DIR / "run_08.png").convert("RGBA")
    generated_four = match_palette(generated_four, frame_four)
    generated_eight = match_palette(generated_eight, frame_eight)
    replace_leg(frame_four, generated_four, left_side=True).save(OUTPUT_DIR / "run_04.png", optimize=True)
    replace_leg(frame_eight, generated_eight, left_side=False).save(OUTPUT_DIR / "run_08.png", optimize=True)

    frames = [Image.open(OUTPUT_DIR / f"run_{index:02d}.png").convert("RGBA") for index in range(1, 9)]
    strip = Image.new("RGBA", (FRAME_SIZE * 8, FRAME_SIZE), (0, 0, 0, 0))
    grid = Image.new("RGBA", (FRAME_SIZE * 4, FRAME_SIZE * 2), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME_SIZE, 0))
        grid.alpha_composite(frame, ((index % 4) * FRAME_SIZE, (index // 4) * FRAME_SIZE))
    strip.save(OUTPUT_DIR / "run_forward_v6_strip_8x1.png", optimize=True)
    grid.save(OUTPUT_DIR / "run_forward_v6_grid_4x2.png", optimize=True)

    preview = [frame.resize((512, 512), Image.Resampling.NEAREST) for frame in frames]
    preview[0].save(
        OUTPUT_DIR / "run_forward_v6_preview.gif",
        save_all=True,
        append_images=preview[1:],
        duration=95,
        loop=0,
        disposal=2,
    )


if __name__ == "__main__":
    main()
