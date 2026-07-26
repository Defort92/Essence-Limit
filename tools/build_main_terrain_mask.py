"""Build the main location grass coverage map from dual-grid mask tiles."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = PROJECT_ROOT / "assets" / "textures" / "environment" / "ground" / "dual_grid"
OUTPUT_PATH = SOURCE_DIR / "main_terrain_grass_mask.png"

WORLD_MIN = -30.0
WORLD_MAX = 30.0
GRID_POINTS = 31
OUTPUT_TILE_SIZE = 64

# World-space X/Z routes. The first route connects the portal to the enemy clearing.
ROUTES: tuple[tuple[tuple[float, float], ...], ...] = (
    ((-4.0, 6.0), (-1.0, 4.0), (3.0, 1.0), (7.0, -3.0), (12.0, -8.0)),
    ((0.0, 0.0), (-2.0, 2.0), (-4.0, 6.0)),
    ((-4.0, 6.0), (-7.0, 3.0), (-10.0, 0.0)),
)
ROUTE_RADII = (1.8, 1.65, 1.65)

# The MobSpawner uses a 6 m spawn radius. The larger clearing keeps every spawn
# point on bare ground, including the irregular grass transition.
ENEMY_CLEARING_CENTER = (12.0, -8.0)
ENEMY_CLEARING_RADIUS = 8.0
PORTAL_CLEARING_CENTER = (-4.0, 6.0)
PORTAL_CLEARING_RADIUS = 2.35


def distance_to_segment(
    point: tuple[float, float],
    start: tuple[float, float],
    end: tuple[float, float],
) -> float:
    px, pz = point
    ax, az = start
    bx, bz = end
    dx = bx - ax
    dz = bz - az
    length_squared = dx * dx + dz * dz
    if length_squared == 0.0:
        return math.hypot(px - ax, pz - az)
    t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / length_squared))
    return math.hypot(px - (ax + dx * t), pz - (az + dz * t))


def inside_route(point: tuple[float, float], route: tuple[tuple[float, float], ...], radius: float) -> bool:
    return any(
        distance_to_segment(point, route[index], route[index + 1]) <= radius
        for index in range(len(route) - 1)
    )


def is_grass(world_x: float, world_z: float) -> bool:
    point = (world_x, world_z)
    if math.dist(point, ENEMY_CLEARING_CENTER) <= ENEMY_CLEARING_RADIUS:
        return False
    if math.dist(point, PORTAL_CLEARING_CENTER) <= PORTAL_CLEARING_RADIUS:
        return False
    return not any(
        inside_route(point, route, ROUTE_RADII[index])
        for index, route in enumerate(ROUTES)
    )


def corner_pattern(image: Image.Image) -> int:
    alpha = image.getchannel("A")
    margin = max(2, image.width // 8)
    samples = (
        (margin, image.height - margin - 1),  # bottom-left: bit 0
        (image.width - margin - 1, image.height - margin - 1),  # bottom-right: bit 1
        (image.width - margin - 1, margin),  # top-right: bit 2
        (margin, margin),  # top-left: bit 3
    )
    pattern = 0
    for bit, sample in enumerate(samples):
        if alpha.getpixel(sample) >= 128:
            pattern |= 1 << bit
    return pattern


def load_canonical_masks() -> dict[int, Image.Image]:
    result: dict[int, Image.Image] = {}
    for pattern in (0b0000, 0b0001, 0b0011, 0b0101, 0b0111, 0b1111):
        path = SOURCE_DIR / f"grass_mask_{pattern:04b}.png"
        result[pattern] = Image.open(path).convert("RGBA")
    return result


def tile_for_pattern(pattern: int, masks: dict[int, Image.Image]) -> Image.Image:
    count = pattern.bit_count()
    if count == 0:
        base = masks[0b0000]
    elif count == 4:
        base = masks[0b1111]
    elif count == 1:
        base = masks[0b0001]
    elif count == 3:
        base = masks[0b0111]
    elif pattern in (0b0101, 0b1010):
        base = masks[0b0101]
    else:
        base = masks[0b0011]

    candidate = base
    for _rotation in range(4):
        if corner_pattern(candidate) == pattern:
            return candidate.resize(
                (OUTPUT_TILE_SIZE, OUTPUT_TILE_SIZE),
                Image.Resampling.LANCZOS,
            )
        candidate = candidate.transpose(Image.Transpose.ROTATE_90)
    raise ValueError(f"No rotated canonical mask matches {pattern:04b}")


def main() -> None:
    masks = load_canonical_masks()
    grid_step = (WORLD_MAX - WORLD_MIN) / float(GRID_POINTS - 1)
    points = [
        [
            is_grass(WORLD_MIN + column * grid_step, WORLD_MIN + row * grid_step)
            for column in range(GRID_POINTS)
        ]
        for row in range(GRID_POINTS)
    ]

    tile_cache = {pattern: tile_for_pattern(pattern, masks) for pattern in range(16)}
    tile_count = GRID_POINTS - 1
    output = Image.new(
        "RGBA",
        (tile_count * OUTPUT_TILE_SIZE, tile_count * OUTPUT_TILE_SIZE),
        (255, 255, 255, 0),
    )

    for row in range(tile_count):
        for column in range(tile_count):
            # Bit order matches the supplied masks: BL, BR, TR, TL.
            pattern = (
                int(points[row + 1][column])
                | int(points[row + 1][column + 1]) << 1
                | int(points[row][column + 1]) << 2
                | int(points[row][column]) << 3
            )
            output.alpha_composite(
                tile_cache[pattern],
                (column * OUTPUT_TILE_SIZE, row * OUTPUT_TILE_SIZE),
            )

    output.save(OUTPUT_PATH, optimize=True)
    print(f"Saved {OUTPUT_PATH} ({output.width}x{output.height})")


if __name__ == "__main__":
    main()
