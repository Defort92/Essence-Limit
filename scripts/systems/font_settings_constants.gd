## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name FontSettingsConstants
extends RefCounted

const SETTINGS_PATH := "user://settings.cfg"

const THEME_PATH := "res://assets/themes/essence_theme.tres"

## Доступные шрифты (пиксельные, с поддержкой кириллицы). Порядок — от самого читаемого
## к самому декоративному. "name" — подпись в настройках, "path" — путь к .ttf.
const FONTS: Array[Dictionary] = [
	{"name": "DotGothic16", "path": "res://assets/fonts/DotGothic16-Regular.ttf"},
	{"name": "Pixelify Sans", "path": "res://assets/fonts/PixelifySans-VariableFont.ttf"},
	{"name": "Handjet", "path": "res://assets/fonts/Handjet-VariableFont.ttf"},
	{"name": "Tiny5", "path": "res://assets/fonts/Tiny5-Regular.ttf"},
	{"name": "Pixeloid Sans", "path": "res://assets/fonts/PixeloidSans-Regular.ttf"},
	{"name": "Pixel UniCode", "path": "res://assets/fonts/PixelUniCode-Regular.ttf"},
	{"name": "Neue Pixel Sans", "path": "res://assets/fonts/NeuePixelSans-Regular.ttf"},
	{"name": "Basis33", "path": "res://assets/fonts/Basis33-Regular.ttf"},
	{"name": "Retron 2000", "path": "res://assets/fonts/Retron2000-Regular.ttf"},
	{"name": "Home Video", "path": "res://assets/fonts/HomeVideo-Regular.ttf"},
	{"name": "Instructions", "path": "res://assets/fonts/Instructions-Regular.ttf"},
	{"name": "712 Serif", "path": "res://assets/fonts/712Serif-Regular.ttf"},
	{"name": "BlockKie", "path": "res://assets/fonts/BlockKie-Regular.ttf"},
	{"name": "Progress Pixel", "path": "res://assets/fonts/ProgressPixel-Regular.ttf"},
	{"name": "Rubik Pixels", "path": "res://assets/fonts/RubikPixels-Regular.ttf"},
]

## Куда применяется шрифт основного текста: тип в теме -> межбуквенный интервал (spacing_glyph).
## Пустой ключ "" — это default_font темы (обычные Label, кнопки меню и т.п.).
const BODY_ROLES: Dictionary = {
	"": 0,
	"Button": 1,
	"HeaderLabel": 2,
	"LineEdit": 1,
	"MutedLabel": 0,
}

## Индекс шрифта заголовков по умолчанию (DotGothic16 — читаемый).
const DEFAULT_TITLE := 0

## Индекс шрифта основного текста по умолчанию (DotGothic16 — читаемый).
const DEFAULT_BODY := 0
