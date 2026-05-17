"""
SpriteLayer — состояние одного загруженного спрайта.
"""

from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image

from config import DEFAULT_CELL_SIZE


@dataclass
class SpriteLayer:
    path: Path
    original: Image.Image                # исходник, не трогаем
    current: Image.Image                 # после snap / chroma и т.д.
    offset_x: int = 0
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
