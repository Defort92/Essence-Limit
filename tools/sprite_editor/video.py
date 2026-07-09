#!/usr/bin/env python3
"""
Video → frames loader.

Использует imageio с ffmpeg-плагином. Установка:
    pip install imageio imageio-ffmpeg
"""

from pathlib import Path
from typing import Iterator

from PIL import Image


def _check_imageio():
    """Импорт imageio с понятной ошибкой если не установлен."""
    try:
        import imageio.v3 as iio
        return iio
    except ImportError:
        raise RuntimeError(
            "Для загрузки видео нужен imageio:\n"
            "    pip install imageio imageio-ffmpeg"
        )


def count_frames(video_path: Path) -> int:
    """Прикинуть число кадров. Возвращает -1 если не удалось."""
    try:
        iio = _check_imageio()
        meta = iio.immeta(str(video_path), plugin="pyav")
    except Exception:
        try:
            meta = iio.immeta(str(video_path))
        except Exception:
            return -1
    fps = meta.get("fps", 0)
    duration = meta.get("duration", 0)
    if fps and duration:
        return int(fps * duration)
    return meta.get("nframes", -1) or -1


def load_frames(
    video_path: Path,
    every_n: int = 1,
    max_frames: int = 200,
    start_frame: int = 0,
) -> Iterator[tuple[int, Image.Image]]:
    """
    Итератор по кадрам видео. Yields (frame_index, PIL.Image RGBA).

    every_n      — брать каждый N-й кадр (1 = все, 4 = каждый четвёртый)
    max_frames   — максимум сколько кадров вернуть после фильтрации
    start_frame  — пропустить первые N кадров видео
    """
    iio = _check_imageio()

    out_count = 0
    for i, arr in enumerate(iio.imiter(str(video_path))):
        if i < start_frame:
            continue
        if (i - start_frame) % every_n != 0:
            continue
        if out_count >= max_frames:
            break
        img = Image.fromarray(arr)
        if img.mode != "RGBA":
            img = img.convert("RGBA")
        yield (i, img)
        out_count += 1


def load_frames_list(
    video_path: Path,
    every_n: int = 1,
    max_frames: int = 200,
    start_frame: int = 0,
    resize_to: int = 0,
) -> list[tuple[str, Image.Image]]:
    """
    Удобная обёртка: возвращает список (имя_файла, image).
    Имена идут как frame_0001.png, frame_0002.png и т.д.

    resize_to > 0 — ресайз КАЖДОГО кадра по длинной стороне СРАЗУ при загрузке
    (через BOX-фильтр), чтобы не держать в RAM 1080p × N штук.
    Это критично для длинных видео.
    """
    result = []
    for idx, (orig_idx, img) in enumerate(load_frames(
        video_path, every_n, max_frames, start_frame
    )):
        if resize_to > 0:
            w, h = img.size
            if max(w, h) > resize_to:
                if w >= h:
                    new_w = resize_to
                    new_h = max(1, round(h * resize_to / w))
                else:
                    new_h = resize_to
                    new_w = max(1, round(w * resize_to / h))
                img = img.resize((new_w, new_h), Image.BOX)
        name = f"frame_{idx:04d}.png"
        result.append((name, img))
    return result
