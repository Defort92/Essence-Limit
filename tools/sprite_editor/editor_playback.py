"""
PlaybackMixin — режим проигрывания анимации, scrubber-ползунок,
синхронизация активного кадра при паузе.

Зависит от методов, предоставляемых другими миксинами / основным классом:
  self.layers, self.active_name, self.canvas, self.status, self.root
  self.view_scale, self.playback_idx, self.playback_on, self.playback_after_id
  self._playback_item, self.play_btn, self.play_fps,
  self.scrub_scale, self.scrub_var, self._scrub_programmatic, self._scrub_user_dragging
  self.frame_indicator
  self._redraw(), self._update_active_panel(), self._update_file_list_active(prev)
"""

from PIL import Image, ImageTk


class PlaybackMixin:
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
            # На паузу → активным становится текущий кадр плеера
            self._stop_timer()
            self._adopt_playback_frame_as_active()
            self.status.config(
                text=f"Пауза на кадре {self.playback_idx + 1}/{len(visible)}"
            )
        else:
            first_entry = not self.playback_on
            self.playback_on = True
            self.play_btn.config(text="⏸ Pause")
            self._update_frame_indicator()
            if first_entry:
                self._redraw()
            self._schedule_next_tick()
            self.status.config(text="▶ Воспроизведение")

    def _schedule_next_tick(self):
        fps = max(1, int(self.play_fps.get()))
        delay_ms = max(16, int(1000 / fps))
        self.playback_after_id = self.root.after(delay_ms, self._play_tick)

    def _play_tick(self):
        visible = self._visible_layers_ordered()
        if not visible:
            self._stop_timer()
            self.playback_on = False
            return
        self.playback_idx = (self.playback_idx + 1) % len(visible)
        self._update_frame_indicator()
        self._sync_scrub_position()
        self._fast_playback_redraw()
        self._schedule_next_tick()

    def _fast_playback_redraw(self):
        """Hot path: подменяет image у одного canvas item."""
        visible = self._visible_layers_ordered()
        if not visible:
            return
        layer = visible[self.playback_idx % len(visible)]

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
        visible = self._visible_layers_ordered()
        if not visible:
            return
        self._stop_timer()
        self.play_btn.config(text="▶ Play")
        first_entry = not self.playback_on
        self.playback_on = True
        self.playback_idx = target_idx % len(visible)
        self._update_frame_indicator()
        self._sync_scrub_position()
        if first_entry:
            self._redraw()
        else:
            self._fast_playback_redraw()
        self.status.config(text=f"Кадр {self.playback_idx + 1}/{len(visible)}")

    def _on_scrub_change(self, value):
        if self._scrub_programmatic:
            return
        try:
            idx = int(round(float(value)))
        except (TypeError, ValueError):
            return
        visible = self._visible_layers_ordered()
        if not visible:
            return
        idx = max(0, min(len(visible) - 1, idx))
        if idx == self.playback_idx and self.playback_on:
            return
        was_playing = self.playback_after_id is not None
        if was_playing:
            self._stop_timer()
            self.play_btn.config(text="▶ Play")
        first_entry = not self.playback_on
        self.playback_on = True
        self.playback_idx = idx
        self._update_frame_indicator()
        if first_entry:
            self._redraw()
        else:
            self._fast_playback_redraw()
        if not self._scrub_user_dragging:
            self.status.config(text=f"Кадр {idx + 1}/{len(visible)}")

    def _sync_scrub_position(self):
        if not hasattr(self, "scrub_scale"):
            return
        self._scrub_programmatic = True
        try:
            self.scrub_var.set(float(self.playback_idx))
        finally:
            self._scrub_programmatic = False

    def _sync_scrub_range(self):
        if not hasattr(self, "scrub_scale"):
            return
        visible = self._visible_layers_ordered()
        upper = max(0, len(visible) - 1)
        self.scrub_scale.config(to=upper)
        if self.playback_idx > upper:
            self.playback_idx = upper
        self._sync_scrub_position()

    def _adopt_playback_frame_as_active(self):
        """После паузы — кадр плеера становится активным слоем."""
        visible = self._visible_layers_ordered()
        if visible:
            idx = self.playback_idx % len(visible)
            cur_layer = visible[idx]
            for n, l in self.layers.items():
                if l is cur_layer:
                    prev = self.active_name
                    self.active_name = n
                    self._update_file_list_active(prev)
                    break
        self.playback_on = False
        self.play_btn.config(text="▶ Play")
        self._update_active_panel()
        self._update_frame_indicator()
        self._redraw()

    def _exit_playback(self):
        """Esc или другое прерывание — активный = текущий кадр плеера."""
        if not self.playback_on:
            return
        self._stop_timer()
        self._adopt_playback_frame_as_active()

    def _update_frame_indicator(self):
        total = len(self._visible_layers_ordered())
        if self.playback_on and total > 0:
            self.frame_indicator.config(
                text=f"{self.playback_idx + 1} / {total}"
            )
        else:
            self.frame_indicator.config(text=f"– / {total}")
        self._sync_scrub_range()
