from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


SOURCE_DIR = Path("assets/sprites/characters/base/frames/front/run_v4")
OUTPUT_DIR = Path("assets/sprites/characters/base/frames/front/raised_leg_candidates")
FRAME_SIZE = 128
TARGET_HEIGHT = 116
BOTTOM_Y = 118

CANDIDATES = {
    "A": (Path("tmp/imagegen/candidate_a_alpha.png"), 32),
    "B": (Path("tmp/imagegen/candidate_b_alpha.png"), 24),
    "C": (Path("tmp/imagegen/candidate_c_alpha.png"), 36),
}


def prepare_pair(path: Path) -> tuple[Image.Image, Image.Image]:
    source = Image.open(path).convert("RGBA")
    middle = source.width // 2
    cells = (source.crop((0, 0, middle, source.height)), source.crop((middle, 0, source.width, source.height)))
    prepared: list[Image.Image] = []
    for cell in cells:
        bbox = cell.getbbox()
        if bbox is None:
            raise RuntimeError(f"Empty generated cell in {path}")
        sprite = cell.crop(bbox)
        width = round(sprite.width * TARGET_HEIGHT / sprite.height)
        sprite = sprite.resize((width, TARGET_HEIGHT), Image.Resampling.NEAREST)
        frame = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        frame.alpha_composite(sprite, ((FRAME_SIZE - width) // 2, BOTTOM_Y - TARGET_HEIGHT))
        prepared.append(frame)

    # Generations returned the mirror order: right cell has the raised leg on
    # screen-left (frame 4), left cell on screen-right (frame 8).
    return prepared[1], prepared[0]


def match_palette(generated: Image.Image, original: Image.Image) -> Image.Image:
    palette = sorted({pixel[:3] for pixel in original.getdata() if pixel[3] >= 192})
    cache: dict[tuple[int, int, int], tuple[int, int, int]] = {}
    output = []
    for red, green, blue, alpha in generated.getdata():
        if alpha == 0:
            output.append((0, 0, 0, 0))
            continue
        color = (red, green, blue)
        if color not in cache:
            cache[color] = min(
                palette,
                key=lambda candidate: sum((candidate[channel] - color[channel]) ** 2 for channel in range(3)),
            )
        output.append((*cache[color], alpha))
    result = Image.new("RGBA", generated.size)
    result.putdata(output)
    return result


def composite_leg(original: Image.Image, generated: Image.Image, left_side: bool, outer_x: int) -> Image.Image:
    left_polygon = [(outer_x, 57), (66, 57), (66, 73), (63, 90), (61, 111), (outer_x, 111)]
    polygon = left_polygon if left_side else [(FRAME_SIZE - x, y) for x, y in left_polygon]
    region = Image.new("L", original.size, 0)
    ImageDraw.Draw(region).polygon(polygon, fill=255)
    paste_mask = Image.composite(generated.getchannel("A"), Image.new("L", original.size, 0), region)
    result = original.copy()
    result.paste(Image.new("RGBA", original.size, (0, 0, 0, 0)), (0, 0), region)
    result.paste(generated, (0, 0), paste_mask)
    return result


def checkerboard(size: tuple[int, int], cell: int = 16) -> Image.Image:
    image = Image.new("RGBA", size, (31, 34, 40, 255))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(43, 47, 55, 255))
    return image


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    original_four = Image.open(SOURCE_DIR / "run_04.png").convert("RGBA")
    original_eight = Image.open(SOURCE_DIR / "run_08.png").convert("RGBA")
    results: dict[str, tuple[Image.Image, Image.Image]] = {}

    for name, (source, outer_x) in CANDIDATES.items():
        generated_four, generated_eight = prepare_pair(source)
        generated_four = match_palette(generated_four, original_four)
        generated_eight = match_palette(generated_eight, original_eight)
        frame_four = composite_leg(original_four, generated_four, True, outer_x)
        frame_eight = composite_leg(original_eight, generated_eight, False, outer_x)
        frame_four.save(OUTPUT_DIR / f"option_{name.lower()}_frame_04.png", optimize=True)
        frame_eight.save(OUTPUT_DIR / f"option_{name.lower()}_frame_08.png", optimize=True)
        pair = Image.new("RGBA", (256, 128), (0, 0, 0, 0))
        pair.alpha_composite(frame_four, (0, 0))
        pair.alpha_composite(frame_eight, (128, 0))
        pair.save(OUTPUT_DIR / f"option_{name.lower()}_pair.png", optimize=True)
        results[name] = (frame_four, frame_eight)

    scale = 2
    header = 44
    board = checkerboard((FRAME_SIZE * scale * 3, header + FRAME_SIZE * scale * 2))
    draw = ImageDraw.Draw(board)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 28)
    except OSError:
        font = ImageFont.load_default()

    for column, name in enumerate(("A", "B", "C")):
        text_box = draw.textbbox((0, 0), name, font=font)
        text_width = text_box[2] - text_box[0]
        draw.text(
            (column * FRAME_SIZE * scale + (FRAME_SIZE * scale - text_width) // 2, 7),
            name,
            font=font,
            fill=(255, 255, 255, 255),
        )
        for row, frame in enumerate(results[name]):
            enlarged = frame.resize((FRAME_SIZE * scale, FRAME_SIZE * scale), Image.Resampling.NEAREST)
            board.alpha_composite(enlarged, (column * FRAME_SIZE * scale, header + row * FRAME_SIZE * scale))
    board.save(OUTPUT_DIR / "raised_leg_options_ABC.png", optimize=True)


if __name__ == "__main__":
    main()
