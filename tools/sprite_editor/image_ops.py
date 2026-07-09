"""
Чистые операции над PIL.Image — без Tkinter, без зависимостей от editor state.
Каждая функция принимает Image и возвращает новый Image (или кортеж).
"""

from typing import Optional

import numpy as np
from PIL import Image

from config import CHROMA_TOLERANCE


def op_pixel_snap(img: Image.Image, cell: int) -> Image.Image:
    """Простой snap: NN-downscale → NN-upscale."""
    w, h = img.size
    sw = max(1, round(w / cell))
    sh = max(1, round(h / cell))
    small = img.resize((sw, sh), Image.NEAREST)
    return small.resize((w, h), Image.NEAREST)


def op_resize_to(img: Image.Image, target_size: int) -> Image.Image:
    """
    Реально уменьшить изображение до target_size по длинной стороне.
    Итоговый файл будет ~target_size × target_size пикселей.
    BOX-фильтр даёт качественный downscale без размытия.
    """
    w, h = img.size
    if w >= h:
        new_w = target_size
        new_h = max(1, round(h * target_size / w))
    else:
        new_h = target_size
        new_w = max(1, round(w * target_size / h))
    return img.resize((new_w, new_h), Image.BOX)


def op_force_size(img: Image.Image, target_size: int) -> Image.Image:
    """
    Старый "force": downscale + upscale обратно. Размер изображения НЕ меняется,
    но пиксели становятся крупнее.
    """
    w, h = img.size
    small = op_resize_to(img, target_size)
    return small.resize((w, h), Image.NEAREST)


def _detect_cell_size(arr_rgb: np.ndarray) -> int:
    """Авто-детект размера native-пикселя через автокорреляцию градиента."""
    gray = arr_rgb.mean(axis=2)
    grad = np.abs(np.diff(gray, axis=1)).sum(axis=0)
    if grad.std() == 0:
        return 10
    grad = grad - grad.mean()
    corr = np.correlate(grad, grad, mode="full")[len(grad) - 1:]
    for lag in range(3, min(33, len(corr) - 1)):
        if corr[lag] > corr[lag - 1] and corr[lag] >= corr[lag + 1]:
            if corr[lag] > 0.25 * corr[0]:
                return lag
    return 10


def op_smart_snap(img: Image.Image, k_colors: int = 16,
                  cell_size: Optional[int] = None) -> tuple[Image.Image, int]:
    """
    Векторизованный SpriteFusion-style snap.
    """
    rgba = img.convert("RGBA")
    arr_rgba = np.array(rgba)
    alpha = arr_rgba[:, :, 3]
    rgb_img = rgba.convert("RGB")

    paletted = rgb_img.quantize(colors=k_colors, method=Image.Quantize.MEDIANCUT)
    pal_indices = np.array(paletted, dtype=np.int64)

    palette_flat = paletted.getpalette() or [0] * 768
    if len(palette_flat) < 768:
        palette_flat = palette_flat + [0] * (768 - len(palette_flat))
    palette_rgb = np.array(palette_flat[:768], dtype=np.uint8).reshape(256, 3)

    if cell_size is None:
        rgb_for_detect = palette_rgb[pal_indices]
        cell_size = _detect_cell_size(rgb_for_detect)
    cell_size = max(1, cell_size)

    h_orig, w_orig = pal_indices.shape
    target_w = max(1, round(w_orig / cell_size))
    target_h = max(1, round(h_orig / cell_size))
    new_h = target_h * cell_size
    new_w = target_w * cell_size

    if (new_h, new_w) != (h_orig, w_orig):
        pal_img = Image.fromarray(pal_indices.astype(np.uint8), mode="L")
        pal_indices = np.array(
            pal_img.resize((new_w, new_h), Image.NEAREST), dtype=np.int64
        )
        alpha = np.array(
            Image.fromarray(alpha).resize((new_w, new_h), Image.NEAREST)
        )

    blocks = pal_indices.reshape(target_h, cell_size, target_w, cell_size)
    blocks = blocks.transpose(0, 2, 1, 3).reshape(
        target_h * target_w, cell_size * cell_size
    )

    K = 256
    n_blocks = blocks.shape[0]
    offsets = (np.arange(n_blocks, dtype=np.int64) * K).reshape(-1, 1)
    flat = (blocks + offsets).ravel()
    counts = np.bincount(flat, minlength=n_blocks * K).reshape(n_blocks, K)
    mode_indices = counts.argmax(axis=1)

    out_rgb = palette_rgb[mode_indices].reshape(target_h, target_w, 3)

    alpha_blocks = alpha.reshape(target_h, cell_size, target_w, cell_size)
    alpha_blocks = alpha_blocks.transpose(0, 2, 1, 3).reshape(target_h, target_w, -1)
    out_alpha = np.median(alpha_blocks, axis=-1).astype(np.uint8)

    out = np.empty((target_h, target_w, 4), dtype=np.uint8)
    out[:, :, :3] = out_rgb
    out[:, :, 3] = out_alpha

    small = Image.fromarray(out, "RGBA")
    return small.resize((w_orig, h_orig), Image.NEAREST), cell_size


def op_remove_chroma(img: Image.Image, tol: int = CHROMA_TOLERANCE) -> Image.Image:
    """Удалить зелёный фон → прозрачность (жёсткий порог, как раньше)."""
    rgba = img.convert("RGBA")
    arr = np.array(rgba, dtype=np.int32)
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    mask = (g - r > tol) & (g - b > tol)
    arr[:, :, 3] = np.where(mask, 0, arr[:, :, 3])
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def op_chroma_to_alpha(img: Image.Image, tol: int = CHROMA_TOLERANCE) -> Image.Image:
    """
    «Мягкий» режим удаления зелёного фона: RGB пикселей НЕ трогаем,
    только обнуляем альфу у зелёных. Полупрозрачные края тоже
    масштабируются к нулю по мере «зелёности».

    Сами пиксели остаются на месте — это удобно для последующих
    манипуляций (motion-blur, смещения, восстановление и т.п.):
    цвет никуда не делся, просто стал невидимым.
    """
    rgba = img.convert("RGBA")
    arr = np.array(rgba, dtype=np.int32)
    r = arr[:, :, 0]
    g = arr[:, :, 1]
    b = arr[:, :, 2]
    a = arr[:, :, 3]

    rb_max = np.maximum(r, b)
    greenness = g - rb_max

    # Линейная шкала: greenness<=0 → alpha без изменений,
    # greenness>=tol → alpha=0, между ними — пропорционально.
    factor = np.clip(1.0 - greenness / float(max(1, tol)), 0.0, 1.0)
    new_a = np.clip(a.astype(np.float32) * factor, 0, 255).astype(np.int32)

    arr[:, :, 3] = new_a
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def op_crop_to_content(img: Image.Image) -> tuple[Image.Image, int, int]:
    """Обрезать прозрачные края. Возвращает (img, dx, dy)."""
    rgba = img.convert("RGBA")
    bbox = rgba.getbbox()
    if bbox is None:
        return rgba, 0, 0
    left, top, right, bottom = bbox
    cropped = rgba.crop(bbox)
    return cropped, left, top


def op_pad_to_canvas(img: Image.Image, target_w: int, target_h: int,
                     anchor: str = "center") -> Image.Image:
    """
    Поместить изображение в холст target_w × target_h с прозрачным паддингом.
    anchor: "center" | "topleft" | "bottom" (низ по центру).
    Если изображение больше холста — обрежется по краям.
    """
    rgba = img.convert("RGBA")
    w, h = rgba.size
    canvas = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    if anchor == "topleft":
        x, y = 0, 0
    elif anchor == "bottom":
        x = (target_w - w) // 2
        y = target_h - h
    else:  # center
        x = (target_w - w) // 2
        y = (target_h - h) // 2
    canvas.paste(rgba, (x, y), rgba)
    return canvas


def build_shared_palette(frames: list, k: int = 32) -> Image.Image:
    """
    Построить общую палитру k цветов на основе всех кадров.
    Учитываются только непрозрачные пиксели. Возвращает PIL-картинку
    в режиме 'P' с палитрой — её можно передать в quantize(palette=...).
    """
    if not frames:
        raise ValueError("build_shared_palette: пустой список кадров")

    pixels = []
    for f in frames:
        arr = np.array(f.convert("RGBA"))
        mask = arr[..., 3] > 0
        if mask.any():
            pixels.append(arr[mask][:, :3])

    if not pixels:
        # Все кадры полностью прозрачные — fallback на первый
        return frames[0].convert("RGB").quantize(
            colors=k, method=Image.Quantize.MEDIANCUT
        )

    all_px = np.concatenate(pixels, axis=0)
    # Pillow требует 2D-картинку; делаем (N, 1, 3)
    sample = Image.fromarray(all_px.reshape(-1, 1, 3).astype(np.uint8), "RGB")
    return sample.quantize(colors=k, method=Image.Quantize.MEDIANCUT)


def op_apply_shared_palette(img: Image.Image,
                            palette_img: Image.Image) -> Image.Image:
    """
    Квантизовать img по общей палитре. Возвращает PIL-картинку в режиме 'P'
    с info['transparency'] — это даёт настоящий Indexed PNG, который
    Aseprite сразу открывает в режиме Indexed.
    """
    rgba = img.convert("RGBA")
    arr = np.array(rgba)
    alpha = arr[..., 3]
    rgb = rgba.convert("RGB")
    quantized = rgb.quantize(palette=palette_img, dither=Image.Dither.NONE)
    pal = quantized.getpalette()

    arr_p = np.array(quantized, dtype=np.uint8)
    transparent_idx = 0
    arr_p[alpha < 128] = transparent_idx

    out = Image.fromarray(arr_p, mode="P")
    out.putpalette(pal)
    out.info["transparency"] = transparent_idx
    return out


def op_foot_baseline(img: Image.Image, target_y: int) -> tuple[Image.Image, int, int]:
    """
    Найти нижний непрозрачный пиксель и подвинуть так, чтобы он попал на target_y.
    Возвращает (img, dx, dy).
    """
    rgba = img.convert("RGBA")
    arr = np.array(rgba)
    alpha = arr[:, :, 3]
    rows_with = np.where(alpha.max(axis=1) > 0)[0]
    cols_with = np.where(alpha.max(axis=0) > 0)[0]
    if len(rows_with) == 0:
        return rgba, 0, 0
    bottom = int(rows_with[-1])
    dy = target_y - bottom
    left, right = int(cols_with[0]), int(cols_with[-1])
    content_cx = (left + right) // 2
    image_cx = img.size[0] // 2
    dx = image_cx - content_cx
    return rgba, dx, dy
