## Строка списка «текст + кнопки действий» для панелей (лут, лавка, экран персонажа).
## Создаётся из кода:
##   UIListRow.create("Меч x1", [{"text": "Взять", "callback": func(): ...}])
## Стили кнопок общие на всю игру и строятся один раз. make_button используется и
## отдельно — например, для вкладок участников отряда на экране персонажа.
extends HBoxContainer
class_name UIListRow

const TEXT_COLOR := Color(0.78, 0.71, 0.6, 1)
const TEXT_HOVER_COLOR := Color(0.95, 0.83, 0.45, 1)

static var _style_normal: StyleBoxFlat = null
static var _style_hover: StyleBoxFlat = null

## Собирает строку: растягивающийся текст слева, кнопки действий справа.
## [param actions] — массив словарей { "text": String, "callback": Callable }.
static func create(label_text: String, actions: Array = []) -> UIListRow:
	var row := UIListRow.new()
	row.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", TEXT_COLOR)
	row.add_child(label)

	for action: Dictionary in actions:
		row.add_child(make_button(action.text, action.callback))
	return row

## Кнопка в общем стиле строк списка. [param highlighted] — постоянно «горящий» фон
## (например, активная вкладка участника отряда).
static func make_button(text_value: String, callback: Callable, highlighted: bool = false) -> Button:
	_ensure_styles()
	var button := Button.new()
	button.text = text_value
	button.add_theme_stylebox_override("normal", _style_hover if highlighted else _style_normal)
	button.add_theme_stylebox_override("hover", _style_hover)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_HOVER_COLOR)
	button.pressed.connect(callback)
	return button

static func _ensure_styles() -> void:
	if _style_normal != null:
		return
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.039, 0.031, 0.035, 0.85)
	_style_normal.border_width_left = 1
	_style_normal.border_width_top = 1
	_style_normal.border_width_right = 1
	_style_normal.border_width_bottom = 1
	_style_normal.border_color = Color(0.471, 0.376, 0.212, 0.4)
	_style_normal.content_margin_left = 12
	_style_normal.content_margin_top = 4
	_style_normal.content_margin_right = 12
	_style_normal.content_margin_bottom = 4

	_style_hover = _style_normal.duplicate() as StyleBoxFlat
	_style_hover.bg_color = Color(0.588, 0.275, 0.141, 0.2)
	_style_hover.border_color = Color(0.55, 0.44, 0.25, 0.55)
