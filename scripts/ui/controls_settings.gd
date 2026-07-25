## Раздел настроек «Управление»: переключатель режима бега (клавиатура/мышь) и привязка
## клавиш к действиям. Правки живут в черновике и НЕ влияют на игру, пока не нажата
## «Сохранить». При сохранении с дублирующимися клавишами показывается предупреждение с
## возможностью всё равно сохранить. «Назад» отменяет несохранённые изменения.
##
## Панель самодостаточна: инстанцируется из меню (главное меню / пауза), открывается open()
## и прячется сама, испуская сигнал closed. process_mode = ALWAYS, чтобы работать и на
## паузе (меню паузы), и без неё (главное меню).
extends Control
class_name ControlsSettings

signal closed

## Действия передвижения — рабочие только в режиме клавиатуры (в режиме мыши бег по ПКМ).
const MOVEMENT_ACTIONS: Array = ["move_up", "move_down", "move_left", "move_right"]
## Прочие привязываемые действия — общие для обоих режимов бега.
const COMMON_ACTIONS: Array = [
	"dodge", "interact",
	"ability_1", "ability_2", "ability_3", "ability_4",
	"consumable_1", "consumable_2", "consumable_3", "consumable_4",
	"inventory", "states", "party_command",
]

const ACTION_LABELS := {
	"move_up": "Движение вверх",
	"move_down": "Движение вниз",
	"move_left": "Движение влево",
	"move_right": "Движение вправо",
	"dodge": "Уклонение",
	"interact": "Взаимодействие",
	"ability_1": "Способность 1",
	"ability_2": "Способность 2",
	"ability_3": "Способность 3",
	"ability_4": "Способность 4",
	"consumable_1": "Расходник 1",
	"consumable_2": "Расходник 2",
	"consumable_3": "Расходник 3",
	"consumable_4": "Расходник 4",
	"inventory": "Инвентарь",
	"states": "Состояния",
	"party_command": "Команда отряду (формация)",
}

## Действия, сознательно НЕ показываемые здесь — привязаны к мыши (attack/block) или это
## служебный "pause" (Esc), который не переназначается. Любое другое действие из InputMap,
## которого нет ни здесь, ни в MOVEMENT_ACTIONS/COMMON_ACTIONS, считается забытым — см.
## _warn_about_unlisted_actions().
const EXCLUDED_ACTIONS: Array = ["attack", "block", "pause"]

@onready var _mode_switch: CheckButton = $Panel/Margin/VBoxContainer/ModeRow/ModeSwitch
@onready var _mode_value: Label = $Panel/Margin/VBoxContainer/ModeRow/ModeValueLabel
@onready var _mode_hint: Label = $Panel/Margin/VBoxContainer/ModeHint
@onready var _rows_container: VBoxContainer = $Panel/Margin/VBoxContainer/Scroll/RowsContainer
@onready var _capture_hint: Label = $Panel/Margin/VBoxContainer/CaptureHint
@onready var _save_button: Button = $Panel/Margin/VBoxContainer/ButtonsRow/SaveButton
@onready var _back_button: Button = $Panel/Margin/VBoxContainer/ButtonsRow/BackButton
@onready var _confirm_popup: Control = $ConfirmPopup
@onready var _confirm_message: Label = $ConfirmPopup/PopupPanel/Margin/VBoxContainer/MessageLabel
@onready var _confirm_save: Button = $ConfirmPopup/PopupPanel/Margin/VBoxContainer/ButtonsRow/ConfirmSaveButton
@onready var _confirm_back: Button = $ConfirmPopup/PopupPanel/Margin/VBoxContainer/ButtonsRow/ConfirmBackButton

## Черновик привязок: action -> physical_keycode. Применяется к игре только по «Сохранить».
var _draft: Dictionary = {}
## Режим бега в черновике (InputSettings.MovementMode).
var _mode_draft: int = InputSettings.MovementMode.KEYBOARD
## Действие, для которого сейчас ждём нажатие клавиши ("" — не в режиме захвата).
var _capturing: String = ""
## action -> Button с текстом клавиши, для обновления подписей.
var _key_buttons: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_confirm_popup.hide()
	_mode_switch.toggled.connect(_on_mode_toggled)
	_save_button.pressed.connect(_on_save_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_confirm_save.pressed.connect(_on_confirm_save_pressed)
	_confirm_back.pressed.connect(_on_confirm_back_pressed)
	if OS.is_debug_build():
		_warn_about_unlisted_actions()

## Загружает текущие настройки в черновик и показывает панель.
func open() -> void:
	_draft.clear()
	for action in _all_actions():
		_draft[action] = InputSettings.current_binding(action)
	_mode_draft = int(InputSettings.movement_mode)
	_capturing = ""
	_capture_hint.text = ""
	_mode_switch.set_pressed_no_signal(_mode_draft == InputSettings.MovementMode.MOUSE)
	_update_mode_labels()
	_rebuild_rows()
	show()

func _all_actions() -> Array:
	return MOVEMENT_ACTIONS + COMMON_ACTIONS

## Предохранитель от забытых клавиш: любое собственное действие проекта (не встроенное
## "ui_*" из Godot), которого нет ни в списке экрана настроек, ни в EXCLUDED_ACTIONS,
## печатается предупреждением в консоль. Так при добавлении нового действия в InputMap
## (Project Settings → Input Map или напрямую в project.godot) разработчик сразу увидит,
## что забыл добавить его в COMMON_ACTIONS/ACTION_LABELS этого экрана — только для debug-сборок.
func _warn_about_unlisted_actions() -> void:
	var known := {}
	for action in _all_actions():
		known[action] = true
	for action in EXCLUDED_ACTIONS:
		known[action] = true
	for action in InputMap.get_actions():
		var action_name := str(action)
		if action_name.begins_with("ui_"):
			continue
		if not known.has(action_name):
			push_warning("ControlsSettings: действие '%s' есть в InputMap, но не отображается в меню настроек управления. Добавь его в COMMON_ACTIONS/ACTION_LABELS (scripts/ui/controls_settings.gd) или в EXCLUDED_ACTIONS, если оно намеренно не переназначается." % action_name)

## Действия, показываемые/редактируемые в текущем режиме бега.
func _visible_actions() -> Array:
	if _mode_draft == InputSettings.MovementMode.MOUSE:
		return COMMON_ACTIONS.duplicate()
	return _all_actions()

func _on_mode_toggled(pressed: bool) -> void:
	_mode_draft = InputSettings.MovementMode.MOUSE if pressed else InputSettings.MovementMode.KEYBOARD
	_cancel_capture()
	_update_mode_labels()
	_rebuild_rows()

func _update_mode_labels() -> void:
	if _mode_draft == InputSettings.MovementMode.MOUSE:
		_mode_value.text = "Мышь (ПКМ)"
		_mode_hint.text = "Бег к точке по правой кнопке мыши. Блок щитом в этом режиме недоступен."
	else:
		_mode_value.text = "Клавиатура (WASD)"
		_mode_hint.text = "Движение на WASD/стрелках. Блок щитом — правой кнопкой мыши."

# ─── Строки привязок ───────────────────────────────────────────────────────

func _rebuild_rows() -> void:
	for child in _rows_container.get_children():
		child.queue_free()
	_key_buttons.clear()
	for action in _visible_actions():
		_rows_container.add_child(_make_row(str(action)))
	_refresh_all_buttons()

func _make_row(action: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = ACTION_LABELS.get(action, action)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var key_button := Button.new()
	key_button.custom_minimum_size = Vector2(130, 0)
	key_button.pressed.connect(_begin_capture.bind(action))
	row.add_child(key_button)
	_key_buttons[action] = key_button
	return row

func _refresh_all_buttons() -> void:
	var duplicates := _duplicate_keycodes()
	for action in _key_buttons:
		var button := _key_buttons[action] as Button
		var keycode := int(_draft.get(action, 0))
		if _capturing == action:
			button.text = "…"
		else:
			button.text = InputSettings.keycode_label(keycode)
		# Красным подсвечиваем клавиши, назначенные более чем на одно действие.
		button.modulate = Color(1.0, 0.5, 0.5) if duplicates.has(keycode) else Color.WHITE

# ─── Захват нажатия клавиши ────────────────────────────────────────────────

func _begin_capture(action: String) -> void:
	_capturing = action
	_capture_hint.text = "Нажмите клавишу для «%s»  (Esc — отмена)" % ACTION_LABELS.get(action, action)
	_refresh_all_buttons()

func _cancel_capture() -> void:
	if _capturing == "":
		return
	_capturing = ""
	_capture_hint.text = ""
	_refresh_all_buttons()

func _input(event: InputEvent) -> void:
	if not visible or _capturing == "" or _confirm_popup.visible:
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var action := _capturing
	_capturing = ""
	_capture_hint.text = ""
	if key.physical_keycode != KEY_ESCAPE:
		var keycode: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		_draft[action] = keycode
	_refresh_all_buttons()
	get_viewport().set_input_as_handled()

# ─── Валидация и сохранение ────────────────────────────────────────────────

## Возвращает { physical_keycode: [actions...] } для клавиш, назначенных >1 раз среди
## видимых сейчас действий (0 = не назначено, не считается дубликатом).
func _duplicate_keycodes() -> Dictionary:
	var used := {}
	for action in _visible_actions():
		var keycode := int(_draft.get(action, 0))
		if keycode == 0:
			continue
		if not used.has(keycode):
			used[keycode] = []
		used[keycode].append(action)
	var duplicates := {}
	for keycode in used:
		if used[keycode].size() > 1:
			duplicates[keycode] = used[keycode]
	return duplicates

func _on_save_pressed() -> void:
	_cancel_capture()
	var duplicates := _duplicate_keycodes()
	if duplicates.is_empty():
		_commit()
		return
	var first_keycode := int(duplicates.keys()[0])
	_confirm_message.text = "Клавиша %s используется несколько раз" % InputSettings.keycode_label(first_keycode)
	_confirm_popup.show()

func _commit() -> void:
	InputSettings.apply_and_save(_mode_draft, _draft)
	_confirm_popup.hide()
	hide()
	closed.emit()

func _on_back_pressed() -> void:
	# Отмена: черновик отбрасывается, к игре ничего не применяется.
	_cancel_capture()
	hide()
	closed.emit()

func _on_confirm_save_pressed() -> void:
	_commit()

func _on_confirm_back_pressed() -> void:
	# Вернуться к редактированию, ничего не сохраняя.
	_confirm_popup.hide()
