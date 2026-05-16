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

if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout.reconfigure(encoding="utf-8")


# ═══════════════════════════════════════════════════════════════════════════════
#   КОНФИГ
# ═══════════════════════════════════════════════════════════════════════════════

CANVAS_W = 800
CANVAS_H = 800
DEFAULT_VIEW_SCALE = 1            # zoom of display
DEFAULT_CELL_SIZE = 10            # native pixel for snap
CHROMA_TOLERANCE = 50
OUTPUT_SUBFOLDER = "_processed"
STATE_FILE = "_editor_state.json"

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
    snap_cell: int = DEFAULT_CELL_SIZE   # размер native-пикселя для snap
    chroma_removed: bool = False
    # undo stack — список снимков (current, offset_x, offset_y)
    history: list = field(default_factory=list)

    def push_history(self):
        self.history.append((self.current.copy(), self.offset_x, self.offset_y))
        if len(self.history) > 30:
            self.history.pop(0)

    def undo(self) -> bool:
        if not self.history:
            return False
        self.current, self.offset_x, self.offset_y = self.history.pop()
        return True


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


def op_force_size(img: Image.Image, target_size: int) -> Image.Image:
    """
    Уменьшить изображение до target_size (по длинной стороне) через BOX-фильтр,
    затем NN-увеличить обратно. Жёстко привязывает к пиксельной сетке.
    Хорошо для устранения «мыла».
    """
    w, h = img.size
    if w >= h:
        new_w = target_size
        new_h = max(1, round(h * target_size / w))
    else:
        new_h = target_size
        new_w = max(1, round(w * target_size / h))
    small = img.resize((new_w, new_h), Image.BOX)
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
        self.view_scale: int = DEFAULT_VIEW_SCALE
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

    def _build_ui(self):
        # Top toolbar
        top = ttk.Frame(self.root)
        top.pack(side="top", fill="x", padx=4, pady=4)

        ttk.Button(top, text="📂 Открыть папку", command=self._open_folder).pack(side="left")
        ttk.Button(top, text="💾 Сохранить активный", command=self._save_active).pack(side="left", padx=(8, 0))
        ttk.Button(top, text="💾💾 Сохранить ВСЕ", command=self._save_all).pack(side="left", padx=(4, 0))

        ttk.Separator(top, orient="vertical").pack(side="left", fill="y", padx=10)

        ttk.Label(top, text="Zoom:").pack(side="left")
        self.zoom_var = tk.IntVar(value=DEFAULT_VIEW_SCALE)
        zoom_spin = ttk.Spinbox(top, from_=1, to=6, width=4, textvariable=self.zoom_var,
                                command=self._on_zoom_changed)
        zoom_spin.pack(side="left", padx=(4, 12))

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

        canvas = tk.Canvas(list_frame, highlightthickness=0)
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

        self.canvas = tk.Canvas(center, bg="#1e1e1e", highlightthickness=0)
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

        # Force Size (downscale → upscale)
        size_frame = ttk.Frame(right)
        size_frame.pack(anchor="w", fill="x", pady=(6, 2))
        ttk.Label(size_frame, text="Размер:").pack(side="left")
        self.force_size_var = tk.IntVar(value=96)
        ttk.Spinbox(size_frame, from_=16, to=512, increment=16,
                    width=5, textvariable=self.force_size_var).pack(side="left", padx=2)
        ttk.Button(size_frame, text="📐 Force", width=10,
                   command=self._do_force_size).pack(side="left", padx=2)
        ttk.Label(right, text="↳ 96/128 для пиксель-арта, 1px = 1 пиксель",
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

        # ── Мышь на canvas ──────────────────────────────────────────────────
        # ЛКМ + drag = pan (как в графических редакторах)
        self.canvas.bind("<ButtonPress-1>",   self._on_pan_start)
        self.canvas.bind("<B1-Motion>",       self._on_pan_drag)
        # Средняя кнопка = тоже pan (запасной вариант)
        self.canvas.bind("<ButtonPress-2>",   self._on_pan_start)
        self.canvas.bind("<B2-Motion>",       self._on_pan_drag)

        # Колесо мыши = zoom (Windows: <MouseWheel>, Linux: Button-4/5)
        self.canvas.bind("<MouseWheel>",      self._on_mouse_wheel)
        self.canvas.bind("<Button-4>",        lambda e: self._zoom_step(+1, e))
        self.canvas.bind("<Button-5>",        lambda e: self._zoom_step(-1, e))
        # Чтобы canvas получал клавиатурные события
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
        # Подобрать baseline по высоте первой картинки
        if self.layers:
            h = next(iter(self.layers.values())).original.height
            self.baseline_y.set(int(h * 0.85))
        self._redraw()
        self.status.config(text=f"Загружено: {len(self.layers)} файлов из {folder}")

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
        out_dir.mkdir(exist_ok=True)
        # Применить offset к итоговому изображению: сдвигаем содержимое внутри холста
        w, h = layer.current.size
        composite = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        composite.paste(layer.current, (layer.offset_x, layer.offset_y), layer.current)
        out_path = out_dir / layer.path.name
        composite.save(out_path)
        return out_path

    # ── File list panel ──────────────────────────────────────────────────────

    def _rebuild_file_list(self):
        for w in self.file_list_frame.winfo_children():
            w.destroy()

        for name, layer in self.layers.items():
            row = ttk.Frame(self.file_list_frame)
            row.pack(fill="x", padx=2, pady=1)

            # Visibility checkbox
            vis_var = tk.BooleanVar(value=layer.visible)
            cb = ttk.Checkbutton(row, variable=vis_var,
                                  command=lambda n=name, v=vis_var: self._toggle_visible(n, v))
            cb.pack(side="left")

            # Color swatch
            swatch = tk.Label(row, text=" ", bg=layer.tint_color,
                              relief="solid", borderwidth=1, width=2)
            swatch.pack(side="left", padx=2)

            # Active selector + name
            btn = tk.Button(
                row, text=name, anchor="w",
                relief="flat",
                bg=("#2a5d8a" if name == self.active_name else "#f0f0f0"),
                fg=("white" if name == self.active_name else "black"),
                command=lambda n=name: self._set_active(n),
            )
            btn.pack(side="left", fill="x", expand=True, padx=2)

    def _toggle_visible(self, name: str, var: tk.BooleanVar):
        self.layers[name].visible = var.get()
        self._redraw()

    def _set_active(self, name: str):
        self.active_name = name
        self._rebuild_file_list()
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
        self.view_scale = max(1, int(self.zoom_var.get()))
        self._redraw()

    def _redraw(self):
        self.canvas.delete("all")
        self._tk_images.clear()

        if not self.layers:
            return

        # Канвас рассчитываем по размеру самого большого слоя
        max_w = max(l.current.size[0] for l in self.layers.values())
        max_h = max(l.current.size[1] for l in self.layers.values())
        scale = self.view_scale
        view_w = max_w * scale
        view_h = max_h * scale
        self.canvas.config(scrollregion=(0, 0, view_w, view_h))

        # Шахматка для прозрачности (быстрая)
        self._draw_checker(view_w, view_h)

        # Рисуем все видимые слои
        for name, layer in self.layers.items():
            if not layer.visible:
                continue
            is_active = (name == self.active_name)
            # Подкрасить тинтом если не активный, или если несколько видимых
            visible_count = sum(1 for l in self.layers.values() if l.visible)
            tinted = self._apply_tint(layer.current, layer.tint_color,
                                       alpha=200 if not is_active and visible_count > 1 else 255)
            scaled = tinted.resize(
                (tinted.size[0] * scale, tinted.size[1] * scale),
                Image.NEAREST
            )
            tk_img = ImageTk.PhotoImage(scaled)
            self._tk_images.append(tk_img)
            self.canvas.create_image(
                layer.offset_x * scale,
                layer.offset_y * scale,
                anchor="nw",
                image=tk_img,
            )

        # Overlays: baseline, center, grid
        if self.show_baseline.get():
            y = self.baseline_y.get() * scale
            self.canvas.create_line(0, y, view_w, y, fill="#ff3333",
                                     width=1, dash=(4, 4))
            self.canvas.create_text(4, y - 8, anchor="nw",
                                     text=f"baseline y={self.baseline_y.get()}",
                                     fill="#ff6666", font=("Consolas", 9))

        if self.show_center.get():
            x = (max_w // 2) * scale
            self.canvas.create_line(x, 0, x, view_h, fill="#33ccff",
                                     width=1, dash=(4, 4))

        if self.show_grid.get() and scale >= 4:
            # Сетка native-пикселей
            cell = self.layers[self.active_name].snap_cell if self.active_name else DEFAULT_CELL_SIZE
            step = cell * scale
            for x in range(0, view_w, step):
                self.canvas.create_line(x, 0, x, view_h, fill="#444444")
            for y in range(0, view_h, step):
                self.canvas.create_line(0, y, view_w, y, fill="#444444")

    def _draw_checker(self, w, h, square=16):
        # Серая фоновая заливка
        self.canvas.create_rectangle(0, 0, w, h, fill="#2a2a2a", outline="")

    def _apply_tint(self, img: Image.Image, hex_color: str, alpha: int = 255) -> Image.Image:
        """Умножает RGB на цвет тинта. Прозрачность сохраняется."""
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
        self._redraw()

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

    def _on_mouse_wheel(self, event):
        """Windows: event.delta = ±120 на щелчок."""
        direction = 1 if event.delta > 0 else -1
        self._zoom_step(direction, event)

    def _zoom_step(self, direction: int, event):
        """Изменить zoom с фокусом на курсор."""
        new_scale = self.view_scale + direction
        if new_scale < 1 or new_scale > 16:
            return

        # Координата изображения под курсором сейчас
        canvas_x = self.canvas.canvasx(event.x)
        canvas_y = self.canvas.canvasy(event.y)
        img_x = canvas_x / self.view_scale
        img_y = canvas_y / self.view_scale

        self.view_scale = new_scale
        self.zoom_var.set(new_scale)
        self._redraw()

        # Прокрутить так, чтобы тот же пиксель остался под курсором
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

    def _do_force_size(self):
        layer = self._active()
        if not layer:
            return
        target = max(16, int(self.force_size_var.get()))
        layer.push_history()
        layer.current = op_force_size(layer.current, target)
        self._update_active_panel()
        self._redraw()
        self.status.config(text=f"Force size: {target}px по длинной стороне → NN upscale")

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
    try:
        # Лучший вид на Windows
        style = ttk.Style()
        if "vista" in style.theme_names():
            style.theme_use("vista")
    except Exception:
        pass

    app = SpriteEditor(root, initial_folder=initial)
    root.mainloop()


if __name__ == "__main__":
    main()
