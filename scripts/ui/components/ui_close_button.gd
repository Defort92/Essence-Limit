## Кнопка-крестик закрытия экрана. Общий компонент интерфейса: прикрепляется к узлу
## Button в любой сцене (существующие connection'ы pressed сохраняются) или создаётся
## из кода: UICloseButton.new(). Вид задаёт сама — в сцене текст/размер не прописывать.
##
## Если задано close_action, тултип показывает актуальную горячую клавишу закрытия
## («Закрыть (F)») и обновляется при переназначении клавиш в настройках.
extends Button
class_name UICloseButton

## Input-действие, закрывающее этот экран (для тултипа). Пусто — тултип просто «Закрыть».
@export var close_action: String = ""

func _ready() -> void:
	text = "✕"
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(36, 36)
	add_theme_font_size_override("font_size", 20)
	add_theme_color_override("font_color", Color(0.757, 0.675, 0.525))
	add_theme_color_override("font_hover_color", Color(0.95, 0.83, 0.45))
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	InputSettings.bindings_changed.connect(_update_tooltip)
	_update_tooltip()

func _update_tooltip() -> void:
	if close_action.is_empty():
		tooltip_text = "Закрыть"
	else:
		tooltip_text = "Закрыть (%s)" % InputSettings.action_key_label(close_action)
