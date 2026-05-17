"""
PaintMixin — инструменты рисования: кисть, ластик, метла, пипетка,
сохранённая палитра. Также ЛКМ-диспатч на канвасе по выбранному инструменту.
"""

import tkinter as tk
from tkinter import colorchooser, messagebox
from typing import Optional

import numpy as np
from PIL import Image, ImageTk


class PaintMixin:
    # ── Палитра ──────────────────────────────────────────────────────────────

    def _rebuild_palette(self):
        for w in self.palette_frame.winfo_children():
            w.destroy()
        for color in self.saved_colors:
            sw = tk.Label(
                self.palette_frame, text=" ", bg=color,
                relief="solid", borderwidth=1, width=2, height=1,
            )
            sw.pack(side="left", padx=1)
            sw.bind("<Button-1>",
                    lambda e, c=color: self._select_palette_color(c))
            sw.bind("<Button-3>",
                    lambda e, c=color: self._remove_palette_color(c))
            self._add_tooltip(sw, f"{color}  (ПКМ — удалить из палитры)")

    def _select_palette_color(self, color: str):
        self.paint_color = color
        self.color_preview.config(bg=color)
        if self.tool_mode not in ("brush",):
            self.tool_var.set("brush")
            self._on_tool_changed("brush")

    def _remove_palette_color(self, color: str):
        if color in self.saved_colors:
            self.saved_colors.remove(color)
            self._rebuild_palette()

    def _save_current_color(self):
        c = self.paint_color
        if c not in self.saved_colors:
            self.saved_colors.append(c)
            self._rebuild_palette()

    def _pick_paint_color(self):
        col = colorchooser.askcolor(color=self.paint_color, title="Цвет кисти")
        if col and col[1]:
            self.paint_color = col[1]
            self.color_preview.config(bg=self.paint_color)

    def _on_tool_changed(self, value: str):
        self.tool_mode = value
        cursors = {
            "pan":        "fleur",
            "brush":      "pencil",
            "eraser":     "dotbox",
            "broom":      "cross",
            "eyedropper": "target",
        }
        self.canvas.config(cursor=cursors.get(value, "arrow"))
        self.status.config(text=f"Инструмент: {value}")

    # ── Tool dispatch (ЛКМ на canvas) ────────────────────────────────────────

    def _canvas_to_image_px(self, event):
        """screen → image-pixel в активном слое. Возвращает (px, py, layer) или None."""
        layer = self._active() if hasattr(self, "_active") else None
        if layer is None:
            return None
        cx = self.canvas.canvasx(event.x)
        cy = self.canvas.canvasy(event.y)
        scale = self.view_scale
        ix = int(cx / scale) - layer.offset_x
        iy = int(cy / scale) - layer.offset_y
        w, h = layer.current.size
        if ix < 0 or iy < 0 or ix >= w or iy >= h:
            return None
        return ix, iy, layer

    def _on_lmb_down(self, event):
        tool = self.tool_mode
        if tool == "pan":
            return self._on_pan_start(event)
        if tool == "eyedropper":
            self._do_eyedropper(event)
            return
        if tool == "broom":
            self._broom_begin(event)
            return
        if tool in ("brush", "eraser"):
            layer = self._active()
            if layer is None:
                return
            self._push_image_undo(layer)
            self._paint_stroke_active = True
            self._paint_last_px = None
            self._apply_paint(event)

    def _on_lmb_drag(self, event):
        tool = self.tool_mode
        if tool == "pan":
            return self._on_pan_drag(event)
        if tool == "broom":
            self._broom_update(event)
            return
        if tool in ("brush", "eraser") and self._paint_stroke_active:
            self._apply_paint(event)

    def _on_lmb_up(self, event):
        if self.tool_mode == "broom":
            self._broom_finish(event)
            return
        if self._paint_stroke_active:
            self._paint_stroke_active = False
            self._paint_last_px = None
            self._redraw()

    # ── Eyedropper ───────────────────────────────────────────────────────────

    def _do_eyedropper(self, event):
        cx = self.canvas.canvasx(event.x)
        cy = self.canvas.canvasy(event.y)
        scale = self.view_scale
        ordered = []
        if self.active_name and self.layers[self.active_name].visible:
            ordered.append(self.layers[self.active_name])
        for n, l in self.layers.items():
            if l.visible and n != self.active_name:
                ordered.insert(0, l)
        for layer in ordered[::-1]:
            ix = int(cx / scale) - layer.offset_x
            iy = int(cy / scale) - layer.offset_y
            w, h = layer.current.size
            if 0 <= ix < w and 0 <= iy < h:
                r, g, b, a = layer.current.getpixel((ix, iy))
                if a > 0:
                    hex_col = f"#{r:02X}{g:02X}{b:02X}"
                    self.paint_color = hex_col
                    self.color_preview.config(bg=hex_col)
                    self.status.config(text=f"Цвет: {hex_col}  (α={a})")
                    self.tool_var.set("brush")
                    self._on_tool_changed("brush")
                    return
        self.status.config(text="Пипетка: под курсором прозрачно / нет слоя")

    # ── Brush / Eraser ───────────────────────────────────────────────────────

    @staticmethod
    def _hex_to_rgb(hex_str: str):
        s = hex_str.lstrip("#")
        return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)

    def _apply_paint(self, event):
        target = self._canvas_to_image_px(event)
        if target is None:
            self._paint_last_px = None
            return
        ix, iy, layer = target

        radius = max(1, int(self.brush_size.get()))
        if self.tool_mode == "brush":
            r, g, b = self._hex_to_rgb(self.paint_color)
            fill = (r, g, b, 255)
        else:
            fill = (0, 0, 0, 0)

        arr = np.array(layer.current, dtype=np.uint8)
        H, W = arr.shape[:2]

        points = []
        if self._paint_last_px is None:
            points.append((ix, iy))
        else:
            lx, ly = self._paint_last_px
            steps = max(abs(ix - lx), abs(iy - ly))
            if steps == 0:
                points.append((ix, iy))
            else:
                for s in range(steps + 1):
                    t = s / steps
                    points.append((round(lx + (ix - lx) * t),
                                   round(ly + (iy - ly) * t)))

        for cx, cy in points:
            x0 = max(0, cx - radius + 1)
            x1 = min(W, cx + radius)
            y0 = max(0, cy - radius + 1)
            y1 = min(H, cy + radius)
            if x1 <= x0 or y1 <= y0:
                continue
            if radius == 1:
                arr[y0:y1, x0:x1] = fill
            else:
                yy, xx = np.ogrid[y0:y1, x0:x1]
                mask = (xx - cx) ** 2 + (yy - cy) ** 2 < radius * radius
                arr[y0:y1, x0:x1][mask] = fill

        layer.current = Image.fromarray(arr, "RGBA")
        layer.invalidate_cache()
        self._paint_last_px = (ix, iy)
        self._refresh_layer_only(layer)

    def _refresh_layer_only(self, layer):
        scale = self.view_scale
        is_active_layer = (
            self.active_name and self.layers.get(self.active_name) is layer
        )
        if is_active_layer:
            tinted = layer.current.convert("RGBA")
            layer._tint_key = ("real", id(layer.current))
        else:
            tinted = self._apply_silhouette(
                layer.current, layer.tint_color, alpha=120
            )
            layer._tint_key = ("sil", layer.tint_color, 120, id(layer.current))
        layer._tinted_cache = tinted
        tw = max(1, int(tinted.size[0] * scale))
        th = max(1, int(tinted.size[1] * scale))
        scaled = tinted.resize((tw, th), Image.NEAREST)
        photo = ImageTk.PhotoImage(scaled)
        layer._cached_photo = photo
        layer._cache_key = (scale, layer._tint_key[0], id(layer.current))
        if layer._canvas_item is not None:
            self.canvas.itemconfigure(layer._canvas_item, image=photo)
        else:
            layer._canvas_item = self.canvas.create_image(
                int(layer.offset_x * scale),
                int(layer.offset_y * scale),
                anchor="nw", image=photo,
            )

    # ── Broom (rect-erase) ───────────────────────────────────────────────────

    def _broom_begin(self, event):
        layer = self._active()
        if layer is None:
            return
        self._broom_start = (self.canvas.canvasx(event.x),
                             self.canvas.canvasy(event.y))
        if self._broom_rect_id is not None:
            self.canvas.delete(self._broom_rect_id)
        self._broom_rect_id = self.canvas.create_rectangle(
            self._broom_start[0], self._broom_start[1],
            self._broom_start[0], self._broom_start[1],
            outline="#ff5555", dash=(3, 3), width=1,
        )

    def _broom_update(self, event):
        if self._broom_start is None or self._broom_rect_id is None:
            return
        cx = self.canvas.canvasx(event.x)
        cy = self.canvas.canvasy(event.y)
        self.canvas.coords(self._broom_rect_id,
                           self._broom_start[0], self._broom_start[1], cx, cy)

    def _broom_finish(self, event):
        if self._broom_start is None:
            return
        layer = self._active()
        if layer is None:
            self._broom_cleanup()
            return
        cx = self.canvas.canvasx(event.x)
        cy = self.canvas.canvasy(event.y)
        scale = self.view_scale
        x0c, y0c = self._broom_start
        x_lo, x_hi = sorted([x0c, cx])
        y_lo, y_hi = sorted([y0c, cy])
        ix0 = int(x_lo / scale) - layer.offset_x
        iy0 = int(y_lo / scale) - layer.offset_y
        ix1 = int(x_hi / scale) - layer.offset_x
        iy1 = int(y_hi / scale) - layer.offset_y
        w, h = layer.current.size
        ix0 = max(0, min(w, ix0)); ix1 = max(0, min(w, ix1))
        iy0 = max(0, min(h, iy0)); iy1 = max(0, min(h, iy1))
        self._broom_cleanup()
        if ix1 - ix0 < 1 or iy1 - iy0 < 1:
            self.status.config(text="Метла: пустое выделение")
            return
        self._push_image_undo(layer)
        arr = np.array(layer.current, dtype=np.uint8)
        arr[iy0:iy1, ix0:ix1] = (0, 0, 0, 0)
        layer.current = Image.fromarray(arr, "RGBA")
        layer.invalidate_cache()
        self._redraw()
        self.status.config(
            text=f"Метла: стёрто {ix1 - ix0}×{iy1 - iy0} px"
        )

    def _broom_cleanup(self):
        if self._broom_rect_id is not None:
            self.canvas.delete(self._broom_rect_id)
            self._broom_rect_id = None
        self._broom_start = None

    def _clear_active_layer(self):
        layer = self._active()
        if layer is None:
            return
        if not messagebox.askyesno(
            "Очистить слой?",
            f"Стереть все пиксели слоя '{self.active_name}'?\n"
            "(можно отменить через Ctrl+Z)",
        ):
            return
        self._push_image_undo(layer)
        w, h = layer.current.size
        layer.current = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        layer.invalidate_cache()
        self._redraw()
        self.status.config(text="Активный слой очищен")
