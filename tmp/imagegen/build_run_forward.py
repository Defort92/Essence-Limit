from pathlib import Path

from PIL import Image


SOURCE = Path("tmp/imagegen/run_forward_alpha.png")
OUTPUT = Path("assets/sprites/characters/base/frames/front/run")
FRAME_SIZE = 128
TARGET_HEIGHT = 116
BASELINE_Y = 121


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    width, height = source.size
    x_edges = [round(width * index / 4) for index in range(5)]
    y_edges = [round(height * index / 2) for index in range(3)]

    OUTPUT.mkdir(parents=True, exist_ok=True)
    frames: list[Image.Image] = []

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

            sprite = tile.crop(bbox)
            scaled_width = round(sprite.width * TARGET_HEIGHT / sprite.height)
            sprite = sprite.resize((scaled_width, TARGET_HEIGHT), Image.Resampling.NEAREST)

            frame = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            x = (FRAME_SIZE - scaled_width) // 2
            y = BASELINE_Y - TARGET_HEIGHT
            frame.alpha_composite(sprite, (x, y))
            frames.append(frame)

            frame_number = len(frames)
            frame.save(OUTPUT / f"run_{frame_number:02d}.png", optimize=True)

    horizontal = Image.new("RGBA", (FRAME_SIZE * len(frames), FRAME_SIZE), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        horizontal.alpha_composite(frame, (index * FRAME_SIZE, 0))
    horizontal.save(OUTPUT / "run_forward_strip_8x1.png", optimize=True)

    grid = Image.new("RGBA", (FRAME_SIZE * 4, FRAME_SIZE * 2), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        grid.alpha_composite(frame, ((index % 4) * FRAME_SIZE, (index // 4) * FRAME_SIZE))
    grid.save(OUTPUT / "run_forward_grid_4x2.png", optimize=True)

    preview_frames = [
        frame.resize((FRAME_SIZE * 4, FRAME_SIZE * 4), Image.Resampling.NEAREST)
        for frame in frames
    ]
    preview_frames[0].save(
        OUTPUT / "run_forward_preview.gif",
        save_all=True,
        append_images=preview_frames[1:],
        duration=85,
        loop=0,
        disposal=2,
    )


if __name__ == "__main__":
    main()
