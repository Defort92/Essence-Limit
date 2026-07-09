## Баннер текущего места по центру верха экрана: в подземелье — «ЭТАЖ N» и название
## этажа; в мире — название локации (задаётся сценой через set_world_location).
## Источник этажа — DungeonPortal; название мира приходит из HUD (свой у каждой сцены).
extends Control

const TITLE_COLOR: Color = Color(0.839, 0.698, 0.353)
const SUBTITLE_COLOR: Color = Color(0.663, 0.588, 0.541)

## Названия этажей подземелья (1–15). Индекс 0 не используется.
const FLOOR_NAMES: Array[String] = [
	"",
	"Преддверие Праха",
	"Соляные Катакомбы",
	"Галереи Стылой Крови",
	"Костяной Предел",
	"Залы Разбитых Зеркал",
	"Чертоги Тлеющего Пепла",
	"Провалы Немого Хора",
	"Топи Забытых Имён",
	"Обсидиановый Ярус",
	"Сады Висельного Тёрна",
	"Кузни Угасшего Света",
	"Лестница Тысячи Плачей",
	"Престол Смердящей Тьмы",
	"Разлом Изнанки",
	"Сердце Предела",
]

const ROMAN: Array[String] = [
	"", "I", "II", "III", "IV", "V", "VI", "VII", "VIII",
	"IX", "X", "XI", "XII", "XIII", "XIV", "XV",
]

@onready var _title: Label = $Box/Title
@onready var _subtitle: Label = $Box/Subtitle

## Название текущей локации мира (не подземелья). Задаётся сценой через set_world_location().
var _world_location: String = ""

func _ready() -> void:
	DungeonPortal.floor_changed.connect(_on_floor_changed)
	DungeonPortal.portal_closed.connect(_refresh)
	_refresh()

## Устанавливает название локации мира (вызывается HUD при входе в сцену). В подземелье
## отображение перекрывается названием этажа, поэтому обновляем баннер после установки.
func set_world_location(location_name: String) -> void:
	_world_location = location_name
	_refresh()

func _on_floor_changed(_floor: int) -> void:
	_refresh()

func _refresh() -> void:
	if DungeonPortal.is_inside():
		var floor_num: int = DungeonPortal.current_floor
		_title.text = "ЭТАЖ %s" % _roman(floor_num)
		_subtitle.text = FLOOR_NAMES[floor_num] if floor_num < FLOOR_NAMES.size() else ""
		_subtitle.visible = not _subtitle.text.is_empty()
	else:
		_title.text = _world_location.to_upper()
		_subtitle.visible = false
	visible = not _title.text.is_empty()

func _roman(value: int) -> String:
	return ROMAN[value] if value >= 0 and value < ROMAN.size() else str(value)
