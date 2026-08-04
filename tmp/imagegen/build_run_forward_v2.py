from pathlib import Path

from PIL import Image


SOURCE = Path("tmp/imagegen/run_forward_v2_alpha.png")
OUTPUT = Path("assets/sprites/characters/base/frames/front/run_v2")
FRAME_SIZE = 128
MAX_SPRITE_HEIGHT = 116

# Contact, recoil, passing, high; then the mirrored half of the cycle.
# These are intentional animation offsets, not automatic bottom alignment.
BOTTOM_Y = (121, 124, 120, 115, 121, 124, 120, 115)


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    width, height = source.size
    x_edges = [round(width * index / 4) for index in range(5)]
    y_edges = [round(height * index / 2) for index in range(3)]

    sprites: list[Image.Image] = []
    for row in range(2):
        for column in range(4):
            tile = source.crop(
                (
                    x_edges[column],
                    y_edges[row],
                    x_edges[column + 1],
                    y_edges[row + 1],
                )
            )
            bbox = tile.getbbox()
            if bbox is None:
                raise RuntimeError(f"Empty generated frame at row {row}, column {column}")
            sprites.append(tile.crop(bbox))

    # One scale for the entire sequence preserves compression, extension, and
    # foreshortening differences between the eight generated poses.
    scale = MAX_SPRITE_HEIGHT / max(sprite.height for sprite in sprites)
    frames: list[Image.Image] = []
    OUTPUT.mkdir(parents=True, exist_ok=True)

    for index, sprite in enumerate(sprites):
        scaled_size = (
            max(1, round(sprite.width * scale)),
            max(1, round(sprite.height * scale)),
        )
        sprite = sprite.resize(scaled_size, Image.Resampling.NEAREST)

        frame = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        x = (FRAME_SIZE - sprite.width) // 2
        y = BOTTOM_Y[index] - sprite.height
        frame.alpha_composite(sprite, (x, y))
        frame.save(OUTPUT / f"run_{index + 1:02d}.png", optimize=True)
        frames.append(frame)

    strip = Image.new("RGBA", (FRAME_SIZE * 8, FRAME_SIZE), (0, 0, 0, 0))
    grid = Image.new("RGBA", (FRAME_SIZE * 4, FRAME_SIZE * 2), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME_SIZE, 0))
        grid.alpha_composite(frame, ((index % 4) * FRAME_SIZE, (index // 4) * FRAME_SIZE))

    strip.save(OUTPUT / "run_forward_v2_strip_8x1.png", optimize=True)
    grid.save(OUTPUT / "run_forward_v2_grid_4x2.png", optimize=True)

    preview_frames = [
        frame.resize((FRAME_SIZE * 4, FRAME_SIZE * 4), Image.Resampling.NEAREST)
        for frame in frames
    ]
    preview_frames[0].save(
        OUTPUT / "run_forward_v2_preview.gif",
        save_all=True,
        append_images=preview_frames[1:],
        duration=90,
        loop=0,
        disposal=2,
    )


if __name__ == "__main__":
    main()
