#!/usr/bin/env python3
"""
Упаковка кадров в готовый game-ready спрайт-лист.

Берёт список PIL-изображений и пакует их в один PNG с регулярной сеткой клеток.
Каждый кадр выравнивается по нижней линии и центруется горизонтально в клетке.

Также сохраняет JSON-манифест для Godot/Phaser/etc.
"""

import json
from pathlib import Path

import numpy as np
from PIL import Image


def foot_align_in_cell(img: Image.Image, cell_w: int, cell_h: int) -> Image.Image:
    """
    Поместить изображение в клетку cell_w × cell_h так, чтобы:
      - нижний непрозрачный пиксель оказался на y = cell_h - 1
      - центр содержимого по горизонтали оказался на x = cell_w // 2

    Если содержимое больше клетки — масштабируется вниз (NEAREST, без размытия).
    """
    rgba = img.convert("RGBA")
    arr = np.array(rgba)
    alpha = arr[:, :, 3]

    rows_with = np.where(alpha.max(axis=1) > 0)[0]
    cols_with = np.where(alpha.max(axis=0) > 0)[0]

    cell = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
    if len(rows_with) == 0 or len(cols_with) == 0:
        return cell

    top, bottom = int(rows_with[0]), int(rows_with[-1])
    left, right = int(cols_with[0]), int(cols_with[-1])
    cropped = rgba.crop((left, top, right + 1, bottom + 1))

    # Если не помещается — уменьшить (NEAREST чтобы не было мыла)
    if cropped.width > cell_w or cropped.height > cell_h:
        scale = min(cell_w / cropped.width, cell_h / cropped.height)
        new_w = max(1, int(cropped.width * scale))
        new_h = max(1, int(cropped.height * scale))
        cropped = cropped.resize((new_w, new_h), Image.NEAREST)

    paste_x = (cell_w - cropped.width) // 2
    paste_y = cell_h - cropped.height
    cell.paste(cropped, (paste_x, paste_y), cropped)
    return cell


def pack_spritesheet(
    frames: list[Image.Image],
    cell_w: int,
    cell_h: int,
    cols: int,
    rows: int,
) -> Image.Image:
    """
    Запаковать кадры в сетку cols × rows. Каждая клетка cell_w × cell_h.
    Возвращает RGBA-изображение размером (cols × cell_w, rows × cell_h).

    Если кадров больше чем cols*rows — лишние игнорируются.
    Если меньше — оставшиеся клетки прозрачные.
    """
    sheet = Image.new("RGBA", (cols * cell_w, rows * cell_h), (0, 0, 0, 0))
    capacity = cols * rows

    for i, frame in enumerate(frames):
        if i >= capacity:
            break
        c = i % cols
        r = i // cols
        cell = foot_align_in_cell(frame, cell_w, cell_h)
        sheet.paste(cell, (c * cell_w, r * cell_h), cell)

    return sheet


def pack_aseprite_sheet(
    frames: list[Image.Image],
    cell_w: int,
    cell_h: int,
    cols: int,
    rows: int,
    anchor: str = "center",
) -> Image.Image:
    """
    Запаковка для Aseprite «Import Sprite Sheet»: каждый кадр кладётся в клетку
    БЕЗ crop/foot-align — только паддинг прозрачным до cell_w×cell_h.
    Aseprite потом сам нарежет атлас регулярной сеткой.
    """
    from image_ops import op_pad_to_canvas

    sheet = Image.new("RGBA", (cols * cell_w, rows * cell_h), (0, 0, 0, 0))
    capacity = cols * rows
    for i, frame in enumerate(frames):
        if i >= capacity:
            break
        c = i % cols
        r = i // cols
        cell = op_pad_to_canvas(frame, cell_w, cell_h, anchor=anchor)
        sheet.paste(cell, (c * cell_w, r * cell_h), cell)
    return sheet


def build_manifest(
    action: str,
    direction: str,
    frame_count: int,
    cell_w: int,
    cell_h: int,
    cols: int,
    rows: int,
    fps: int,
) -> dict:
    """Манифест в формате, совместимом с предыдущим build_spritesheet.py."""
    return {
        "version": 1,
        "action": action,
        "direction": direction,
        "spritesheet": "spritesheet.png",
        "frameWidth": cell_w,
        "frameHeight": cell_h,
        "columns": cols,
        "rows": rows,
        "frames": frame_count,
        "fps": fps,
        "anchor": {"x": cell_w // 2, "y": cell_h - 1},
    }


def save_spritesheet(
    sheet: Image.Image,
    manifest: dict,
    output_dir: Path,
) -> tuple[Path, Path]:
    """Сохранить PNG + JSON. Возвращает (png_path, json_path)."""
    output_dir.mkdir(parents=True, exist_ok=True)
    png_path = output_dir / "spritesheet.png"
    json_path = output_dir / "manifest.json"
    sheet.save(png_path)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
    return png_path, json_path
