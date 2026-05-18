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
from typing import Optional

import tkinter as tk
from tkinter import ttk, filedialog, messagebox, colorchooser

import numpy as np
from PIL import Image, ImageTk

# Локальные модули
import video as video_mod
import spritesheet as ss_mod

from config import (
    CANVAS_W, CANVAS_H, DEFAULT_VIEW_SCALE, DEFAULT_CELL_SIZE,
    CHROMA_TOLERANCE, OUTPUT_SUBFOLDER, STATE_FILE,
    ZOOM_LEVELS, ZOOM_MIN, ZOOM_MAX, OVERLAY_TINTS, DARK,
)
from sprite_layer import SpriteLayer
from image_ops import (
    op_pixel_snap, op_resize_to, op_force_size, op_smart_snap,
    op_remove_chroma, op_chroma_to_alpha, op_crop_to_content, op_foot_baseline,
    op_pad_to_canvas, build_shared_palette, op_apply_shared_palette,
)
from editor_painting import PaintMixin
from editor_playback import PlaybackMixin
from editor_filelist import FileListMixin
from editor_undo import UndoMixin

if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout.reconfigure(encoding="utf-8")



# ═══════════════════════════════════════════════════════════════════════════════
#   ГЛАВНОЕ ОКНО
# ═══════════════════════════════════════════════════════════════════════════════

class SpriteEditor(PaintMixin, PlaybackMixin, FileListMixin, UndoMixin):
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

        # ── Painting state ───────────────────────────────────────────────────
        # Tool: 'pan' | 'brush' | 'eraser' | 'broom' | 'eyedropper'
        self.tool_mode: str = "pan"
        self.paint_color: str = "#FFFFFF"
        self.brush_size: tk.IntVar = tk.IntVar(value=1)   # радиус в пикселях
        self.saved_colors: list[str] = [
            "#000000", "#FFFFFF", "#7F7F7F",
            "#E84B4B", "#F09030", "#F0D040",
            "#5BC85B", "#3B82F6", "#9B59B6",
            "#8B4513",
        ]
        # rubber-band для broom
        self._broom_rect_id: Optional[int] = None
        self._broom_start: Optional[tuple[float, float]] = None
        # для оптимизации paint-stroke
        self._paint_stroke_active: bool = False
        self._paint_last_px: Optional[tuple[int, int]] = None

        # Drag-and-drop в списке слоёв
        self._tile_drag: dict = {
            "name": None, "started": False,
            "x0": 0, "y0": 0, "highlight": None,
        }

        # Буфер обмена для кадров (Ctrl+C / X / V)
        self._clipboard_layer: Optional[SpriteLayer] = None
        self._clipboard_name: str = ""

        # Глобальная история операций (для Ctrl+Z по любому действию)
        # Каждая запись: ("image", layer) ИЛИ ("frames", snapshot, active, op_name)
        self._global_undo: list = []
        # Максимум 50 шагов — иначе память
        self.MAX_UNDO = 50

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

        # Scale (ползунок — для plays-scrubber)
        style.configure("Horizontal.TScale",
                        background=DARK["bg"],
                        troughcolor=DARK["entry_bg"],
                        bordercolor=DARK["border"],
                        darkcolor=DARK["bg_active"],
                        lightcolor=DARK["bg_active"])

        # LabelFrame
        style.configure("TLabelframe",
                        background=DARK["bg"], foreground=DARK["fg"],
                        bordercolor=DARK["border"])
        style.configure("TLabelframe.Label",
                        background=DARK["bg"], foreground=DARK["accent"])

        # Combobox
        style.configure("TCombobox",
                        fieldbackground=DARK["entry_bg"],
                        background=DARK["button_bg"],
                        foreground=DARK["fg"],
                        arrowcolor=DARK["fg"])
        style.map("TCombobox",
                  fieldbackground=[("readonly", DARK["entry_bg"])],
                  foreground=[("readonly", DARK["fg"])])

        # Дефолтные цвета для tk-виджетов (Canvas, Label-style и Button-tk в списке)
        self.root.option_add("*background", DARK["bg"])
        self.root.option_add("*foreground", DARK["fg"])
        self.root.option_add("*Canvas.background", DARK["canvas_bg"])
        self.root.option_add("*Label.background", DARK["bg"])
        self.root.option_add("*Label.foreground", DARK["fg"])

    def _build_main_menu(self, parent):
        """
        Hamburger-меню справа сверху (как New UI в PyCharm).
        Все файловые операции — здесь, чтобы не загромождать тулбар.
        """
        mb = ttk.Menubutton(parent, text="☰ Меню")
        mb.pack(side="left", padx=(0, 4))

        menu = tk.Menu(
            mb, tearoff=0,
            bg=DARK["bg_alt"], fg=DARK["fg"],
            activebackground=DARK["bg_active"], activeforeground=DARK["fg_active"],
            borderwidth=0, relief="flat",
        )
        menu.add_command(label="📂  Открыть файлы…  (заменить)",
                         command=lambda: self._open_files(append=False),
                         accelerator="Ctrl+O")
        menu.add_command(label="➕  Добавить файлы…",
                         command=lambda: self._open_files(append=True),
                         accelerator="Ctrl+Shift+O")
        menu.add_separator()
        menu.add_command(label="📁  Открыть папку…  (заменить)",
                         command=lambda: self._open_folder(append=False))
        menu.add_command(label="➕📁 Добавить из папки…",
                         command=lambda: self._open_folder(append=True))
        menu.add_separator()
        menu.add_command(label="📹  Открыть видео…", command=self._open_video)
        menu.add_separator()
        menu.add_command(label="🗑  Закрыть все слои", command=self._close_all_layers)
        menu.add_separator()
        menu.add_command(label="📋  Копировать кадр",
                         command=self._copy_active, accelerator="Ctrl+C")
        menu.add_command(label="✂️  Вырезать кадр",
                         command=self._cut_active, accelerator="Ctrl+X")
        menu.add_command(label="📥  Вставить кадр",
                         command=self._paste_clipboard, accelerator="Ctrl+V")
        menu.add_command(label="↶  Отменить",
                         command=self._undo, accelerator="Ctrl+Z")
        menu.add_separator()
        menu.add_command(label="💾  Сохранить активный",
                         command=self._save_active, accelerator="Ctrl+S")
        menu.add_command(label="💾  Сохранить все",  command=self._save_all)
        menu.add_separator()
        menu.add_command(label="🎬  Pack Spritesheet…",
                         command=self._open_pack_dialog)
        menu.add_separator()
        menu.add_command(label="🎞️  Export PNG sequence (Aseprite)…",
                         command=self._open_aseprite_png_dialog)
        menu.add_command(label="🎞️  Export Sprite Sheet (Aseprite)…",
                         command=self._open_aseprite_sheet_dialog)
        mb["menu"] = menu

        # Хоткеи
        self.root.bind("<Control-o>",       lambda e: self._open_files(append=False))
        self.root.bind("<Control-O>",       lambda e: self._open_files(append=True))
        self.root.bind("<Control-Shift-o>", lambda e: self._open_files(append=True))
        self.root.bind("<Control-Shift-O>", lambda e: self._open_files(append=True))
        self.root.bind("<Control-c>",       lambda e: self._copy_active())
        self.root.bind("<Control-x>",       lambda e: self._cut_active())
        self.root.bind("<Control-v>",       lambda e: self._paste_clipboard())

    def _build_left_panel(self, parent):
        """
        Левая колонка: инструменты рисования + палитра + zoom + проигрывание
        + baseline. Раньше всё это было в верхнем тулбаре.
        """
        outer = ttk.Frame(parent, width=240)
        outer.pack(side="left", fill="y", padx=(0, 4))
        outer.pack_propagate(False)

        # Прокручиваемая колонка (если экран маленький)
        scroll_canvas = tk.Canvas(outer, highlightthickness=0,
                                   bg=DARK["bg"], width=240)
        vs = ttk.Scrollbar(outer, orient="vertical",
                            command=scroll_canvas.yview)
        col = ttk.Frame(scroll_canvas)
        col.bind("<Configure>",
                 lambda e: scroll_canvas.configure(scrollregion=scroll_canvas.bbox("all")))
        scroll_canvas.create_window((0, 0), window=col, anchor="nw", width=222)
        scroll_canvas.configure(yscrollcommand=vs.set)
        scroll_canvas.pack(side="left", fill="both", expand=True)
        vs.pack(side="right", fill="y")

        def section(title: str):
            lf = ttk.LabelFrame(col, text=title)
            lf.pack(fill="x", padx=4, pady=4)
            return lf

        # ── ИНСТРУМЕНТЫ ────────────────────────────────────────────────────
        tools = section("Инструменты")
        self.tool_var = tk.StringVar(value="pan")

        def tool_btn(parent_, text: str, value: str, tip: str):
            b = tk.Radiobutton(
                parent_, text=text, value=value, variable=self.tool_var,
                indicatoron=False, width=4,
                bg=DARK["button_bg"], fg=DARK["fg"],
                activebackground=DARK["button_hover"], activeforeground=DARK["fg_active"],
                selectcolor=DARK["bg_active"],
                relief="flat", borderwidth=0, padx=4, pady=2,
                command=lambda: self._on_tool_changed(value),
            )
            b.pack(side="left", padx=1)
            self._add_tooltip(b, tip)
            return b

        row1 = ttk.Frame(tools); row1.pack(fill="x", pady=2)
        tool_btn(row1, "✋",  "pan",        "Pan / навигация (ЛКМ — двигать вид)")
        tool_btn(row1, "✏️", "brush",      "Кисть — рисовать выбранным цветом")
        tool_btn(row1, "🧽", "eraser",     "Ластик — стереть пиксели (alpha=0)")
        tool_btn(row1, "🧹", "broom",      "Метла — стереть пиксели в прямоугольнике")
        tool_btn(row1, "💧", "eyedropper", "Пипетка — взять цвет с изображения")

        size_row = ttk.Frame(tools); size_row.pack(fill="x", pady=2)
        ttk.Label(size_row, text="Размер кисти:").pack(side="left")
        ttk.Spinbox(size_row, from_=1, to=32, width=4,
                    textvariable=self.brush_size).pack(side="left", padx=(4, 0))

        # ── ЦВЕТ И ПАЛИТРА ─────────────────────────────────────────────────
        pal_sec = section("Цвет")
        cr = ttk.Frame(pal_sec); cr.pack(fill="x", pady=2)
        ttk.Label(cr, text="Текущий:").pack(side="left")
        self.color_preview = tk.Label(
            cr, text="    ", bg=self.paint_color,
            relief="solid", borderwidth=1, width=4,
        )
        self.color_preview.pack(side="left", padx=(4, 4))
        self.color_preview.bind("<Button-1>", lambda e: self._pick_paint_color())
        ttk.Button(cr, text="Цвет…", command=self._pick_paint_color,
                   width=8).pack(side="left")

        ttk.Button(pal_sec, text="+ Добавить в палитру",
                   command=self._save_current_color).pack(fill="x", pady=2)
        ttk.Label(pal_sec, text="Палитра (ПКМ — удалить):",
                  foreground="gray").pack(anchor="w")
        self.palette_frame = ttk.Frame(pal_sec)
        self.palette_frame.pack(fill="x", pady=2)
        self._rebuild_palette()

        ttk.Button(pal_sec, text="🗑 Очистить активный слой",
                   command=self._clear_active_layer).pack(fill="x", pady=(4, 2))

        # ── BASELINE ────────────────────────────────────────────────────────
        bs = section("Выравнивание (overlay)")
        br = ttk.Frame(bs); br.pack(fill="x", pady=2)
        ttk.Label(br, text="Baseline Y:").pack(side="left")
        baseline_spin = ttk.Spinbox(br, from_=0, to=2000, width=6,
                                    textvariable=self.baseline_y,
                                    command=self._redraw)
        baseline_spin.pack(side="left", padx=(4, 0))
        self.baseline_y.trace_add("write", lambda *a: self._redraw())

        ttk.Checkbutton(bs, text="Линия baseline", variable=self.show_baseline,
                        command=self._redraw).pack(anchor="w", pady=1)
        ttk.Checkbutton(bs, text="Линия центра", variable=self.show_center,
                        command=self._redraw).pack(anchor="w", pady=1)
        ttk.Checkbutton(bs, text="Сетка пикселей", variable=self.show_grid,
                        command=self._redraw).pack(anchor="w", pady=1)

    def _add_tooltip(self, widget, text: str):
        """Простой tooltip — подсказка при наведении."""
        tip = {"win": None}

        def show(_e):
            if tip["win"] is not None:
                return
            x = widget.winfo_rootx() + 10
            y = widget.winfo_rooty() + widget.winfo_height() + 4
            tw = tk.Toplevel(widget)
            tw.wm_overrideredirect(True)
            tw.wm_geometry(f"+{x}+{y}")
            lbl = tk.Label(tw, text=text, bg="#2a2a2a", fg="#e0e0e0",
                           relief="solid", borderwidth=1, padx=6, pady=2,
                           font=("Segoe UI", 9))
            lbl.pack()
            tip["win"] = tw

        def hide(_e):
            if tip["win"] is not None:
                tip["win"].destroy()
                tip["win"] = None

        widget.bind("<Enter>", show)
        widget.bind("<Leave>", hide)

    def _build_ui(self):
        self._apply_dark_theme()

        # Минимальная верхняя полоса — только ☰ меню
        top = ttk.Frame(self.root)
        top.pack(side="top", fill="x", padx=4, pady=4)
        self._build_main_menu(top)
        ttk.Label(top, text="Essence Limit — Sprite Editor",
                  foreground="gray").pack(side="left", padx=(8, 0))

        # Переменные, которые нужны до создания виджетов
        self.zoom_var = tk.StringVar(value=f"{int(DEFAULT_VIEW_SCALE * 100)}%")
        self.play_fps = tk.IntVar(value=10)

        # Status bar — пакуется ПЕРВЫМ среди bottom-виджетов, чтобы быть в самом низу
        self.status = ttk.Label(self.root, text="Открой папку со спрайтами",
                                relief="sunken", anchor="w")
        self.status.pack(side="bottom", fill="x")

        # ── Bottom strip — file list с превьюшками (горизонтально) ─────────
        self._build_bottom_filelist()

        # Main area
        main = ttk.Frame(self.root)
        main.pack(side="top", fill="both", expand=True, padx=4, pady=4)

        # ── Left panel: всё что раньше было сверху + инструменты рисования ──
        self._build_left_panel(main)

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
        ttk.Button(right, text="Удалить, оставив контур прозрачным",
                   command=self._do_chroma_to_alpha).pack(anchor="w", fill="x", pady=2)

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
        # ЛКМ — диспатч по выбранному инструменту
        self.canvas.bind("<ButtonPress-1>",   self._on_lmb_down)
        self.canvas.bind("<B1-Motion>",       self._on_lmb_drag)
        self.canvas.bind("<ButtonRelease-1>", self._on_lmb_up)
        # Средняя и правая кнопки — всегда pan (как в Photoshop / Aseprite)
        self.canvas.bind("<ButtonPress-2>",   self._on_pan_start)
        self.canvas.bind("<B2-Motion>",       self._on_pan_drag)
        self.canvas.bind("<ButtonPress-3>",   self._on_pan_start)
        self.canvas.bind("<B3-Motion>",       self._on_pan_drag)

        # Колесо мыши = zoom — используем bind_all + проверку под курсором,
        # потому что иначе на Windows событие летит только в виджет с фокусом
        self.root.bind_all("<MouseWheel>", self._on_mouse_wheel_global)
        self.root.bind_all("<Button-4>",  lambda e: self._on_wheel_linux(e, +1))
        self.root.bind_all("<Button-5>",  lambda e: self._on_wheel_linux(e, -1))

        # Фокус — чтобы клавиатура работала по hover
        self.canvas.bind("<Enter>", lambda e: self.canvas.focus_set())

    # ── Folder / Files I/O ───────────────────────────────────────────────────

    def _open_folder(self, append: bool = False):
        path = filedialog.askdirectory(title="Папка со спрайтами")
        if not path:
            return
        folder = Path(path)
        png_files = sorted(folder.glob("*.png"))
        png_files = [p for p in png_files if not p.name.startswith("_")]
        if not png_files:
            messagebox.showwarning("Пусто", f"В папке нет .png файлов:\n{folder}")
            return
        self._load_files(png_files, folder=folder, append=append)

    def _open_files(self, append: bool = False):
        paths = filedialog.askopenfilenames(
            title="Выбрать файлы спрайтов",
            filetypes=[("PNG", "*.png"), ("Изображения", "*.png *.jpg *.jpeg *.webp *.bmp"),
                       ("Все файлы", "*.*")],
        )
        if not paths:
            return
        files = [Path(p) for p in paths]
        # Папка для сохранения — родитель первого файла (только если режим replace)
        folder = self.folder if append and self.folder else files[0].parent
        self._load_files(files, folder=folder, append=append)

    def _load_files(self, files: list[Path], folder: Path, append: bool = False):
        """Загрузить файлы. append=True — добавить к существующим без очистки."""
        if not append:
            # Если уже что-то загружено — даём шанс на undo
            if self.layers:
                self._push_frames_undo("открыть файлы (замена)")
            self.folder = folder
            self.layers.clear()
            self.active_name = None
        else:
            # Папка остаётся прежней (если уже была)
            if self.folder is None:
                self.folder = folder

        # Защита от дубликатов имён — добавляем суффикс
        existing = set(self.layers.keys())
        added = 0
        for path in files:
            try:
                img = Image.open(path).convert("RGBA")
            except Exception as ex:
                print(f"  ⚠ {path.name}: {ex}")
                continue
            name = path.name
            if name in existing:
                stem, ext = path.stem, path.suffix
                i = 1
                while f"{stem}_{i}{ext}" in existing:
                    i += 1
                name = f"{stem}_{i}{ext}"
            existing.add(name)
            layer = SpriteLayer(
                path=path if name == path.name else path.with_name(name),
                original=img.copy(),
                current=img.copy(),
            )
            self.layers[name] = layer
            added += 1

        if not self.layers:
            messagebox.showwarning("Пусто", "Не удалось загрузить ни одного файла.")
            return

        self._auto_assign_tints()
        self._rebuild_file_list()
        if self.active_name is None:
            self.active_name = next(iter(self.layers))
            self._update_active_panel()
            h = next(iter(self.layers.values())).original.height
            self.baseline_y.set(int(h * 0.85))

        self._redraw()
        if not append:
            self.root.after(100, self._zoom_fit)
        if append:
            self.status.config(text=f"Добавлено: {added}, всего: {len(self.layers)}")
        else:
            self.status.config(text=f"Загружено: {len(self.layers)} файлов из {folder}")

    # Совместимость
    def _load_folder(self, folder: Path):
        png_files = sorted(folder.glob("*.png"))
        png_files = [p for p in png_files if not p.name.startswith("_")]
        if not png_files:
            messagebox.showwarning("Пусто", f"В папке нет .png файлов:\n{folder}")
            return
        self._load_files(png_files, folder=folder, append=False)

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
        every_n, max_frames, start_frame, resize_to, out_folder = params

        # Загрузка с прогрессом в статусбаре
        self.status.config(text="Загрузка видео…")
        self.root.update_idletasks()

        try:
            frames = video_mod.load_frames_list(
                Path(video_path),
                every_n=every_n,
                max_frames=max_frames,
                start_frame=start_frame,
                resize_to=resize_to,
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
        dialog.geometry("440x340")

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

        # resize_to — авто-ресайз при загрузке (ВАЖНО для длинных видео!)
        f_rs = ttk.Frame(dialog); f_rs.pack(fill="x", padx=12, pady=4)
        ttk.Label(f_rs, text="Ресайз при загрузке (px):").pack(side="left")
        resize_var = tk.IntVar(value=256)
        ttk.Spinbox(f_rs, from_=0, to=2048, increment=64, width=6,
                     textvariable=resize_var).pack(side="left", padx=8)
        ttk.Label(f_rs, text="0 = без ресайза", foreground="gray").pack(side="left")

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
            max(0, resize_var.get()),
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

    # ── Aseprite export ──────────────────────────────────────────────────────

    def _gather_aseprite_frames(self) -> list[Image.Image]:
        """Собрать кадры видимых слоёв с применённым offset.
        Возвращает кадры РАЗНОГО размера (унификация — на следующем шаге)."""
        frames = []
        for layer in self.layers.values():
            if not layer.visible:
                continue
            w, h = layer.current.size
            composite = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            composite.paste(layer.current, (layer.offset_x, layer.offset_y),
                            layer.current)
            frames.append(composite)
        return frames

    def _unify_frames(self, frames: list[Image.Image],
                      anchor: str) -> tuple[list[Image.Image], int, int]:
        """Подогнать все кадры к общему холсту max(w) × max(h)."""
        if not frames:
            return [], 0, 0
        target_w = max(f.size[0] for f in frames)
        target_h = max(f.size[1] for f in frames)
        out = [op_pad_to_canvas(f, target_w, target_h, anchor=anchor)
               for f in frames]
        return out, target_w, target_h

    def _maybe_quantize(self, frames: list[Image.Image],
                        k: int) -> list[Image.Image]:
        """Если k > 0 — свести все кадры к общей палитре k цветов (Indexed PNG)."""
        if k <= 0 or not frames:
            return frames
        palette = build_shared_palette(frames, k=k)
        return [op_apply_shared_palette(f, palette) for f in frames]

    def _build_aseprite_dialog(self, title: str, default_out_suffix: str):
        """Общий диалог для двух Aseprite-экспортов.
        Возвращает dict с параметрами или None, если отменили."""
        if not self.layers:
            messagebox.showinfo("Нечего экспортировать", "Сначала загрузи слои.")
            return None
        visible = [l for l in self.layers.values() if l.visible]
        if not visible:
            messagebox.showwarning("Нет видимых слоёв",
                "В экспорт идут только видимые слои (галочка).")
            return None

        dialog = tk.Toplevel(self.root)
        dialog.title(title)
        dialog.configure(bg=DARK["bg"])
        dialog.transient(self.root)
        dialog.grab_set()
        dialog.geometry("460x280")

        result = {"ok": False}

        ttk.Label(dialog, text=f"Видимых кадров: {len(visible)}",
                  justify="left").pack(anchor="w", padx=12, pady=(10, 8))

        def row(label):
            f = ttk.Frame(dialog); f.pack(fill="x", padx=12, pady=3)
            ttk.Label(f, text=label, width=24).pack(side="left")
            return f

        # Anchor (как выравнивать кадры разного размера)
        f = row("Выравнивание кадров:")
        anchor_var = tk.StringVar(value="bottom")
        ttk.Combobox(f, textvariable=anchor_var, width=14, state="readonly",
                     values=["bottom", "center", "topleft"]).pack(side="left")

        # Quantize
        f = row("Общая палитра (Indexed):")
        quant_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(f, text="Свести к палитре",
                        variable=quant_var).pack(side="left")
        k_var = tk.IntVar(value=32)
        ttk.Label(f, text="  цветов:").pack(side="left")
        ttk.Spinbox(f, from_=2, to=256, width=5,
                    textvariable=k_var).pack(side="left")

        # Output folder
        f = row("Папка для вывода:")
        if self.folder:
            default_out = str(self.folder / default_out_suffix)
        else:
            default_out = ""
        out_var = tk.StringVar(value=default_out)
        ttk.Entry(f, textvariable=out_var, width=20).pack(
            side="left", padx=2, fill="x", expand=True)
        ttk.Button(f, text="…", width=3,
                   command=lambda: out_var.set(
                       filedialog.askdirectory() or out_var.get())
                   ).pack(side="left")

        # Extra slot for caller-specific widgets
        extra_frame = ttk.Frame(dialog)
        extra_frame.pack(fill="x", padx=12, pady=4)

        btns = ttk.Frame(dialog); btns.pack(fill="x", padx=12, pady=12)
        def on_ok():
            result["ok"] = True
            dialog.destroy()
        ttk.Button(btns, text="Export", command=on_ok).pack(side="right", padx=4)
        ttk.Button(btns, text="Отмена",
                   command=dialog.destroy).pack(side="right")

        return {
            "dialog": dialog,
            "extra_frame": extra_frame,
            "result": result,
            "anchor_var": anchor_var,
            "quant_var": quant_var,
            "k_var": k_var,
            "out_var": out_var,
            "visible": visible,
        }

    def _open_aseprite_png_dialog(self):
        """Экспорт всех видимых слоёв как frame_0001.png, frame_0002.png…
        Все кадры — одного размера. Aseprite: File → Import Sprite Sheet,
        либо просто перетащить как frames."""
        ctx = self._build_aseprite_dialog(
            "Export PNG sequence (Aseprite)", "_aseprite_frames")
        if ctx is None:
            return

        # Префикс имени
        prefix_var = tk.StringVar(value="frame")
        pf = ttk.Frame(ctx["extra_frame"]); pf.pack(fill="x")
        ttk.Label(pf, text="Префикс имени файла:", width=24).pack(side="left")
        ttk.Entry(pf, textvariable=prefix_var, width=14).pack(side="left")

        self.root.wait_window(ctx["dialog"])
        if not ctx["result"]["ok"]:
            return

        out_path = Path(ctx["out_var"].get())
        if not str(out_path):
            messagebox.showerror("Ошибка", "Не указана папка вывода.")
            return
        out_path.mkdir(parents=True, exist_ok=True)

        raw = self._gather_aseprite_frames()
        unified, tw, th = self._unify_frames(raw, anchor=ctx["anchor_var"].get())
        if ctx["quant_var"].get():
            unified = self._maybe_quantize(unified, k=max(2, int(ctx["k_var"].get())))

        prefix = (prefix_var.get() or "frame").strip()
        for i, frame in enumerate(unified, start=1):
            frame.save(out_path / f"{prefix}_{i:04d}.png")

        self.status.config(text=f"✓ PNG sequence: {len(unified)} кадров → {out_path}")
        messagebox.showinfo("Готово",
            f"Экспортировано {len(unified)} кадров {tw}×{th}\n\n"
            f"  {out_path}\n\n"
            f"В Aseprite: File → Import Sprite Sheet → выбрать первый PNG\n"
            f"(или просто открыть всю папку как кадры).")

    def _open_aseprite_sheet_dialog(self):
        """Один PNG-атлас с регулярной сеткой, без foot-align — для
        Aseprite File → Import Sprite Sheet."""
        ctx = self._build_aseprite_dialog(
            "Export Sprite Sheet (Aseprite)", "_aseprite_sheet")
        if ctx is None:
            return

        n = len(ctx["visible"])
        suggest_cols = min(n, 8)
        suggest_rows = (n + suggest_cols - 1) // suggest_cols

        gf = ttk.Frame(ctx["extra_frame"]); gf.pack(fill="x")
        ttk.Label(gf, text="Сетка (cols × rows):", width=24).pack(side="left")
        cols_var = tk.IntVar(value=suggest_cols)
        rows_var = tk.IntVar(value=suggest_rows)
        ttk.Spinbox(gf, from_=1, to=64, width=5,
                    textvariable=cols_var).pack(side="left")
        ttk.Label(gf, text=" × ").pack(side="left")
        ttk.Spinbox(gf, from_=1, to=64, width=5,
                    textvariable=rows_var).pack(side="left")

        self.root.wait_window(ctx["dialog"])
        if not ctx["result"]["ok"]:
            return

        out_path = Path(ctx["out_var"].get())
        if not str(out_path):
            messagebox.showerror("Ошибка", "Не указана папка вывода.")
            return
        out_path.mkdir(parents=True, exist_ok=True)

        raw = self._gather_aseprite_frames()
        unified, cell_w, cell_h = self._unify_frames(
            raw, anchor=ctx["anchor_var"].get())
        if ctx["quant_var"].get():
            # Квантизация делается ПОСЛЕ паддинга, но ДО склейки,
            # чтобы паддинговая прозрачность не попала в палитру цветов.
            unified = self._maybe_quantize(
                unified, k=max(2, int(ctx["k_var"].get())))
            # Для атласа нужно вернуться в RGBA (паттерн 'P' с transparency
            # не склеивается в один PNG корректно через paste).
            unified = [f.convert("RGBA") for f in unified]

        cols = max(1, int(cols_var.get()))
        rows = max(1, int(rows_var.get()))
        sheet = ss_mod.pack_aseprite_sheet(
            unified, cell_w, cell_h, cols, rows,
            anchor="topleft",  # уже выровнены — кладём как есть
        )

        png_path = out_path / "spritesheet.png"
        sheet.save(png_path)

        # Манифест: совместим с уже существующим build_manifest
        manifest = ss_mod.build_manifest(
            action="anim", direction="s",
            frame_count=min(len(unified), cols * rows),
            cell_w=cell_w, cell_h=cell_h,
            cols=cols, rows=rows, fps=10,
        )
        json_path = out_path / "manifest.json"
        with open(json_path, "w", encoding="utf-8") as fjson:
            json.dump(manifest, fjson, indent=2, ensure_ascii=False)

        self.status.config(text=f"✓ Aseprite sheet: {png_path}")
        messagebox.showinfo("Готово",
            f"Атлас {cols}×{rows}, клетка {cell_w}×{cell_h}\n\n"
            f"  {png_path}\n  {json_path}\n\n"
            f"В Aseprite: File → Import Sprite Sheet →\n"
            f"  Type: Horizontal Strip / By Grid,\n"
            f"  Frame Width = {cell_w}, Frame Height = {cell_h}")

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

    # ── Bottom strip: file list с превью ─────────────────────────────────────

    THUMB_SIZE = 64        # сторона мини-превью
    TILE_W     = 110       # фикс. ширина тайла для wrap-расчёта
    TILE_H     = 130       # фикс. высота тайла

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

    # Onion-skin: сколько кадров до/после активного и их альфы.
    # Индекс = расстояние от активного (1 = соседний).
    ONION_BEFORE_COUNT = 4
    ONION_AFTER_COUNT  = 3
    ONION_ALPHA = {1: 170, 2: 115, 3: 75, 4: 45}

    def _build_onion_draw_order(self) -> list:
        """
        Список (name, layer, sil_alpha). Альфа = None для активного.
        Берём только ONION_BEFORE кадров до и ONION_AFTER после активного
        из списка ВИДИМЫХ слоёв.
        Порядок отрисовки: дальние силуэты → ближние → активный сверху.
        """
        visible_names = [n for n, l in self.layers.items() if l.visible]
        if not visible_names:
            return []

        if self.active_name not in visible_names:
            # Нет активного среди видимых — показываем только активный (если виден)
            # или вообще ничего (редкий случай).
            if self.active_name and self.layers.get(self.active_name) \
                                 and self.layers[self.active_name].visible:
                return [(self.active_name, self.layers[self.active_name], None)]
            return []

        a_idx = visible_names.index(self.active_name)
        order: list = []

        # Сначала отрисовываем САМЫЕ дальние, потом ближе — так ближние идут поверх.
        # Сначала before (4 .. 1), потом after (3 .. 1), потом активный.
        for d in range(self.ONION_BEFORE_COUNT, 0, -1):
            i = a_idx - d
            if 0 <= i < len(visible_names):
                alpha = self.ONION_ALPHA.get(d, 30)
                n = visible_names[i]
                order.append((n, self.layers[n], alpha))

        for d in range(self.ONION_AFTER_COUNT, 0, -1):
            i = a_idx + d
            if 0 <= i < len(visible_names):
                alpha = self.ONION_ALPHA.get(d, 30)
                n = visible_names[i]
                order.append((n, self.layers[n], alpha))

        # Активный — сверху, без альфы (real-color)
        order.append((self.active_name, self.layers[self.active_name], None))
        return order

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
                # 3-tuple: alpha=None означает «реальные цвета»
                draw_order = [(name, current, None)]
            else:
                draw_order = []
        else:
            # Overlay onion-skin: 4 кадра ДО + активный + 3 ПОСЛЕ.
            # Прозрачность падает с расстоянием.
            draw_order = self._build_onion_draw_order()

        for entry in draw_order:
            name, layer, sil_alpha = entry
            is_active = self.playback_on or (sil_alpha is None)

            if is_active:
                # Реальные цвета, без тинта, полная непрозрачность
                tint_key = ("real", id(layer.current))
                cache_key = (scale, "real", id(layer.current))
            else:
                # Плоский силуэт цвета слоя, прозрачность по расстоянию
                tint_key = ("sil", layer.tint_color, sil_alpha, id(layer.current))
                cache_key = (scale, "sil", layer.tint_color, sil_alpha, id(layer.current))

            if layer._cache_key != cache_key:
                if getattr(layer, "_tint_key", None) != tint_key:
                    if is_active:
                        # Никаких преобразований цвета — просто RGBA
                        layer._tinted_cache = layer.current.convert("RGBA")
                    else:
                        layer._tinted_cache = self._apply_silhouette(
                            layer.current, layer.tint_color, alpha=sil_alpha
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

        # ── Авто-обновление устаревших превьюшек ───────────────────────────
        if hasattr(self, "_file_rows"):
            for name, layer in self.layers.items():
                if name not in self._file_rows:
                    continue
                stale = getattr(layer, "_thumb_key", None) != (
                    id(layer.current), self.THUMB_SIZE
                )
                if stale:
                    self._refresh_layer_thumb(name)

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
        self._push_image_undo(layer)
        layer.snap_cell = cell
        layer.current = op_pixel_snap(layer.current, cell)
        self._update_active_panel()
        self._redraw()
        self.status.config(text=f"Pixel snap применён (cell={cell})")

    def _do_remove_chroma(self):
        layer = self._active()
        if not layer:
            return
        self._push_image_undo(layer)
        layer.current = op_remove_chroma(layer.current)
        layer.chroma_removed = True
        self._update_active_panel()
        self._redraw()
        self.status.config(text="Зелёный фон удалён")

    def _do_chroma_to_alpha(self):
        """Скрыть зелёный фон у ВСЕХ слоёв (RGB сохраняется, alpha→0
        пропорционально 'зелёности' пикселя)."""
        count = 0
        for layer in self.layers.values():
            self._push_image_undo(layer)
            layer.current = op_chroma_to_alpha(layer.current)
            layer.chroma_removed = True
            count += 1
        self._update_active_panel()
        self._redraw()
        self.status.config(
            text=f"Зелёный скрыт (alpha) у {count} слоёв, пиксели сохранены"
        )

    def _do_crop(self):
        layer = self._active()
        if not layer:
            return
        self._push_image_undo(layer)
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
        self._push_image_undo(layer)
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
            self._push_image_undo(layer)
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

    # ── Undo (общая история для image-правок и frame-операций) ───────────────

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
        self._push_image_undo(layer)
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
        self._push_image_undo(layer)
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
            self._push_image_undo(layer)
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
            self._push_image_undo(layer)
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
            # Кэш тинта инвалидируется автоматически (изменился tint_color в ключе)
            self._update_active_panel()
            self._update_file_list_swatch(self.active_name)
            self._redraw()

    def _auto_assign_tints(self):
        for i, (name, layer) in enumerate(self.layers.items()):
            layer.tint_color = OVERLAY_TINTS[i % len(OVERLAY_TINTS)]
        if self.active_name:
            self._update_active_panel()
        # Если список уже построен — обновим только swatches, иначе пересоздадим
        if hasattr(self, "_file_rows") and self._file_rows:
            for name in self.layers:
                self._update_file_list_swatch(name)
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
