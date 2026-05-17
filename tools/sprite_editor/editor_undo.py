"""
UndoMixin — общий undo-stack для image-правок и frame-операций,
плюс clipboard (копировать / вырезать / вставить кадр).
"""

from pathlib import Path
from tkinter import messagebox

from sprite_layer import SpriteLayer


class UndoMixin:
    MAX_UNDO = 50

    # ── Undo (общая история) ────────────────────────────────────────────────

    def _push_image_undo(self, layer):
        layer.push_history()
        self._global_undo.append(("image", layer))
        if len(self._global_undo) > self.MAX_UNDO:
            self._global_undo.pop(0)

    def _push_frames_undo(self, op_name: str = ""):
        snap = list(self.layers.items())
        self._global_undo.append(("frames", snap, self.active_name, op_name))
        if len(self._global_undo) > self.MAX_UNDO:
            self._global_undo.pop(0)

    def _undo(self):
        if not self._global_undo:
            self.status.config(text="Нечего отменять")
            return
        entry = self._global_undo.pop()
        kind = entry[0]
        if kind == "image":
            layer = entry[1]
            if layer.undo():
                layer.invalidate_cache()
                self._update_active_panel()
                self._redraw()
                self.status.config(text="Отменено: правка изображения")
            else:
                self._undo()
        elif kind == "frames":
            _, snap, active, op_name = entry
            self.layers = dict(snap)
            if self.playback_on:
                self._exit_playback()
            if active and active in self.layers:
                self.active_name = active
            else:
                self.active_name = next(iter(self.layers), None)
            self._rebuild_file_list()
            self._update_active_panel()
            self._redraw()
            label = op_name or "операция со слоями"
            self.status.config(text=f"Отменено: {label}")

    # ── Clipboard ───────────────────────────────────────────────────────────

    def _clone_layer(self, src) -> SpriteLayer:
        return SpriteLayer(
            path=src.path,
            original=src.original.copy(),
            current=src.current.copy(),
            offset_x=src.offset_x,
            offset_y=src.offset_y,
            visible=src.visible,
            tint_color=src.tint_color,
            snap_cell=src.snap_cell,
            chroma_removed=src.chroma_removed,
        )

    def _copy_active(self):
        if not self.active_name:
            self.status.config(text="Нет активного кадра для копирования")
            return
        layer = self.layers[self.active_name]
        self._clipboard_layer = self._clone_layer(layer)
        self._clipboard_name = self.active_name
        self.status.config(text=f"Скопировано: {self.active_name}")

    def _cut_active(self):
        if not self.active_name:
            self.status.config(text="Нет активного кадра для вырезания")
            return
        name = self.active_name
        layer = self.layers[name]
        self._clipboard_layer = self._clone_layer(layer)
        self._clipboard_name = name
        self._push_frames_undo("вырезать кадр")
        if self.playback_on:
            self._exit_playback()
        names = list(self.layers.keys())
        idx = names.index(name)
        del self.layers[name]
        new_names = list(self.layers.keys())
        if new_names:
            self.active_name = new_names[min(idx, len(new_names) - 1)]
        else:
            self.active_name = None
        self._rebuild_file_list()
        self._update_active_panel()
        self._update_frame_indicator()
        self._redraw()
        self.status.config(text=f"Вырезано: {name}")

    def _paste_clipboard(self):
        if self._clipboard_layer is None:
            self.status.config(text="Буфер пуст")
            return
        self._push_frames_undo("вставить кадр")
        base = self._clipboard_name or "pasted.png"
        if base in self.layers:
            stem = Path(base).stem
            ext = Path(base).suffix or ".png"
            i = 1
            cand = f"{stem}_copy{i}{ext}"
            while cand in self.layers:
                i += 1
                cand = f"{stem}_copy{i}{ext}"
            new_name = cand
        else:
            new_name = base

        new_layer = self._clone_layer(self._clipboard_layer)
        if self.folder:
            new_layer.path = self.folder / new_name
        else:
            new_layer.path = Path(new_name)

        names = list(self.layers.keys())
        if self.active_name and self.active_name in names:
            insert_at = names.index(self.active_name) + 1
        else:
            insert_at = len(names)
        names.insert(insert_at, new_name)

        new_layers: dict = {}
        for n in names:
            new_layers[n] = new_layer if n == new_name else self.layers[n]
        self.layers = new_layers
        self.active_name = new_name

        self._rebuild_file_list()
        self._update_active_panel()
        self._update_frame_indicator()
        self._redraw()
        self.status.config(text=f"Вставлено: {new_name}")

    # ── Reset ───────────────────────────────────────────────────────────────

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
        if not messagebox.askyesno(
            "Подтверждение", "Сбросить ВСЕ слои к оригиналу?"
        ):
            return
        for layer in self.layers.values():
            layer.current = layer.original.copy()
            layer.offset_x = 0
            layer.offset_y = 0
            layer.chroma_removed = False
            layer.history.clear()
        self._update_active_panel()
        self._redraw()
