"""
Конфиг и общие константы для sprite editor.
"""

# Холст
CANVAS_W = 800
CANVAS_H = 800
DEFAULT_VIEW_SCALE = 0.5          # 50% — стартовый zoom
DEFAULT_CELL_SIZE = 10
CHROMA_TOLERANCE = 50

# Сохранение
OUTPUT_SUBFOLDER = "_processed"
STATE_FILE = "_editor_state.json"

# Уровни зума в процентах (% от оригинала)
ZOOM_LEVELS = [
    0.10, 0.15, 0.20, 0.25, 0.33, 0.40, 0.50, 0.67, 0.80,
    1.00,
    1.25, 1.50, 2.00, 2.50, 3.00, 4.00, 6.00, 8.00,
    10.0, 12.0, 16.0, 20.0, 24.0, 32.0,
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
