#!/usr/bin/env python3
"""
Essence Limit — Sprite Editor
===============================
GUI-утилита для подготовки спрайтов:
  • Pixel Snap          — устранение размытых пикселей (mixels → real pixels)
  • Chroma Key          — удаление зелёного фона
  • Foot-Baseline Lock  — выравнивание персонажей по нижней точке
  • Crop to Content     — обрезка прозрачных краёв
  • Nudge               — точное смещение по 1px (стрелки) / 8px (Shift+стрелки)
  • Onion-Skin Overlay  — наложение слоёв с разными цветами для сравнения

Запуск:
    python sprite_editor.py [папка_со_спрайтами]

Зависимости:
    pip install Pillow numpy
"""

import sys
import json
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional

import tkinter as tk
from tkinter import ttk, filedialog, messagebox, colorchooser

import numpy as np
from PIL import Image, ImageTk, ImageOps

# Локальные модули
import video as video_mod
import spritesheet as ss_mod

if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout.reconfigure(encoding="utf-8")


# ═══════════════════════════════════════════════════════════════════════════════
#   КОНФИГ
# ═══════════════════════════════════════════════════════════════════════════════

CANVAS_W = 800
CANVAS_H = 800
DEFAULT_VIEW_SCALE = 0.5          # 50% — стартовый zoom
DEFAULT_CELL_SIZE = 10
CHROMA_TOLERANCE = 50
OUTPUT_SUBFOLDER = "_processed"
STATE_FILE = "_editor_state.json"

# Уровни зума в процентах (% от оригинала)
ZOOM_LEVELS = [
    0.10, 0.15, 0.20, 0.25, 0.33, 0.40, 0.50, 0.67, 0.80,
    1.00,
    1.25, 1.50, 2.00, 2.50, 3.00, 4.00, 6.00, 8.00,
]
ZOOM_MIN = ZOOM_LEVELS[0]
ZOOM_MAX = ZOOM_LEVELS[-1]

# Палитра цветов для overlay-tint (циклически назначается слоям)
OVERLAY_TINTS = [
    "#FFFFFF",  # white — нейтральный
    "#FF4444",  # red
    "#44FF44",  # green
    "#4488FF",  # blue
    "#FFDD44",  # yellow
    "#FF44DD",  # magenta
    "#44DDFF",  # cyan
    "#FF8844",  # orange
]

# Тёмная тема (PyCharm Darcula-style)
DARK = {
    "bg":          "#2b2b2b",
    "bg_alt":      "#3c3f41",
    "bg_active":   "#4b6eaf",
    "fg":          "#bbbbbb",
    "fg_active":   "#ffffff",
    "border":      "#555555",
    "canvas_bg":   "#1e1e1e",
    "entry_bg":    "#45494a",
    "button_bg":   "#4c5052",
    "button_hover": "#5c6164",
    "list_inactive": "#3c3f41",
    "list_active":  "#214283",
    "accent":      "#ffc66d",  # ярко-жёлтый для акцентов
}


# ═══════════════════════════════════════════════════════════════════════════════
#   СОСТОЯНИЕ ОДНОГО ФАЙЛА
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class SpriteLayer:
    path: Path
    original: Image.Image                # исходник, не трогаем
    current: Image.Image                 # после snap / chroma и т.д.
    offset_x: int = 0                    # смещение для отрисовки
    offset_y: int = 0
    visible: bool = True
    tint_color: str = "#FFFFFF"
    snap_cell: int = DEFAULT_CELL_SIZE
    chroma_removed: bool = False
    history: list = field(default_factory=list)

    # Кэш отрисовки — пересоздаётся только при изменении изображения / тинта / зума
    _cache_key: tuple = field(default=None, repr=False)
    _cached_photo: object = field(default=None, repr=False)
    _canvas_item: int = field(default=None, repr=False)

    def push_history(self):
        self.history.append((self.current.copy(), self.offset_x, self.offset_y))
        if len(self.history) > 30:
            self.history.pop(0)

    def undo(self) -> bool:
        if not self.history:
            return False
        self.current, self.offset_x, self.offset_y = self.history.pop()
        self.invalidate_cache()
        return True

    def invalidate_cache(self):
        self._cache_key = None
        self._cached_photo = None


# ═══════════════════════════════════════════════════════════════════════════════
#   ОПЕРАЦИИ НАД ИЗОБРАЖЕНИЯМИ
# ═══════════════════════════════════════════════════════════════════════════════

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
    но пиксели становятся крупнее. Полезно для устранения мыла, но НЕ для
    финальных game-ready ассетов.
    """
    w, h = img.size
    small = op_resize_to(img, target_size)
    return small.resize((w, h), Image.NEAREST)


def _detect_cell_size(arr_rgb: np.ndarray) -> int:
    """
    Авто-детект размера native-пикселя через автокорреляцию градиента.
    Возвращает целое число (lag первого пика).
    """
    gray = arr_rgb.mean(axis=2)
    # Профиль по горизонтали: суммарная разница соседних колонок
    grad = np.abs(np.diff(gray, axis=1)).sum(axis=0)
    if grad.std() == 0:
        return 10
    grad = grad - grad.mean()
    corr = np.correlate(grad, grad, mode="full")[len(grad) - 1:]
    # Ищем первый пик после lag 0 (минимум 3, максимум 32)
    for lag in range(3, min(33, len(corr) - 1)):
        if corr[lag] > corr[lag - 1] and corr[lag] >= corr[lag + 1]:
            if corr[lag] > 0.25 * corr[0]:
                return lag
    return 10


def op_smart_snap(img: Image.Image, k_colors: int = 16,
                  cell_size: Optional[int] = None) -> tuple[Image.Image, int]:
    """
    Умный snap по алгоритму SpriteFusion:
      1. Квантование цвета (median-cut, k_colors палитра)
      2. Авто-детект размера native-пикселя (если cell_size=None)
      3. Resample по majority vote: для каждой клетки берём самый частый цвет

    Сохраняет альфа-канал.
    """
    rgba = img.convert("RGBA")
    arr_rgba = np.array(rgba)
    alpha = arr_rgba[:, :, 3]
    rgb_img = rgba.convert("RGB")

    # 1. Quantize
    paletted = rgb_img.quantize(colors=k_colors, method=Image.Quantize.MEDIANCUT)
    quantized = np.array(paletted.convert("RGB"))

    # 2. Detect cell size
    if cell_size is None:
        cell_size = _detect_cell_size(quantized)

    h, w = quantized.shape[:2]
    target_w = max(1, round(w / cell_size))
    target_h = max(1, round(h / cell_size))

    # 3. Majority vote per cell
    out = np.zeros((target_h, target_w, 4), dtype=np.uint8)
    cell_w_f = w / target_w
    cell_h_f = h / target_h

    for ty in range(target_h):
        y0 = int(ty * cell_h_f)
        y1 = max(y0 + 1, int((ty + 1) * cell_h_f))
        for tx in range(target_w):
            x0 = int(tx * cell_w_f)
            x1 = max(x0 + 1, int((tx + 1) * cell_w_f))
            block = quantized[y0:y1, x0:x1].reshape(-1, 3)
            block_a = alpha[y0:y1, x0:x1].reshape(-1)
            if block.size == 0:
                continue
            # Самый частый цвет в блоке
            view = np.ascontiguousarray(block).view(
                np.dtype((np.void, block.dtype.itemsize * 3))
            )
            _, idx, counts = np.unique(view, return_index=True, return_counts=True)
            best = block[idx[counts.argmax()]]
            out[ty, tx, :3] = best
            # Альфа: медиана
            out[ty, tx, 3] = int(np.median(block_a))

    small = Image.fromarray(out, "RGBA")
    return small.resize((w, h), Image.NEAREST), cell_size


def op_remove_chroma(img: Image.Image, tol: int = CHROMA_TOLERANCE) -> Image.Image:
    """Удалить зелёный фон → прозрачность."""
    rgba = img.convert("RGBA")
    arr = np.array(rgba, dtype=np.int32)
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    mask = (g - r > tol) & (g - b > tol)
    arr[:, :, 3] = np.where(mask, 0, arr[:, :, 3])
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def op_crop_to_content(img: Image.Image) -> tuple[Image.Image, int, int]:
    """
    Обрезать прозрачные края. Возвращает (новое изображение, dx, dy)
    где dx/dy — на сколько сдвинулся top-left угол.
    """
    rgba = img.convert("RGBA")
    bbox = rgba.getbbox()
    if bbox is None:
        return rgba, 0, 0
    left, top, right, bottom = bbox
    cropped = rgba.crop(bbox)
    return cropped, left, top


def op_foot_baseline(img: Image.Image, target_y: int) -> tuple[Image.Image, int, int]:
    """
    Найти нижний непрозрачный пиксель и подвинуть так, чтобы он попал на target_y.
    Возвращает (img, dx, dy_to_apply_as_offset).
    """
    rgba = img.convert("RGBA")
    arr = np.array(rgba)
    alpha = arr[:, :, 3]
    rows_with = np.where(alpha.max(axis=1) > 0)[0]
    cols_with = np.where(alpha.max(axis=0) > 0)[0]
    if len(rows_with) == 0:
        return rgba, 0, 0
    bottom = int(rows_with[-1])
    # Сколько надо сдвинуть, чтобы bottom оказался на target_y
    dy = target_y - bottom
    # Горизонтально — центр содержимого на центр изображения
    left, right = int(cols_with[0]), int(cols_with[-1])
    content_cx = (left + right) // 2
    image_cx = img.size[0] // 2
    dx = image_cx - content_cx
    return rgba, dx, dy


# ═══════════════════════════════════════════════════════════════════════════════
#   ГЛАВНОЕ ОКНО
# ═══════════════════════════════════════════════════════════════════════════════

class SpriteEditor:
    def __init__(self, root: tk.Tk, initial_folder: Optional[Path] = None):
        self.root = root
        self.root.title("Essence Limit — Sprite Editor")
        self.root.geometry("1280x900")

        self.folder: Optional[Path] = None
        self.layers: dict[str, SpriteLayer] = {}      # filename → layer
        self.active_name: Optional[str] = None
        self.view_scale: float = DEFAULT_VIEW_SCALE   # дробный масштаб (0.1 .. 8.0)

        # Playback (превью анимации)
        self.playback_on: bool = False
        self.playback_idx: int = 0
        self.playback_after_id: Optional[str] = None
        self._playback_item: Optional[int] = None     # один shared canvas item для всех кадров плейбэка
        self._playback_frame_drift_warned: bool = False
        self.baseline_y: tk.IntVar = tk.IntVar(value=600)
        self.show_baseline: tk.BooleanVar = tk.BooleanVar(value=True)
        self.show_center: tk.BooleanVar = tk.BooleanVar(value=True)
        self.show_grid: tk.BooleanVar = tk.BooleanVar(value=False)

        self._tk_images: list = []   # keep refs so Tk doesn't GC

        self._build_ui()
        self._bind_keys()

        if initial_folder and initial_folder.exists():
            self._load_folder(initial_folder)

    # ── UI build ─────────────────────────────────────────────────────────────

    def _apply_dark_theme(self):
        """Тёмная тема в стиле PyCharm Darcula."""
        self.root.configure(bg=DARK["bg"])

        style = ttk.Style()
        # clam — единственная встроенная тема, которая нормально кастомизируется
        try:
            style.theme_use("clam")
        except Exception:
            pass

        # Frames
        style.configure("TFrame", background=DARK["bg"])
        style.configure("TLabel", background=DARK["bg"], foreground=DARK["fg"])
        style.configure("TLabelframe", background=DARK["bg"], foreground=DARK["fg"])
        style.configure("TLabelframe.Label",
                        background=DARK["bg"], foreground=DARK["fg"])

        # Buttons
        style.configure("TButton",
                        background=DARK["button_bg"],
                        foreground=DARK["fg"],
                        bordercolor=DARK["border"],
                        focuscolor=DARK["bg_active"],
                        lightcolor=DARK["button_bg"],
                        darkcolor=DARK["button_bg"],
                        relief="flat")
        style.map("TButton",
                  background=[("active", DARK["button_hover"]),
                              ("pressed", DARK["bg_active"])],
                  foreground=[("active", DARK["fg_active"])])

        # Spinbox / Entry
        style.configure("TSpinbox",
                        fieldbackground=DARK["entry_bg"],
                        foreground=DARK["fg"],
                        bordercolor=DARK["border"],
                        arrowcolor=DARK["fg"],
                        background=DARK["button_bg"])
        style.configure("TEntry",
                        fieldbackground=DARK["entry_bg"],
                        foreground=DARK["fg"],
                        bordercolor=DARK["border"],
                        insertcolor=DARK["fg"])

        # Checkbutton
        style.configure("TCheckbutton",
                        background=DARK["bg"],
                        foreground=DARK["fg"],
                        indicatorbackground=DARK["entry_bg"],
                        indicatorforeground=DARK["fg"])
        style.map("TCheckbutton",
                  background=[("active", DARK["bg"])],
                  foreground=[("active", DARK["fg_active"])])

        # Scrollbar
        style.configure("Vertical.TScrollbar",
                        background=DARK["button_bg"],
                        troughcolor=DARK["bg"],
                        bordercolor=DARK["border"],
                        arrowcolor=DARK["fg"],
                        gripcount=0)
        style.configure("Horizontal.TScrollbar",
                        background=DARK["button_bg"],
                        troughcolor=DARK["bg"],
                        bordercolor=DARK["border"],
                        arrowcolor=DARK["fg"],
                        gripcount=0)

        # Separator
        style.configure("TSeparator", background=DARK["border"])

        # Дефолтные цвета для tk-виджетов (Canvas, Label-style и Button-tk в списке)
        self.root.option_add("*background", DARK["bg"])
        self.root.option_add("*foreground", DARK["fg"])
        self.root.option_add("*Canvas.background", DARK["canvas_bg"])
        self.root.option_add("*Label.background", DARK["bg"])
        self.root.option_add("*Label.foreground", DARK["fg"])

    def _build_ui(self):
        self._apply_dark_theme()

        # Top toolbar
        top = ttk.Frame(self.root)
        top.pack(side="top", fill="x", padx=4, pady=4)

        ttk.Button(top, text="📂 Папка", command=self._open_folder).pack(side="left")
        ttk.Button(top, text="📹 Видео", command=self._open_video).pack(side="left", padx=(4, 0))
        ttk.Button(top, text="💾 Активный", command=self._save_active).pack(side="left", padx=(8, 0))
        ttk.Button(top, text="💾💾 ВСЕ", command=self._save_all).pack(side="left", padx=(4, 0))
        ttk.Button(top, text="🎬 Pack Spritesheet",
                   command=self._open_pack_dialog).pack(side="left", padx=(8, 0))

        ttk.Separator(top, orient="vertical").pack(side="left", fill="y", padx=10)

        ttk.Label(top, text="Zoom:").pack(side="left")
        self.zoom_var = tk.StringVar(value=f"{int(DEFAULT_VIEW_SCALE * 100)}%")
        zoom_values = [f"{int(z * 100)}%" for z in ZOOM_LEVELS]
        self.zoom_combo = ttk.Combobox(top, width=6, textvariable=self.zoom_var,
                                        values=zoom_values, state="readonly")
        self.zoom_combo.pack(side="left", padx=(4, 4))
        self.zoom_combo.bind("<<ComboboxSelected>>", lambda e: self._on_zoom_changed())

        ttk.Button(top, text="−", width=2,
                   command=lambda: self._zoom_step_at_center(-1)).pack(side="left", padx=1)
        ttk.Button(top, text="+", width=2,
                   command=lambda: self._zoom_step_at_center(+1)).pack(side="left", padx=(1, 4))
        ttk.Button(top, text="Fit",
                   command=self._zoom_fit).pack(side="left", padx=(0, 12))

        # ── Playback (превью анимации) ──────────────────────────────────────
        ttk.Separator(top, orient="vertical").pack(side="left", fill="y", padx=4)

        self.play_btn = ttk.Button(top, text="▶ Play", width=8,
                                    command=self._toggle_playback)
        self.play_btn.pack(side="left", padx=(4, 2))

        ttk.Button(top, text="⏮", width=2,
                    command=lambda: self._scrub(0)).pack(side="left", padx=1)
        ttk.Button(top, text="◀", width=2,
                    command=lambda: self._scrub(self.playback_idx - 1)).pack(side="left", padx=1)
        ttk.Button(top, text="▶", width=2,
                    command=lambda: self._scrub(self.playback_idx + 1)).pack(side="left", padx=1)

        ttk.Label(top, text="FPS:").pack(side="left", padx=(8, 2))
        self.play_fps = tk.IntVar(value=10)
        ttk.Spinbox(top, from_=1, to=60, width=4,
                     textvariable=self.play_fps).pack(side="left")

        self.frame_indicator = ttk.Label(top, text="0 / 0", width=10)
        self.frame_indicator.pack(side="left", padx=(8, 0))

        ttk.Label(top, text="Baseline Y:").pack(side="left")
        baseline_spin = ttk.Spinbox(top, from_=0, to=2000, width=6,
                                    textvariable=self.baseline_y,
                                    command=self._redraw)
        baseline_spin.pack(side="left", padx=(4, 12))
        self.baseline_y.trace_add("write", lambda *a: self._redraw())

        ttk.Checkbutton(top, text="Линия baseline", variable=self.show_baseline,
                        command=self._redraw).pack(side="left", padx=4)
        ttk.Checkbutton(top, text="Центр", variable=self.show_center,
                        command=self._redraw).pack(side="left", padx=4)
        ttk.Checkbutton(top, text="Сетка", variable=self.show_grid,
                        command=self._redraw).pack(side="left", padx=4)

        # Main area
        main = ttk.Frame(self.root)
        main.pack(side="top", fill="both", expand=True, padx=4, pady=4)

        # Left panel — file list
        left = ttk.Frame(main, width=260)
        left.pack(side="left", fill="y", padx=(0, 4))
        left.pack_propagate(False)

        ttk.Label(left, text="Слои (✓ видим, ● активный)").pack(anchor="w")

        # Scrollable file list
        list_frame = ttk.Frame(left)
        list_frame.pack(fill="both", expand=True)

        canvas = tk.Canvas(list_frame, highlightthickness=0, bg=DARK["bg"])
        scrollbar = ttk.Scrollbar(list_frame, orient="vertical", command=canvas.yview)
        self.file_list_frame = ttk.Frame(canvas)
        self.file_list_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        canvas.create_window((0, 0), window=self.file_list_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)
        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        # Center — image canvas with scrollbars
        center = ttk.Frame(main)
        center.pack(side="left", fill="both", expand=True)

        self.canvas = tk.Canvas(center, bg=DARK["canvas_bg"], highlightthickness=0)
        h_scroll = ttk.Scrollbar(center, orient="horizontal", command=self.canvas.xview)
        v_scroll = ttk.Scrollbar(center, orient="vertical", command=self.canvas.yview)
        self.canvas.configure(xscrollcommand=h_scroll.set, yscrollcommand=v_scroll.set)
        self.canvas.grid(row=0, column=0, sticky="nsew")
        v_scroll.grid(row=0, column=1, sticky="ns")
        h_scroll.grid(row=1, column=0, sticky="ew")
        center.grid_rowconfigure(0, weight=1)
        center.grid_columnconfigure(0, weight=1)

        # Right panel — tools
        right = ttk.Frame(main, width=300)
        right.pack(side="right", fill="y", padx=(4, 0))
        right.pack_propagate(False)

        # Active file info
        self.active_label = ttk.Label(right, text="(нет активного слоя)",
                                       font=("Segoe UI", 10, "bold"))
        self.active_label.pack(anchor="w", pady=(0, 8))

        self.info_label = ttk.Label(right, text="", font=("Consolas", 9))
        self.info_label.pack(anchor="w", pady=(0, 8))

        ttk.Separator(right, orient="horizontal").pack(fill="x", pady=4)

        # Pixel Snap section
        ttk.Label(right, text="УСТРАНЕНИЕ РАЗМЫТИЯ",
                  font=("Segoe UI", 9, "bold")).pack(anchor="w")

        # Smart Snap (SpriteFusion-style)
        smart_frame = ttk.Frame(right)
        smart_frame.pack(anchor="w", fill="x", pady=2)
        ttk.Label(smart_frame, text="K-colors:").pack(side="left")
        self.kcolors_var = tk.IntVar(value=16)
        ttk.Spinbox(smart_frame, from_=4, to=64, width=4,
                    textvariable=self.kcolors_var).pack(side="left", padx=2)
        ttk.Button(smart_frame, text="🪄 Smart Snap", width=12,
                   command=self._do_smart_snap).pack(side="left", padx=2)
        ttk.Label(right, text="↳ Авто-определяет cell, чистит палитру",
                  foreground="gray").pack(anchor="w")

        # Resize (реальное уменьшение)
        ttk.Label(right, text="РЕАЛЬНЫЙ РЕСАЙЗ",
                  font=("Segoe UI", 9, "bold")).pack(anchor="w", pady=(6, 0))
        size_frame = ttk.Frame(right)
        size_frame.pack(anchor="w", fill="x", pady=(4, 2))
        ttk.Label(size_frame, text="Px:").pack(side="left")
        self.force_size_var = tk.IntVar(value=96)
        ttk.Spinbox(size_frame, from_=16, to=512, increment=16,
                    width=5, textvariable=self.force_size_var).pack(side="left", padx=2)
        ttk.Button(size_frame, text="↓ Активный",
                   command=self._do_resize_active).pack(side="left", padx=2)
        ttk.Button(right, text="↓↓ Resize ВСЕХ слоёв",
                   command=self._do_resize_all).pack(anchor="w", fill="x", pady=2)
        ttk.Label(right, text="↳ Реально уменьшает картинку (1024 → 96)",
                  foreground="gray").pack(anchor="w")
        ttk.Label(right, text="↳ Сохранится как файл 96×96",
                  foreground="gray").pack(anchor="w")

        # Naive snap (старый)
        snap_frame = ttk.Frame(right)
        snap_frame.pack(anchor="w", fill="x", pady=(6, 2))
        ttk.Label(snap_frame, text="Cell:").pack(side="left")
        self.cell_var = tk.IntVar(value=DEFAULT_CELL_SIZE)
        ttk.Spinbox(snap_frame, from_=2, to=32, width=4,
                    textvariable=self.cell_var).pack(side="left", padx=2)
        ttk.Button(snap_frame, text="Naive Snap", width=12,
                   command=self._do_pixel_snap).pack(side="left", padx=2)
        ttk.Label(right, text="↳ Простой NN-downscale (быстро, грубо)",
                  foreground="gray").pack(anchor="w")

        ttk.Separator(right, orient="horizontal").pack(fill="x", pady=8)

        # Chroma key
        ttk.Label(right, text="ФОН",
                  font=("Segoe UI", 9, "bold")).pack(anchor="w")
        ttk.Button(right, text="Удалить зелёный фон у ВСЕХ",
                   command=self._do_remove_chroma_all).pack(anchor="w", fill="x", pady=2)
        ttk.Button(right, text="Удалить только у активного",
                   command=self._do_remove_chroma).pack(anchor="w", fill="x", pady=2)

        ttk.Separator(right, orient="horizontal").pack(fill="x", pady=8)

        # Alignment
        ttk.Label(right, text="ВЫРАВНИВАНИЕ",
                  font=("Segoe UI", 9, "bold")).pack(anchor="w")
        ttk.Button(right, text="🔒 Foot-Baseline Lock",
                   command=self._do_foot_lock).pack(anchor="w", fill="x", pady=2)
        ttk.Button(right, text="🔒🔒 Lock ВСЕХ к baseline",
                   command=self._do_foot_lock_all).pack(anchor="w", fill="x", pady=2)
        ttk.Button(right, text="✂ Crop to Content",
                   command=self._do_crop).pack(anchor="w", fill="x", pady=2)

        ttk.Separator(right, orient="horizontal").pack(fill="x", pady=8)

        # Nudge
        ttk.Label(right, text="ТОЧНОЕ СМЕЩЕНИЕ",
                  font=("Segoe UI", 9, "bold")).pack(anchor="w")
        nudge_frame = ttk.Frame(right)
        nudge_frame.pack(anchor="w", pady=4)
        ttk.Button(nudge_frame, text="↑", width=3,
                   command=lambda: self._nudge(0, -1)).grid(row=0, column=1)
        ttk.Button(nudge_frame, text="←", width=3,
                   command=lambda: self._nudge(-1, 0)).grid(row=1, column=0)
        ttk.Button(nudge_frame, text="↓", width=3,
                   command=lambda: self._nudge(0, 1)).grid(row=1, column=1)
        ttk.Button(nudge_frame, text="→", width=3,
                   command=lambda: self._nudge(1, 0)).grid(row=1, column=2)

        ttk.Label(right, text="↳ Стрелки: 1px, Shift+Стрелки: 8px",
                  foreground="gray").pack(anchor="w")
        ttk.Label(right, text="↳ Ctrl+Z: отменить",
                  foreground="gray").pack(anchor="w")

        ttk.Separator(right, orient="horizontal").pack(fill="x", pady=8)

        # Overlay tint
        ttk.Label(right, text="ЦВЕТ СЛОЯ (для overlay)",
                  font=("Segoe UI", 9, "bold")).pack(anchor="w")
        tint_frame = ttk.Frame(right)
        tint_frame.pack(anchor="w", pady=4)
        self.tint_preview = tk.Label(tint_frame, text="    ", bg="#FFFFFF",
                                      relief="solid", borderwidth=1, width=4)
        self.tint_preview.pack(side="left", padx=4)
        ttk.Button(tint_frame, text="Цвет...",
                   command=self._pick_tint).pack(side="left", padx=4)
        ttk.Button(tint_frame, text="Auto",
                   command=self._auto_assign_tints).pack(side="left", padx=4)

        ttk.Separator(right, orient="horizontal").pack(fill="x", pady=8)

        # Reset
        ttk.Button(right, text="⟲ Сбросить активный к оригиналу",
                   command=self._reset_active).pack(anchor="w", fill="x", pady=2)
        ttk.Button(right, text="⟲⟲ Сбросить ВСЕ",
                   command=self._reset_all).pack(anchor="w", fill="x", pady=2)

        # Status bar
        self.status = ttk.Label(self.root, text="Открой папку со спрайтами",
                                relief="sunken", anchor="w")
        self.status.pack(side="bottom", fill="x")

    def _bind_keys(self):
        # Стрелки = nudge активного слоя
        self.root.bind("<Left>",  lambda e: self._nudge(-1, 0))
        self.root.bind("<Right>", lambda e: self._nudge(1, 0))
        self.root.bind("<Up>",    lambda e: self._nudge(0, -1))
        self.root.bind("<Down>",  lambda e: self._nudge(0, 1))
        self.root.bind("<Shift-Left>",  lambda e: self._nudge(-8, 0))
        self.root.bind("<Shift-Right>", lambda e: self._nudge(8, 0))
        self.root.bind("<Shift-Up>",    lambda e: self._nudge(0, -8))
        self.root.bind("<Shift-Down>",  lambda e: self._nudge(0, 8))
        self.root.bind("<Control-z>", lambda e: self._undo())
        self.root.bind("<Control-s>", lambda e: self._save_active())
        # Плеер: Space — play/pause, Esc — выйти из превью
        self.root.bind("<space>", lambda e: self._toggle_playback())
        self.root.bind("<Escape>", lambda e: self._exit_playback())

        # ── Мышь на canvas ──────────────────────────────────────────────────
        # ЛКМ + drag = pan (как в графических редакторах)
        self.canvas.bind("<ButtonPress-1>",   self._on_pan_start)
        self.canvas.bind("<B1-Motion>",       self._on_pan_drag)
        # Средняя кнопка = тоже pan
        self.canvas.bind("<ButtonPress-2>",   self._on_pan_start)
        self.canvas.bind("<B2-Motion>",       self._on_pan_drag)

        # Колесо мыши = zoom — используем bind_all + проверку под курсором,
        # потому что иначе на Windows событие летит только в виджет с фокусом
        self.root.bind_all("<MouseWheel>", self._on_mouse_wheel_global)
        self.root.bind_all("<Button-4>",  lambda e: self._on_wheel_linux(e, +1))
        self.root.bind_all("<Button-5>",  lambda e: self._on_wheel_linux(e, -1))

        # Фокус — чтобы клавиатура работала по hover
        self.canvas.bind("<Enter>", lambda e: self.canvas.focus_set())

    # ── Folder I/O ───────────────────────────────────────────────────────────

    def _open_folder(self):
        path = filedialog.askdirectory(title="Папка со спрайтами")
        if path:
            self._load_folder(Path(path))

    def _load_folder(self, folder: Path):
        self.folder = folder
        self.layers.clear()
        self.active_name = None

        png_files = sorted(folder.glob("*.png"))
        if not png_files:
            messagebox.showwarning("Пусто", f"В папке нет .png файлов:\n{folder}")
            return

        for path in png_files:
            if path.name.startswith("_"):
                continue  # пропустить служебные/processed
            try:
                img = Image.open(path).convert("RGBA")
                layer = SpriteLayer(
                    path=path,
                    original=img.copy(),
                    current=img.copy(),
                )
                self.layers[path.name] = layer
            except Exception as ex:
                print(f"  ⚠ {path.name}: {ex}")

        self._auto_assign_tints()
        self._rebuild_file_list()
        if self.layers:
            self.active_name = next(iter(self.layers))
            self._update_active_panel()
            h = next(iter(self.layers.values())).original.height
            self.baseline_y.set(int(h * 0.85))

        self._redraw()
        # Авто-fit после первого рендера (нужно дождаться чтобы canvas получил размер)
        self.root.after(100, self._zoom_fit)
        self.status.config(text=f"Загружено: {len(self.layers)} файлов из {folder}")

    # ── Video loading ────────────────────────────────────────────────────────

    def _open_video(self):
        """Открыть видео и извлечь кадры как слои."""
        video_path = filedialog.askopenfilename(
            title="Видео-файл",
            filetypes=[
                ("Видео", "*.mp4 *.webm *.mov *.avi *.mkv *.gif"),
                ("Все файлы", "*.*"),
            ],
        )
        if not video_path:
            return

        # Диалог параметров
        params = self._ask_video_params(Path(video_path))
        if params is None:
            return
        every_n, max_frames, start_frame, out_folder = params

        # Загрузка с прогрессом в статусбаре
        self.status.config(text="Загрузка видео…")
        self.root.update_idletasks()

        try:
            frames = video_mod.load_frames_list(
                Path(video_path),
                every_n=every_n,
                max_frames=max_frames,
                start_frame=start_frame,
            )
        except RuntimeError as ex:
            messagebox.showerror("Видео", str(ex))
            return
        except Exception as ex:
            messagebox.showerror("Ошибка загрузки видео", str(ex))
            return

        if not frames:
            messagebox.showwarning("Пусто", "Не удалось извлечь ни одного кадра.")
            return

        # Заполняем layers как при загрузке папки
        self.folder = out_folder
        self.layers.clear()
        self.active_name = None

        for name, img in frames:
            # path синтетический — для сохранения нужен только filename
            layer = SpriteLayer(
                path=out_folder / name,
                original=img.copy(),
                current=img.copy(),
            )
            self.layers[name] = layer

        self._auto_assign_tints()
        self._rebuild_file_list()
        if self.layers:
            self.active_name = next(iter(self.layers))
            self._update_active_panel()
            h = next(iter(self.layers.values())).original.height
            self.baseline_y.set(int(h * 0.85))

        self._redraw()
        self.root.after(100, self._zoom_fit)
        self.status.config(
            text=f"Загружено {len(self.layers)} кадров из видео → "
                 f"выход в {out_folder}"
        )

    def _ask_video_params(self, video_path: Path):
        """Маленький диалог: every_n, max_frames, start_frame, output_folder."""
        dialog = tk.Toplevel(self.root)
        dialog.title("Параметры видео")
        dialog.configure(bg=DARK["bg"])
        dialog.transient(self.root)
        dialog.grab_set()
        dialog.geometry("420x280")

        result = {"ok": False}

        # Подсказка: число кадров
        total = video_mod.count_frames(video_path)
        info_text = f"Файл: {video_path.name}"
        if total > 0:
            info_text += f"\nКадров всего: ~{total}"
        ttk.Label(dialog, text=info_text, justify="left").pack(
            anchor="w", padx=12, pady=(10, 4))

        # every_n
        f1 = ttk.Frame(dialog); f1.pack(fill="x", padx=12, pady=4)
        ttk.Label(f1, text="Брать каждый N-й кадр:").pack(side="left")
        every_var = tk.IntVar(value=4)
        ttk.Spinbox(f1, from_=1, to=60, width=6, textvariable=every_var).pack(side="left", padx=8)

        # max_frames
        f2 = ttk.Frame(dialog); f2.pack(fill="x", padx=12, pady=4)
        ttk.Label(f2, text="Максимум кадров:").pack(side="left")
        max_var = tk.IntVar(value=24)
        ttk.Spinbox(f2, from_=1, to=500, width=6, textvariable=max_var).pack(side="left", padx=8)

        # start_frame
        f3 = ttk.Frame(dialog); f3.pack(fill="x", padx=12, pady=4)
        ttk.Label(f3, text="Пропустить кадров в начале:").pack(side="left")
        start_var = tk.IntVar(value=0)
        ttk.Spinbox(f3, from_=0, to=10000, width=6, textvariable=start_var).pack(side="left", padx=8)

        # output folder
        f4 = ttk.Frame(dialog); f4.pack(fill="x", padx=12, pady=4)
        ttk.Label(f4, text="Папка для вывода:").pack(side="left")
        default_out = str(video_path.parent / f"{video_path.stem}_frames")
        out_var = tk.StringVar(value=default_out)
        ttk.Entry(f4, textvariable=out_var, width=30).pack(side="left", padx=4, fill="x", expand=True)
        ttk.Button(f4, text="…", width=3,
                    command=lambda: out_var.set(
                        filedialog.askdirectory(initialdir=video_path.parent) or out_var.get()
                    )).pack(side="left")

        # OK / Cancel
        btns = ttk.Frame(dialog); btns.pack(fill="x", padx=12, pady=12)
        def on_ok():
            result["ok"] = True
            dialog.destroy()
        def on_cancel():
            dialog.destroy()
        ttk.Button(btns, text="Загрузить", command=on_ok).pack(side="right", padx=4)
        ttk.Button(btns, text="Отмена", command=on_cancel).pack(side="right")

        self.root.wait_window(dialog)

        if not result["ok"]:
            return None
        return (
            max(1, every_var.get()),
            max(1, max_var.get()),
            max(0, start_var.get()),
            Path(out_var.get()),
        )

    # ── Pack spritesheet ─────────────────────────────────────────────────────

    def _open_pack_dialog(self):
        """Диалог упаковки видимых слоёв в один спрайт-лист."""
        if not self.layers:
            messagebox.showinfo("Нечего паковать", "Сначала загрузи слои.")
            return

        visible_layers = [l for l in self.layers.values() if l.visible]
        if not visible_layers:
            messagebox.showwarning("Нет видимых слоёв",
                "Все слои скрыты. В спрайт идут только видимые (галочка).")
            return

        # Авто-подбор сетки
        n = len(visible_layers)
        suggest_cols = 4 if n > 4 else n
        suggest_rows = (n + suggest_cols - 1) // suggest_cols

        # Размер клетки — берём из активного слоя
        active = self._active()
        if active:
            cell_suggest = max(active.current.size)
        else:
            cell_suggest = 96

        dialog = tk.Toplevel(self.root)
        dialog.title("Упаковка в спрайт-лист")
        dialog.configure(bg=DARK["bg"])
        dialog.transient(self.root)
        dialog.grab_set()
        dialog.geometry("440x330")

        result = {"ok": False}

        ttk.Label(dialog,
            text=f"Видимых слоёв: {n} (только видимые попадут в спрайт)",
            justify="left").pack(anchor="w", padx=12, pady=(10, 8))

        def row(parent, label):
            f = ttk.Frame(parent); f.pack(fill="x", padx=12, pady=3)
            ttk.Label(f, text=label, width=22).pack(side="left")
            return f

        f = row(dialog, "Размер клетки (Ш × В):")
        cw_var = tk.IntVar(value=cell_suggest)
        ch_var = tk.IntVar(value=cell_suggest)
        ttk.Spinbox(f, from_=8, to=512, width=6, textvariable=cw_var).pack(side="left")
        ttk.Label(f, text=" × ").pack(side="left")
        ttk.Spinbox(f, from_=8, to=512, width=6, textvariable=ch_var).pack(side="left")

        f = row(dialog, "Сетка (cols × rows):")
        cols_var = tk.IntVar(value=suggest_cols)
        rows_var = tk.IntVar(value=suggest_rows)
        ttk.Spinbox(f, from_=1, to=20, width=6, textvariable=cols_var).pack(side="left")
        ttk.Label(f, text=" × ").pack(side="left")
        ttk.Spinbox(f, from_=1, to=20, width=6, textvariable=rows_var).pack(side="left")

        f = row(dialog, "Action (для манифеста):")
        action_var = tk.StringVar(value="walk")
        ttk.Combobox(f, textvariable=action_var, width=14,
                      values=["idle", "walk", "attack", "hurt", "jump", "death"]
                      ).pack(side="left")

        f = row(dialog, "Direction:")
        dir_var = tk.StringVar(value="s")
        ttk.Combobox(f, textvariable=dir_var, width=14,
                      values=["s", "n", "e", "w", "ne", "nw", "se", "sw"]
                      ).pack(side="left")

        f = row(dialog, "FPS:")
        fps_var = tk.IntVar(value=10)
        ttk.Spinbox(f, from_=1, to=60, width=6, textvariable=fps_var).pack(side="left")

        f = row(dialog, "Папка для вывода:")
        if self.folder:
            default_out = str(self.folder / "_spritesheet")
        else:
            default_out = ""
        out_var = tk.StringVar(value=default_out)
        ttk.Entry(f, textvariable=out_var, width=20).pack(side="left", padx=2, fill="x", expand=True)
        ttk.Button(f, text="…", width=3,
                    command=lambda: out_var.set(filedialog.askdirectory() or out_var.get())
                    ).pack(side="left")

        btns = ttk.Frame(dialog); btns.pack(fill="x", padx=12, pady=12)
        def on_ok():
            result["ok"] = True
            dialog.destroy()
        ttk.Button(btns, text="Pack", command=on_ok).pack(side="right", padx=4)
        ttk.Button(btns, text="Отмена", command=dialog.destroy).pack(side="right")

        self.root.wait_window(dialog)
        if not result["ok"]:
            return

        out_path = Path(out_var.get())
        if not str(out_path):
            messagebox.showerror("Ошибка", "Не указана папка вывода.")
            return

        # Сборка кадров с учётом offset (чтобы правки в редакторе применились)
        prepared = []
        for layer in visible_layers:
            w, h = layer.current.size
            composite = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            composite.paste(layer.current, (layer.offset_x, layer.offset_y), layer.current)
            prepared.append(composite)

        cell_w = max(8, int(cw_var.get()))
        cell_h = max(8, int(ch_var.get()))
        cols = max(1, int(cols_var.get()))
        rows = max(1, int(rows_var.get()))

        sheet = ss_mod.pack_spritesheet(prepared, cell_w, cell_h, cols, rows)
        manifest = ss_mod.build_manifest(
            action=action_var.get(),
            direction=dir_var.get(),
            frame_count=min(len(prepared), cols * rows),
            cell_w=cell_w, cell_h=cell_h,
            cols=cols, rows=rows,
            fps=int(fps_var.get()),
        )

        png_path, json_path = ss_mod.save_spritesheet(sheet, manifest, out_path)
        self.status.config(text=f"✓ Spritesheet: {png_path}")
        messagebox.showinfo("Готово",
            f"Спрайт-лист сохранён:\n\n"
            f"  {png_path}\n  {json_path}\n\n"
            f"Кадров: {min(len(prepared), cols * rows)} в сетке {cols}×{rows}\n"
            f"Размер клетки: {cell_w}×{cell_h}"
        )

    # ── Save (folder mode) ───────────────────────────────────────────────────

    def _save_active(self):
        if not self.active_name:
            return
        out = self._save_layer(self.layers[self.active_name])
        self.status.config(text=f"Сохранено: {out}")

    def _save_all(self):
        count = 0
        for layer in self.layers.values():
            self._save_layer(layer)
            count += 1
        self.status.config(text=f"Сохранено файлов: {count} в {self.folder / OUTPUT_SUBFOLDER}")

    def _save_layer(self, layer: SpriteLayer) -> Path:
        out_dir = self.folder / OUTPUT_SUBFOLDER
        out_dir.mkdir(parents=True, exist_ok=True)
        # Применить offset к итоговому изображению: сдвигаем содержимое внутри холста
        w, h = layer.current.size
        composite = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        composite.paste(layer.current, (layer.offset_x, layer.offset_y), layer.current)
        out_path = out_dir / layer.path.name
        composite.save(out_path)
        return out_path

    # ── File list panel ──────────────────────────────────────────────────────

    def _rebuild_file_list(self):
        """Полная перестройка — только при загрузке/смене набора слоёв."""
        for w in self.file_list_frame.winfo_children():
            w.destroy()
        # Запоминаем виджеты для инкрементальных апдейтов
        self._file_rows: dict[str, dict] = {}

        for name, layer in self.layers.items():
            row = ttk.Frame(self.file_list_frame)
            row.pack(fill="x", padx=2, pady=1)

            vis_var = tk.BooleanVar(value=layer.visible)
            cb = ttk.Checkbutton(row, variable=vis_var,
                                  command=lambda n=name, v=vis_var: self._toggle_visible(n, v))
            cb.pack(side="left")

            swatch = tk.Label(row, text=" ", bg=layer.tint_color,
                              relief="solid", borderwidth=1, width=2)
            swatch.pack(side="left", padx=2)

            is_active = (name == self.active_name)
            btn = tk.Button(
                row, text=name, anchor="w",
                relief="flat", borderwidth=0,
                bg=(DARK["list_active"] if is_active else DARK["list_inactive"]),
                fg=(DARK["fg_active"] if is_active else DARK["fg"]),
                activebackground=DARK["bg_active"],
                activeforeground=DARK["fg_active"],
                command=lambda n=name: self._set_active(n),
            )
            btn.pack(side="left", fill="x", expand=True, padx=2)

            self._file_rows[name] = {"row": row, "btn": btn, "swatch": swatch, "vis": vis_var}

    def _update_file_list_active(self, prev_name: Optional[str]):
        """
        Быстрый апдейт: перекрасить только две строки (старый + новый активный).
        Не пересоздаёт виджеты — критично при 100+ кадрах.
        """
        if not hasattr(self, "_file_rows"):
            return
        for n in (prev_name, self.active_name):
            if n and n in self._file_rows:
                is_active = (n == self.active_name)
                self._file_rows[n]["btn"].config(
                    bg=(DARK["list_active"] if is_active else DARK["list_inactive"]),
                    fg=(DARK["fg_active"] if is_active else DARK["fg"]),
                )

    def _update_file_list_swatch(self, name: str):
        """Обновить цветной квадратик у одного слоя."""
        if hasattr(self, "_file_rows") and name in self._file_rows:
            self._file_rows[name]["swatch"].config(bg=self.layers[name].tint_color)

    def _toggle_visible(self, name: str, var: tk.BooleanVar):
        layer = self.layers[name]
        layer.visible = var.get()
        # Освобождаем кэш скрытого слоя — иначе при 100+ кадрах быстро OOM
        if not layer.visible:
            layer._tinted_cache = None
            layer._tint_key = None
            layer.invalidate_cache()
        # Если в плейбэке — замкнуть индекс по новому числу видимых
        if self.playback_on:
            visible = self._visible_layers_ordered()
            if not visible:
                self._exit_playback()
                return
            self.playback_idx %= len(visible)
        self._update_frame_indicator()
        self._redraw()

    def _set_active(self, name: str):
        if self.playback_on:
            self._exit_playback()
        prev = self.active_name
        self.active_name = name
        # Не пересоздаём всю панель — только перекрасим две строки
        self._update_file_list_active(prev)
        self._update_active_panel()
        self._redraw()

    def _update_active_panel(self):
        if not self.active_name:
            self.active_label.config(text="(нет активного слоя)")
            self.info_label.config(text="")
            return
        layer = self.layers[self.active_name]
        self.active_label.config(text=f"● {self.active_name}")
        w, h = layer.current.size
        # Найти нижний и верхний непрозрачный пиксель
        arr = np.array(layer.current)
        if arr.shape[2] == 4:
            alpha = arr[:, :, 3]
            rows = np.where(alpha.max(axis=1) > 0)[0]
            if len(rows) > 0:
                top, bottom = int(rows[0]), int(rows[-1])
                foot_on_canvas = bottom + layer.offset_y
                info = (
                    f"Размер:    {w}×{h}\n"
                    f"Offset:    ({layer.offset_x:+d}, {layer.offset_y:+d})\n"
                    f"Top px:    y={top + layer.offset_y}\n"
                    f"Foot px:   y={foot_on_canvas}\n"
                    f"Высота:    {bottom - top + 1}px\n"
                    f"Cell snap: {layer.snap_cell}\n"
                    f"Chroma:    {'удалён' if layer.chroma_removed else 'есть'}"
                )
            else:
                info = f"Размер: {w}×{h}\n(пусто)"
        else:
            info = f"Размер: {w}×{h}"
        self.info_label.config(text=info)
        self.tint_preview.config(bg=layer.tint_color)
        self.cell_var.set(layer.snap_cell)

    # ── Canvas rendering ─────────────────────────────────────────────────────

    def _on_zoom_changed(self):
        """Вызывается при выборе из Combobox."""
        try:
            val = self.zoom_var.get().rstrip("%")
            pct = int(val) / 100.0
        except (ValueError, AttributeError):
            return
        self.view_scale = max(ZOOM_MIN, min(ZOOM_MAX, pct))
        self._redraw()

    def _set_zoom_label(self):
        pct = int(round(self.view_scale * 100))
        self.zoom_var.set(f"{pct}%")

    def _next_zoom_level(self, direction: int) -> float:
        """Возвращает следующий уровень zoom в направлении +1 / -1."""
        # Найти ближайший уровень
        if direction > 0:
            for z in ZOOM_LEVELS:
                if z > self.view_scale + 1e-6:
                    return z
            return ZOOM_LEVELS[-1]
        else:
            for z in reversed(ZOOM_LEVELS):
                if z < self.view_scale - 1e-6:
                    return z
            return ZOOM_LEVELS[0]

    def _zoom_step_at_center(self, direction: int):
        """Zoom от центра видимой области (кнопки +/−)."""
        new_scale = self._next_zoom_level(direction)
        if new_scale == self.view_scale:
            return

        # Центр текущего вьюпорта в canvas-координатах
        cw = self.canvas.winfo_width()
        ch = self.canvas.winfo_height()
        cx = self.canvas.canvasx(cw // 2)
        cy = self.canvas.canvasy(ch // 2)
        img_x = cx / self.view_scale
        img_y = cy / self.view_scale

        self.view_scale = new_scale
        self._set_zoom_label()
        self._redraw()

        new_cx = img_x * new_scale
        new_cy = img_y * new_scale
        bbox = self.canvas.bbox("all")
        if bbox:
            total_w = max(1, bbox[2])
            total_h = max(1, bbox[3])
            self.canvas.xview_moveto(max(0, (new_cx - cw // 2) / total_w))
            self.canvas.yview_moveto(max(0, (new_cy - ch // 2) / total_h))

    def _zoom_fit(self):
        """Подобрать zoom чтобы все слои поместились в видимой области."""
        if not self.layers:
            return
        max_w = max(l.current.size[0] for l in self.layers.values())
        max_h = max(l.current.size[1] for l in self.layers.values())
        cw = max(100, self.canvas.winfo_width() - 20)
        ch = max(100, self.canvas.winfo_height() - 20)
        fit = min(cw / max_w, ch / max_h)
        # Снап к ближайшему уровню снизу
        chosen = ZOOM_LEVELS[0]
        for z in ZOOM_LEVELS:
            if z <= fit:
                chosen = z
        self.view_scale = chosen
        self._set_zoom_label()
        self._redraw()
        self.canvas.xview_moveto(0)
        self.canvas.yview_moveto(0)

    def _redraw(self):
        """Полная перерисовка. Использует двухуровневый кэш у каждого слоя."""
        self.canvas.delete("all")
        for layer in self.layers.values():
            layer._canvas_item = None
        # delete("all") инвалидировал и playback item
        self._playback_item = None

        if not self.layers:
            return

        max_w = max(l.current.size[0] for l in self.layers.values())
        max_h = max(l.current.size[1] for l in self.layers.values())
        scale = self.view_scale
        view_w = max(1, int(max_w * scale))
        view_h = max(1, int(max_h * scale))
        self.canvas.config(scrollregion=(0, 0, view_w, view_h))

        self.canvas.create_rectangle(0, 0, view_w, view_h,
                                      fill=DARK["canvas_bg"], outline="")

        # Режим плеера — показываем только один кадр с реальными цветами
        if self.playback_on:
            visible = self._visible_layers_ordered()
            if visible:
                idx = self.playback_idx % len(visible)
                current = visible[idx]
                # Найти имя слоя
                name = next(n for n, l in self.layers.items() if l is current)
                draw_order = [(name, current)]
            else:
                draw_order = []
        else:
            # Обычный overlay-режим: неактивные силуэтами, активный сверху
            draw_order = [
                (name, layer) for name, layer in self.layers.items()
                if layer.visible and name != self.active_name
            ]
            if self.active_name and self.layers[self.active_name].visible:
                draw_order.append((self.active_name, self.layers[self.active_name]))

        for name, layer in draw_order:
            # В плейбэке единственный отрисовываемый кадр всегда «активный»
            # (реальные цвета, полная непрозрачность).
            is_active = self.playback_on or (name == self.active_name)

            if is_active:
                # Реальные цвета, без тинта, полная непрозрачность
                tint_key = ("real", id(layer.current))
                cache_key = (scale, "real", id(layer.current))
            else:
                # Плоский силуэт цвета слоя, прозрачный
                tint_key = ("sil", layer.tint_color, 120, id(layer.current))
                cache_key = (scale, "sil", layer.tint_color, id(layer.current))

            if layer._cache_key != cache_key:
                if getattr(layer, "_tint_key", None) != tint_key:
                    if is_active:
                        # Никаких преобразований цвета — просто RGBA
                        layer._tinted_cache = layer.current.convert("RGBA")
                    else:
                        layer._tinted_cache = self._apply_silhouette(
                            layer.current, layer.tint_color, alpha=120
                        )
                    layer._tint_key = tint_key

                tinted = layer._tinted_cache
                tw = max(1, int(tinted.size[0] * scale))
                th = max(1, int(tinted.size[1] * scale))
                scaled = tinted.resize((tw, th), Image.NEAREST)
                layer._cached_photo = ImageTk.PhotoImage(scaled)
                layer._cache_key = cache_key

            layer._canvas_item = self.canvas.create_image(
                int(layer.offset_x * scale),
                int(layer.offset_y * scale),
                anchor="nw",
                image=layer._cached_photo,
            )
            # В плейбэке отрисовывается ровно один кадр — запоминаем его item
            # для последующих fast-path обновлений
            if self.playback_on:
                self._playback_item = layer._canvas_item

        # Overlays
        if self.show_baseline.get():
            y = int(self.baseline_y.get() * scale)
            self.canvas.create_line(0, y, view_w, y, fill="#ff5555",
                                     width=1, dash=(4, 4))
            self.canvas.create_text(4, y - 8, anchor="nw",
                                     text=f"baseline y={self.baseline_y.get()}",
                                     fill="#ff8888", font=("Consolas", 9))

        if self.show_center.get():
            x = int((max_w // 2) * scale)
            self.canvas.create_line(x, 0, x, view_h, fill="#55ccff",
                                     width=1, dash=(4, 4))

        if self.show_grid.get() and scale >= 4.0:
            cell = self.layers[self.active_name].snap_cell if self.active_name else DEFAULT_CELL_SIZE
            step = max(1, int(cell * scale))
            for x in range(0, view_w, step):
                self.canvas.create_line(x, 0, x, view_h, fill="#555555")
            for y in range(0, view_h, step):
                self.canvas.create_line(0, y, view_w, y, fill="#555555")

    def _move_active_only(self):
        """Быстрое обновление позиций без пересоздания изображений (для nudge)."""
        scale = self.view_scale
        for name, layer in self.layers.items():
            if layer._canvas_item is not None:
                self.canvas.coords(
                    layer._canvas_item,
                    int(layer.offset_x * scale),
                    int(layer.offset_y * scale),
                )

    # ── Playback (превью анимации) ───────────────────────────────────────────

    def _visible_layers_ordered(self) -> list:
        """Список видимых слоёв в порядке отрисовки (= порядок в dict)."""
        return [l for l in self.layers.values() if l.visible]

    def _toggle_playback(self):
        """Play ↔ Pause. Если ещё не в режиме плеера — запустить."""
        visible = self._visible_layers_ordered()
        if len(visible) < 2:
            self.status.config(text="Для превью нужно ≥ 2 видимых кадра")
            return

        if self.playback_after_id is not None:
            # Сейчас играет — на паузу
            self._stop_timer()
            self.play_btn.config(text="▶ Play")
            self.status.config(text=f"Пауза на кадре {self.playback_idx + 1}/{len(visible)}")
        else:
            # Запустить (или возобновить)
            first_entry = not self.playback_on
            self.playback_on = True
            self.play_btn.config(text="⏸ Pause")
            self._update_frame_indicator()
            if first_entry:
                # Чистим canvas от overlay-вида, создаём один shared playback item
                self._redraw()
            else:
                # Просто возобновили паузу — ничего не дёргаем
                pass
            self._schedule_next_tick()
            self.status.config(text="▶ Воспроизведение")

    def _schedule_next_tick(self):
        fps = max(1, int(self.play_fps.get()))
        delay_ms = max(16, int(1000 / fps))
        self.playback_after_id = self.root.after(delay_ms, self._play_tick)

    def _play_tick(self):
        """Один такт таймера — следующий кадр (fast path, без delete('all'))."""
        visible = self._visible_layers_ordered()
        if not visible:
            self._stop_timer()
            self.playback_on = False
            return
        self.playback_idx = (self.playback_idx + 1) % len(visible)
        self._update_frame_indicator()
        self._fast_playback_redraw()
        self._schedule_next_tick()

    def _fast_playback_redraw(self):
        """
        Hot path плейбэка: только подменяет image у одного canvas item.
        НЕ дёргает delete('all'), не пересоздаёт chrome (baseline, центр).
        """
        visible = self._visible_layers_ordered()
        if not visible:
            return
        layer = visible[self.playback_idx % len(visible)]

        # Убедиться что фотка готова под текущий scale в режиме real-color
        scale = self.view_scale
        cache_key = (scale, "real", id(layer.current))
        if layer._cache_key != cache_key:
            tint_key = ("real", id(layer.current))
            if getattr(layer, "_tint_key", None) != tint_key:
                layer._tinted_cache = layer.current.convert("RGBA")
                layer._tint_key = tint_key
            tinted = layer._tinted_cache
            tw = max(1, int(tinted.size[0] * scale))
            th = max(1, int(tinted.size[1] * scale))
            scaled = tinted.resize((tw, th), Image.NEAREST)
            layer._cached_photo = ImageTk.PhotoImage(scaled)
            layer._cache_key = cache_key

        x = int(layer.offset_x * scale)
        y = int(layer.offset_y * scale)

        if self._playback_item is None:
            # Первый такт после старта плейбэка — создаём item
            self._playback_item = self.canvas.create_image(
                x, y, anchor="nw", image=layer._cached_photo
            )
        else:
            self.canvas.itemconfigure(self._playback_item, image=layer._cached_photo)
            self.canvas.coords(self._playback_item, x, y)

    def _stop_timer(self):
        if self.playback_after_id is not None:
            self.root.after_cancel(self.playback_after_id)
            self.playback_after_id = None

    def _scrub(self, target_idx: int):
        """Прыжок на конкретный кадр."""
        visible = self._visible_layers_ordered()
        if not visible:
            return
        self._stop_timer()
        self.play_btn.config(text="▶ Play")
        first_entry = not self.playback_on
        self.playback_on = True
        self.playback_idx = target_idx % len(visible)
        self._update_frame_indicator()
        if first_entry:
            self._redraw()      # переход overlay → playback (один раз)
        else:
            self._fast_playback_redraw()
        self.status.config(text=f"Кадр {self.playback_idx + 1}/{len(visible)}")

    def _exit_playback(self):
        """Выйти из режима превью обратно к overlay-виду."""
        if not self.playback_on:
            return
        self._stop_timer()
        self.playback_on = False
        self.play_btn.config(text="▶ Play")
        self._update_frame_indicator()
        self._redraw()

    def _update_frame_indicator(self):
        total = len(self._visible_layers_ordered())
        if self.playback_on and total > 0:
            self.frame_indicator.config(text=f"{self.playback_idx + 1} / {total}")
        else:
            self.frame_indicator.config(text=f"– / {total}")

    def _apply_tint(self, img: Image.Image, hex_color: str, alpha: int = 255) -> Image.Image:
        """Умножает RGB на цвет тинта (сохраняет затенения)."""
        if hex_color.upper() == "#FFFFFF" and alpha == 255:
            return img
        rgba = img.convert("RGBA")
        arr = np.array(rgba).astype(np.float32)
        r = int(hex_color[1:3], 16) / 255.0
        g = int(hex_color[3:5], 16) / 255.0
        b = int(hex_color[5:7], 16) / 255.0
        arr[:, :, 0] *= r
        arr[:, :, 1] *= g
        arr[:, :, 2] *= b
        if alpha < 255:
            arr[:, :, 3] *= alpha / 255.0
        return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

    def _apply_silhouette(self, img: Image.Image, hex_color: str, alpha: int = 120) -> Image.Image:
        """
        Заменить ВСЕ непрозрачные пиксели на сплошной цвет (плоский силуэт).
        Реальные цвета изображения игнорируются, остаётся только форма.
        """
        rgba = img.convert("RGBA")
        arr = np.array(rgba)
        r = int(hex_color[1:3], 16)
        g = int(hex_color[3:5], 16)
        b = int(hex_color[5:7], 16)
        mask = arr[:, :, 3] > 0
        arr[mask, 0] = r
        arr[mask, 1] = g
        arr[mask, 2] = b
        if alpha < 255:
            a = arr[:, :, 3].astype(np.float32) * (alpha / 255.0)
            arr[:, :, 3] = a.astype(np.uint8)
        return Image.fromarray(arr, "RGBA")

    # ── Operations ───────────────────────────────────────────────────────────

    def _active(self) -> Optional[SpriteLayer]:
        return self.layers.get(self.active_name) if self.active_name else None

    def _do_pixel_snap(self):
        layer = self._active()
        if not layer:
            return
        cell = max(2, int(self.cell_var.get()))
        layer.push_history()
        layer.snap_cell = cell
        layer.current = op_pixel_snap(layer.current, cell)
        self._update_active_panel()
        self._redraw()
        self.status.config(text=f"Pixel snap применён (cell={cell})")

    def _do_remove_chroma(self):
        layer = self._active()
        if not layer:
            return
        layer.push_history()
        layer.current = op_remove_chroma(layer.current)
        layer.chroma_removed = True
        self._update_active_panel()
        self._redraw()
        self.status.config(text="Зелёный фон удалён")

    def _do_crop(self):
        layer = self._active()
        if not layer:
            return
        layer.push_history()
        cropped, dx, dy = op_crop_to_content(layer.current)
        layer.current = cropped
        # offset сместился — компенсируем
        layer.offset_x += dx
        layer.offset_y += dy
        self._update_active_panel()
        self._redraw()
        self.status.config(text="Crop применён")

    def _do_foot_lock(self):
        layer = self._active()
        if not layer:
            return
        target_y = self.baseline_y.get()
        layer.push_history()
        img, dx, dy = op_foot_baseline(layer.current, target_y)
        layer.current = img
        # Применяем смещение к offset (не двигаем содержимое внутри bbox)
        layer.offset_x = dx
        layer.offset_y = dy
        self._update_active_panel()
        self._redraw()
        self.status.config(text=f"Foot lock: ноги на y={target_y}")

    def _do_foot_lock_all(self):
        target_y = self.baseline_y.get()
        count = 0
        for layer in self.layers.values():
            layer.push_history()
            img, dx, dy = op_foot_baseline(layer.current, target_y)
            layer.current = img
            layer.offset_x = dx
            layer.offset_y = dy
            count += 1
        self._update_active_panel()
        self._redraw()
        self.status.config(text=f"Foot lock применён к {count} слоям (y={target_y})")

    def _nudge(self, dx: int, dy: int):
        layer = self._active()
        if not layer:
            return
        layer.offset_x += dx
        layer.offset_y += dy
        self._update_active_panel()
        # Быстро: только сдвинуть позиции на canvas без перерисовки
        self._move_active_only()

    def _undo(self):
        layer = self._active()
        if not layer:
            return
        if layer.undo():
            self._update_active_panel()
            self._redraw()
            self.status.config(text="Undo")

    def _reset_active(self):
        layer = self._active()
        if not layer:
            return
        layer.current = layer.original.copy()
        layer.offset_x = 0
        layer.offset_y = 0
        layer.chroma_removed = False
        layer.history.clear()
        self._update_active_panel()
        self._redraw()
        self.status.config(text="Сброшен к оригиналу")

    def _reset_all(self):
        if not messagebox.askyesno("Подтверждение", "Сбросить ВСЕ слои к оригиналу?"):
            return
        for layer in self.layers.values():
            layer.current = layer.original.copy()
            layer.offset_x = 0
            layer.offset_y = 0
            layer.chroma_removed = False
            layer.history.clear()
        self._update_active_panel()
        self._redraw()

    # ── Mouse: pan & zoom ────────────────────────────────────────────────────

    def _on_pan_start(self, event):
        self.canvas.scan_mark(event.x, event.y)

    def _on_pan_drag(self, event):
        self.canvas.scan_dragto(event.x, event.y, gain=1)

    def _on_mouse_wheel_global(self, event):
        """
        Глобальный хендлер колеса. Срабатывает только если курсор над canvas.
        Windows: event.delta = ±120 на щелчок.
        """
        widget = self.root.winfo_containing(event.x_root, event.y_root)
        if widget is not self.canvas:
            return
        # Преобразуем координаты в canvas-relative
        event.x = event.x_root - self.canvas.winfo_rootx()
        event.y = event.y_root - self.canvas.winfo_rooty()
        direction = 1 if event.delta > 0 else -1
        self._zoom_step(direction, event)

    def _on_wheel_linux(self, event, direction):
        widget = self.root.winfo_containing(event.x_root, event.y_root)
        if widget is not self.canvas:
            return
        event.x = event.x_root - self.canvas.winfo_rootx()
        event.y = event.y_root - self.canvas.winfo_rooty()
        self._zoom_step(direction, event)

    def _zoom_step(self, direction: int, event):
        """Изменить zoom с фокусом на курсор. Использует уровни ZOOM_LEVELS."""
        new_scale = self._next_zoom_level(direction)
        if new_scale == self.view_scale:
            return

        canvas_x = self.canvas.canvasx(event.x)
        canvas_y = self.canvas.canvasy(event.y)
        img_x = canvas_x / self.view_scale
        img_y = canvas_y / self.view_scale

        self.view_scale = new_scale
        self._set_zoom_label()
        self._redraw()

        new_canvas_x = img_x * new_scale
        new_canvas_y = img_y * new_scale
        bbox = self.canvas.bbox("all")
        if bbox:
            total_w = max(1, bbox[2])
            total_h = max(1, bbox[3])
            self.canvas.xview_moveto(max(0, (new_canvas_x - event.x) / total_w))
            self.canvas.yview_moveto(max(0, (new_canvas_y - event.y) / total_h))

    # ── New operations: Smart Snap, Force Size, Remove chroma all ────────────

    def _do_smart_snap(self):
        layer = self._active()
        if not layer:
            return
        layer.push_history()
        k = max(4, int(self.kcolors_var.get()))
        result, detected_cell = op_smart_snap(layer.current, k_colors=k, cell_size=None)
        layer.current = result
        layer.snap_cell = detected_cell
        self.cell_var.set(detected_cell)
        self._update_active_panel()
        self._redraw()
        self.status.config(text=f"Smart Snap: k={k} colors, detected cell={detected_cell}px")

    def _do_resize_active(self):
        layer = self._active()
        if not layer:
            return
        target = max(16, int(self.force_size_var.get()))
        old_size = layer.current.size
        layer.push_history()
        layer.current = op_resize_to(layer.current, target)
        # Offset сбрасываем — он был для другого размера холста
        layer.offset_x = 0
        layer.offset_y = 0
        new_size = layer.current.size
        self._update_active_panel()
        self._redraw()
        self.status.config(
            text=f"Resize: {old_size[0]}×{old_size[1]} → {new_size[0]}×{new_size[1]}"
        )

    def _do_resize_all(self):
        if not self.layers:
            return
        target = max(16, int(self.force_size_var.get()))
        count = 0
        for layer in self.layers.values():
            layer.push_history()
            layer.current = op_resize_to(layer.current, target)
            layer.offset_x = 0
            layer.offset_y = 0
            count += 1
        # Подстроить baseline под новый размер картинок
        if self.layers:
            new_h = next(iter(self.layers.values())).current.height
            self.baseline_y.set(int(new_h * 0.85))
        self._update_active_panel()
        self._redraw()
        # Авто-Fit после ресайза — иначе персонажи будут крошечной точкой
        self.root.after(50, self._zoom_fit)
        self.status.config(
            text=f"Resize применён к {count} слоям → {target}px по длинной стороне"
        )

    def _do_remove_chroma_all(self):
        count = 0
        for layer in self.layers.values():
            layer.push_history()
            layer.current = op_remove_chroma(layer.current)
            layer.chroma_removed = True
            count += 1
        self._update_active_panel()
        self._redraw()
        self.status.config(text=f"Зелёный фон удалён у {count} слоёв")

    # ── Tints ────────────────────────────────────────────────────────────────

    def _pick_tint(self):
        layer = self._active()
        if not layer:
            return
        color = colorchooser.askcolor(initialcolor=layer.tint_color)
        if color and color[1]:
            layer.tint_color = color[1].upper()
            self._update_active_panel()
            self._rebuild_file_list()
            self._redraw()

    def _auto_assign_tints(self):
        for i, layer in enumerate(self.layers.values()):
            layer.tint_color = OVERLAY_TINTS[i % len(OVERLAY_TINTS)]
        if self.active_name:
            self._update_active_panel()
        self._rebuild_file_list()
        self._redraw()


# ═══════════════════════════════════════════════════════════════════════════════
#   ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    initial = None
    if len(sys.argv) > 1:
        initial = Path(sys.argv[1])

    root = tk.Tk()
    app = SpriteEditor(root, initial_folder=initial)
    root.mainloop()


if __name__ == "__main__":
    main()
