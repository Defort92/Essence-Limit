"""
FileListMixin — нижняя панель со слоями: master-чекбокс, batch-операции,
тайлы с превью, drag-and-drop reorder, move/remove/active.
"""

import tkinter as tk
from tkinter import ttk, messagebox
from typing import Optional

import numpy as np
from PIL import Image, ImageTk

from config import DARK
from sprite_layer import SpriteLayer


class FileListMixin:
    THUMB_SIZE = 64
    TILE_W     = 110
    TILE_H     = 130
    DRAG_THRESHOLD = 6

    # ── Построение нижней панели ─────────────────────────────────────────────

    def _build_bottom_filelist(self):
        wrap = ttk.Frame(self.root, height=260)
        wrap.pack(side="bottom", fill="x", padx=4, pady=(0, 2))
        wrap.pack_propagate(False)

        header = ttk.Frame(wrap)
        header.pack(side="top", fill="x")

        self.master_visible = tk.BooleanVar(value=True)
        self._master_updating = False
        master_cb = ttk.Checkbutton(
            header, text="Все видимы", variable=self.master_visible,
            command=self._on_master_toggle,
        )
        master_cb.pack(side="left", padx=(2, 8))

        ttk.Button(header, text="Выбрать все",
                   command=self._select_all_visible).pack(side="left", padx=2)
        ttk.Button(header, text="Снять все",
                   command=self._select_none_visible).pack(side="left", padx=2)
        ttk.Button(header, text="Инвертировать",
                   command=self._invert_visible).pack(side="left", padx=2)

        ttk.Separator(header, orient="vertical").pack(side="left", fill="y", padx=8)
        self.count_label = ttk.Label(header, text="—", width=8)
        self.count_label.pack(side="left", padx=4)

        # Анимация — в той же строке
        ttk.Separator(header, orient="vertical").pack(side="left", fill="y", padx=8)
        self.play_btn = ttk.Button(header, text="▶ Play", width=8,
                                    command=self._toggle_playback)
        self.play_btn.pack(side="left", padx=(0, 2))
        ttk.Button(header, text="⏮", width=3,
                    command=lambda: self._scrub(0)).pack(side="left", padx=1)
        ttk.Button(header, text="◀", width=3,
                    command=lambda: self._scrub(self.playback_idx - 1)
                    ).pack(side="left", padx=1)
        ttk.Button(header, text="▶", width=3,
                    command=lambda: self._scrub(self.playback_idx + 1)
                    ).pack(side="left", padx=1)

        ttk.Label(header, text="ПКМ — меню",
                  foreground="gray").pack(side="right", padx=4)
        self.frame_indicator = ttk.Label(header, text="– / 0", width=10)
        self.frame_indicator.pack(side="right", padx=(4, 8))
        ttk.Spinbox(header, from_=1, to=60, width=4,
                     textvariable=self.play_fps).pack(side="right")
        ttk.Label(header, text="FPS:").pack(side="right", padx=(8, 2))

        self.scrub_var = tk.DoubleVar(value=0)
        self._scrub_user_dragging = False
        self._scrub_programmatic = False
        self.scrub_scale = ttk.Scale(
            header, orient="horizontal",
            from_=0, to=0, variable=self.scrub_var,
            command=self._on_scrub_change,
        )
        self.scrub_scale.pack(side="left", fill="x", expand=True, padx=8)
        self.scrub_scale.bind(
            "<ButtonPress-1>",
            lambda e: setattr(self, "_scrub_user_dragging", True)
        )
        self.scrub_scale.bind(
            "<ButtonRelease-1>",
            lambda e: setattr(self, "_scrub_user_dragging", False)
        )

        # Wrap-grid тайлов
        strip_frame = ttk.Frame(wrap)
        strip_frame.pack(side="top", fill="both", expand=True, pady=(2, 0))

        canvas = tk.Canvas(strip_frame, highlightthickness=0, bg=DARK["bg"])
        v_scroll = ttk.Scrollbar(strip_frame, orient="vertical",
                                  command=canvas.yview)
        self.file_list_frame = ttk.Frame(canvas)
        self._filelist_window_id = canvas.create_window(
            (0, 0), window=self.file_list_frame, anchor="nw"
        )
        canvas.configure(yscrollcommand=v_scroll.set)
        canvas.pack(side="left", fill="both", expand=True)
        v_scroll.pack(side="right", fill="y")
        self._filelist_canvas = canvas

        def _on_canvas_resize(e):
            canvas.itemconfigure(self._filelist_window_id, width=e.width)
            self._relayout_tiles()
        canvas.bind("<Configure>", _on_canvas_resize)

        self.file_list_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )

        # Колесо мыши над полосой = вертикальный скролл этой полосы.
        # НЕ используем bind_all/unbind_all (это убило бы глобальный zoom-handler).
        # Через bind на сам виджет — событие летит в виджет под курсором.
        def _wheel(e):
            canvas.yview_scroll(-1 if e.delta > 0 else 1, "units")
            return "break"   # не пускаем выше — иначе зум перехватит
        canvas.bind("<MouseWheel>", _wheel)

    def _relayout_tiles(self):
        if not hasattr(self, "_file_rows") or not self._file_rows:
            return
        canvas_w = self._filelist_canvas.winfo_width()
        if canvas_w <= 1:
            return
        cols = max(1, canvas_w // (self.TILE_W + 6))
        for i, name in enumerate(self.layers):
            if name not in self._file_rows:
                continue
            tile = self._file_rows[name]["tile"]
            r, c = i // cols, i % cols
            tile.grid(row=r, column=c, padx=3, pady=3, sticky="nw")

    def _make_thumb_photo(self, layer: SpriteLayer):
        key = (id(layer.current), self.THUMB_SIZE)
        cached = getattr(layer, "_thumb_key", None)
        if cached == key and getattr(layer, "_thumb_photo", None) is not None:
            return layer._thumb_photo
        img = layer.current
        w, h = img.size
        scale = self.THUMB_SIZE / max(w, h)
        tw = max(1, int(w * scale))
        th = max(1, int(h * scale))
        bg = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
        c1, c2 = (60, 60, 60, 255), (90, 90, 90, 255)
        cell = 8
        bg_arr = np.array(bg)
        for yy in range(0, th, cell):
            for xx in range(0, tw, cell):
                color = c1 if ((xx // cell) + (yy // cell)) % 2 == 0 else c2
                bg_arr[yy:yy + cell, xx:xx + cell] = color
        bg = Image.fromarray(bg_arr, "RGBA")
        thumb = img.resize((tw, th), Image.NEAREST)
        composed = Image.alpha_composite(bg, thumb)
        photo = ImageTk.PhotoImage(composed)
        layer._thumb_key = key
        layer._thumb_photo = photo
        return photo

    def _rebuild_file_list(self):
        for w in self.file_list_frame.winfo_children():
            w.destroy()
        self._file_rows: dict[str, dict] = {}

        for name, layer in self.layers.items():
            tile_bg = (DARK["list_active"] if name == self.active_name
                       else DARK["list_inactive"])
            tile = tk.Frame(self.file_list_frame,
                             bg=tile_bg, relief="flat", borderwidth=2,
                             padx=4, pady=2,
                             width=self.TILE_W, height=self.TILE_H)
            tile.grid_propagate(False)
            tile.pack_propagate(False)

            thumb_photo = self._make_thumb_photo(layer)
            thumb_lbl = tk.Label(tile, image=thumb_photo,
                                  bg=tile_bg, borderwidth=0)
            thumb_lbl.image = thumb_photo
            thumb_lbl.pack(side="top")
            thumb_lbl.bind("<ButtonPress-1>",
                            lambda e, n=name: self._tile_press(e, n))
            thumb_lbl.bind("<B1-Motion>",
                            lambda e, n=name: self._tile_motion(e, n))
            thumb_lbl.bind("<ButtonRelease-1>",
                            lambda e, n=name: self._tile_release(e, n))
            thumb_lbl.bind("<Button-3>",
                            lambda e, n=name: self._tile_context_menu(e, n))
            tile.bind("<ButtonPress-1>",
                       lambda e, n=name: self._tile_press(e, n))
            tile.bind("<B1-Motion>",
                       lambda e, n=name: self._tile_motion(e, n))
            tile.bind("<ButtonRelease-1>",
                       lambda e, n=name: self._tile_release(e, n))
            tile.bind("<Button-3>",
                       lambda e, n=name: self._tile_context_menu(e, n))

            info = tk.Frame(tile, bg=tile_bg)
            info.pack(side="top", fill="x", pady=(2, 0))

            vis_var = tk.BooleanVar(value=layer.visible)
            cb = tk.Checkbutton(
                info, variable=vis_var,
                bg=tile_bg, activebackground=tile_bg,
                fg=DARK["fg"], selectcolor=DARK["entry_bg"],
                borderwidth=0, highlightthickness=0,
                command=lambda n=name, v=vis_var: self._toggle_visible(n, v),
            )
            cb.pack(side="left")

            swatch = tk.Label(info, text=" ", bg=layer.tint_color,
                              relief="solid", borderwidth=1, width=2)
            swatch.pack(side="left", padx=2)

            short = name if len(name) <= 14 else name[:11] + "…"
            name_btn = tk.Button(
                tile, text=short, anchor="center",
                relief="flat", borderwidth=0, font=("Segoe UI", 8),
                bg=tile_bg,
                fg=(DARK["fg_active"] if name == self.active_name else DARK["fg"]),
                activebackground=DARK["bg_active"],
                activeforeground=DARK["fg_active"],
                command=lambda n=name: self._set_active(n),
            )
            name_btn.pack(side="top", fill="x")
            self._add_tooltip(name_btn, name)

            ctrl = tk.Frame(tile, bg=tile_bg)
            ctrl.pack(side="top", fill="x")
            tk.Button(ctrl, text="◀", width=2, relief="flat", borderwidth=0,
                      bg=tile_bg, fg=DARK["fg"], font=("Segoe UI", 7),
                      activebackground=DARK["bg_active"],
                      activeforeground=DARK["fg_active"],
                      command=lambda n=name: self._move_layer(n, -1)
                      ).pack(side="left")
            tk.Button(ctrl, text="▶", width=2, relief="flat", borderwidth=0,
                      bg=tile_bg, fg=DARK["fg"], font=("Segoe UI", 7),
                      activebackground=DARK["bg_active"],
                      activeforeground=DARK["fg_active"],
                      command=lambda n=name: self._move_layer(n, +1)
                      ).pack(side="left")
            tk.Button(ctrl, text="✕", width=2, relief="flat", borderwidth=0,
                      bg=tile_bg, fg="#ff7676", font=("Segoe UI", 7),
                      activebackground="#5a1a1a", activeforeground="#ffffff",
                      command=lambda n=name: self._remove_layer(n)
                      ).pack(side="right")

            self._file_rows[name] = {
                "tile": tile, "btn": name_btn, "swatch": swatch,
                "vis": vis_var, "thumb": thumb_lbl,
            }

        self._update_counts()
        self._sync_master_checkbox()
        self._relayout_tiles()
        self._sync_scrub_range()

    # ── Drag-and-drop ────────────────────────────────────────────────────────

    def _tile_press(self, event, name: str):
        self._tile_drag = {
            "name": name, "started": False,
            "x0": event.x_root, "y0": event.y_root,
            "highlight": None,
        }

    def _tile_motion(self, event, name: str):
        st = self._tile_drag
        if st["name"] != name:
            return
        if not st["started"]:
            dx = abs(event.x_root - st["x0"])
            dy = abs(event.y_root - st["y0"])
            if dx + dy < self.DRAG_THRESHOLD:
                return
            st["started"] = True
            self._filelist_canvas.config(cursor="hand2")
            if name in self._file_rows:
                self._file_rows[name]["tile"].config(
                    highlightbackground=DARK["accent"],
                    highlightthickness=2,
                )

        target = self._find_tile_under_pointer(event.x_root, event.y_root)
        prev = st["highlight"]
        if prev != target:
            if prev and prev in self._file_rows and prev != name:
                self._file_rows[prev]["tile"].config(highlightthickness=0)
            if target and target != name and target in self._file_rows:
                self._file_rows[target]["tile"].config(
                    highlightbackground="#7faaff",
                    highlightthickness=2,
                )
            st["highlight"] = target

    def _tile_release(self, event, name: str):
        st = self._tile_drag
        self._tile_drag = {
            "name": None, "started": False,
            "x0": 0, "y0": 0, "highlight": None,
        }
        self._filelist_canvas.config(cursor="")
        if st["name"] != name:
            return
        if name in self._file_rows:
            self._file_rows[name]["tile"].config(highlightthickness=0)
        if st["highlight"] and st["highlight"] in self._file_rows \
                and st["highlight"] != name:
            self._file_rows[st["highlight"]]["tile"].config(highlightthickness=0)

        if not st["started"]:
            self._set_active(name)
            return

        target = self._find_tile_under_pointer(event.x_root, event.y_root)
        if not target or target == name:
            return
        self._reorder_layer_to(name, target)

    def _find_tile_under_pointer(self, x_root: int, y_root: int) -> Optional[str]:
        for n, row in self._file_rows.items():
            tile = row["tile"]
            if not tile.winfo_exists():
                continue
            try:
                tx = tile.winfo_rootx()
                ty = tile.winfo_rooty()
                tw = tile.winfo_width()
                th = tile.winfo_height()
            except tk.TclError:
                continue
            if tx <= x_root < tx + tw and ty <= y_root < ty + th:
                return n
        return None

    def _reorder_layer_to(self, src: str, target: str):
        if src not in self.layers or target not in self.layers or src == target:
            return
        self._push_frames_undo("drag-перестановка")
        names = list(self.layers.keys())
        src_idx = names.index(src)
        tgt_idx = names.index(target)
        names.remove(src)
        new_tgt_idx = names.index(target)
        if src_idx < tgt_idx:
            insert_at = new_tgt_idx + 1
        else:
            insert_at = new_tgt_idx
        names.insert(insert_at, src)
        self.layers = {n: self.layers[n] for n in names}

        if self.playback_on:
            self._exit_playback()
        self._rebuild_file_list()
        self._redraw()
        self.status.config(text=f"Переставлен: {src} → позиция {insert_at + 1}")

    def _tile_context_menu(self, event, name: str):
        m = tk.Menu(self.root, tearoff=0,
                    bg=DARK["bg_alt"], fg=DARK["fg"],
                    activebackground=DARK["bg_active"],
                    activeforeground=DARK["fg_active"])
        m.add_command(label="Сделать активным",
                      command=lambda: self._set_active(name))
        m.add_command(label="◀ Подвинуть влево",
                      command=lambda: self._move_layer(name, -1))
        m.add_command(label="▶ Подвинуть вправо",
                      command=lambda: self._move_layer(name, +1))
        m.add_separator()
        m.add_command(label="✕ Убрать из набора",
                      command=lambda: self._remove_layer(name))
        try:
            m.tk_popup(event.x_root, event.y_root)
        finally:
            m.grab_release()

    # ── Master / batch visibility ────────────────────────────────────────────

    def _on_master_toggle(self):
        if self._master_updating:
            return
        value = self.master_visible.get()
        for name in self.layers:
            self._set_visible(name, value, redraw=False)
        self._update_counts()
        self._redraw()

    def _select_all_visible(self):
        for name in self.layers:
            self._set_visible(name, True, redraw=False)
        self._sync_master_checkbox()
        self._update_counts()
        self._redraw()

    def _select_none_visible(self):
        for name in self.layers:
            self._set_visible(name, False, redraw=False)
        self._sync_master_checkbox()
        self._update_counts()
        self._redraw()

    def _invert_visible(self):
        for name, layer in self.layers.items():
            self._set_visible(name, not layer.visible, redraw=False)
        self._sync_master_checkbox()
        self._update_counts()
        self._redraw()

    def _set_visible(self, name: str, value: bool, redraw: bool = True):
        layer = self.layers[name]
        if layer.visible == value:
            return
        layer.visible = value
        if not value:
            layer._tinted_cache = None
            layer._tint_key = None
            layer.invalidate_cache()
        if name in self._file_rows:
            self._file_rows[name]["vis"].set(value)
        if redraw:
            self._redraw()

    def _sync_master_checkbox(self):
        if not self.layers:
            self._master_updating = True
            self.master_visible.set(False)
            self._master_updating = False
            return
        all_on = all(l.visible for l in self.layers.values())
        self._master_updating = True
        self.master_visible.set(all_on)
        self._master_updating = False

    def _update_counts(self):
        if not hasattr(self, "count_label"):
            return
        total = len(self.layers)
        vis = sum(1 for l in self.layers.values() if l.visible)
        self.count_label.config(text=f"{vis} / {total}")

    def _close_all_layers(self):
        if not self.layers:
            return
        if not messagebox.askyesno(
            "Закрыть все",
            f"Убрать все {len(self.layers)} слоёв из редактора?"
        ):
            return
        self._push_frames_undo("закрыть все слои")
        if self.playback_on:
            self._exit_playback()
        self.layers.clear()
        self.active_name = None
        self._rebuild_file_list()
        self._update_active_panel()
        self._update_frame_indicator()
        self._redraw()
        self.status.config(text="Все слои закрыты")

    def _move_layer(self, name: str, delta: int):
        names = list(self.layers.keys())
        if name not in names:
            return
        idx = names.index(name)
        new_idx = idx + delta
        if new_idx < 0 or new_idx >= len(names):
            return
        self._push_frames_undo("перестановка кадра")
        names[idx], names[new_idx] = names[new_idx], names[idx]
        self.layers = {n: self.layers[n] for n in names}
        if self.playback_on:
            self._exit_playback()
        self._rebuild_file_list()
        self._redraw()

    def _remove_layer(self, name: str):
        if name not in self.layers:
            return
        self._push_frames_undo("удаление кадра")
        if self.playback_on:
            self._exit_playback()
        del self.layers[name]
        if self.active_name == name:
            self.active_name = next(iter(self.layers), None)
        self._rebuild_file_list()
        self._update_active_panel()
        self._update_frame_indicator()
        self._redraw()

    def _update_file_list_active(self, prev_name: Optional[str]):
        if not hasattr(self, "_file_rows"):
            return
        for n in (prev_name, self.active_name):
            if n and n in self._file_rows:
                is_active = (n == self.active_name)
                row = self._file_rows[n]
                bg = DARK["list_active"] if is_active else DARK["list_inactive"]
                row["tile"].config(bg=bg)
                for child in row["tile"].winfo_children():
                    try:
                        child.config(bg=bg)
                        for sub in child.winfo_children():
                            try:
                                if sub is not row["swatch"]:
                                    sub.config(bg=bg)
                            except tk.TclError:
                                pass
                    except tk.TclError:
                        pass
                row["btn"].config(
                    fg=(DARK["fg_active"] if is_active else DARK["fg"]),
                )

    def _update_file_list_swatch(self, name: str):
        if hasattr(self, "_file_rows") and name in self._file_rows:
            self._file_rows[name]["swatch"].config(
                bg=self.layers[name].tint_color
            )

    def _refresh_layer_thumb(self, name: str):
        if not hasattr(self, "_file_rows") or name not in self._file_rows:
            return
        layer = self.layers[name]
        layer._thumb_key = None
        layer._thumb_photo = None
        photo = self._make_thumb_photo(layer)
        lbl = self._file_rows[name]["thumb"]
        lbl.config(image=photo)
        lbl.image = photo

    def _toggle_visible(self, name: str, var: tk.BooleanVar):
        layer = self.layers[name]
        layer.visible = var.get()
        if not layer.visible:
            layer._tinted_cache = None
            layer._tint_key = None
            layer.invalidate_cache()
        if self.playback_on:
            visible = self._visible_layers_ordered()
            if not visible:
                self._exit_playback()
                return
            self.playback_idx %= len(visible)
        self._sync_master_checkbox()
        self._update_counts()
        self._update_frame_indicator()
        self._redraw()

    def _set_active(self, name: str):
        if self.playback_on:
            self._exit_playback()
        prev = self.active_name
        self.active_name = name
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
