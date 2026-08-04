from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


SOURCE_DIR = Path("assets/sprites/characters/base/frames/front/run_v4")
OUTPUT_DIR = Path("assets/sprites/characters/base/frames/front/raised_leg_candidates_original_refs")
FRAME_SIZE = 128
TARGET_HEIGHT = 116
BOTTOM_Y = 118
CANDIDATES = {
    "D": (Path("tmp/imagegen/candidate_d_alpha.png"), 34),
    "E": (Path("tmp/imagegen/candidate_e_alpha.png"), 23),
    "F": (Path("tmp/imagegen/candidate_f_alpha.png"), 35),
}


def prepare_pair(path: Path) -> tuple[Image.Image, Image.Image]:
    source = Image.open(path).convert("RGBA")
    middle = source.width // 2
    prepared = []
    for cell in (source.crop((0, 0, middle, source.height)), source.crop((middle, 0, source.width, source.height))):
        bbox = cell.getbbox()
        if bbox is None:
            raise RuntimeError(f"Empty generated cell in {path}")
        sprite = cell.crop(bbox)
        width = round(sprite.width * TARGET_HEIGHT / sprite.height)
        sprite = sprite.resize((width, TARGET_HEIGHT), Image.Resampling.NEAREST)
        frame = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        frame.alpha_composite(sprite, ((FRAME_SIZE - width) // 2, BOTTOM_Y - TARGET_HEIGHT))
        prepared.append(frame)
    return prepared[0], prepared[1]


def palette_match(generated: Image.Image, original: Image.Image) -> Image.Image:
    palette = sorted({pixel[:3] for pixel in original.getdata() if pixel[3] >= 192})
    cache = {}
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
    left_polygon = [(outer_x, 56), (66, 56), (66, 73), (63, 92), (61, 112), (outer_x, 112)]
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
    originals = (
        Image.open(SOURCE_DIR / "run_04.png").convert("RGBA"),
        Image.open(SOURCE_DIR / "run_08.png").convert("RGBA"),
    )
    results = {}
    for name, (path, outer_x) in CANDIDATES.items():
        generated = prepare_pair(path)
        frames = (
            composite_leg(originals[0], palette_match(generated[0], originals[0]), True, outer_x),
            composite_leg(originals[1], palette_match(generated[1], originals[1]), False, outer_x),
        )
        for frame_number, frame in zip((4, 8), frames):
            frame.save(OUTPUT_DIR / f"option_{name.lower()}_frame_{frame_number:02d}.png", optimize=True)
        pair = Image.new("RGBA", (256, 128), (0, 0, 0, 0))
        pair.alpha_composite(frames[0], (0, 0))
        pair.alpha_composite(frames[1], (128, 0))
        pair.save(OUTPUT_DIR / f"option_{name.lower()}_pair.png", optimize=True)
        results[name] = frames

    scale, header = 2, 44
    board = checkerboard((768, header + 512))
    draw = ImageDraw.Draw(board)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 28)
    except OSError:
        font = ImageFont.load_default()
    for column, name in enumerate(("D", "E", "F")):
        box = draw.textbbox((0, 0), name, font=font)
        draw.text((column * 256 + (256 - (box[2] - box[0])) // 2, 7), name, font=font, fill="white")
        for row, frame in enumerate(results[name]):
            board.alpha_composite(frame.resize((256, 256), Image.Resampling.NEAREST), (column * 256, header + row * 256))
    board.save(OUTPUT_DIR / "raised_leg_options_DEF.png", optimize=True)


if __name__ == "__main__":
    main()
