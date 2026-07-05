## Хранит и применяет пользовательские настройки управления: режим передвижения
## (клавиатура WASD / мышь ПКМ) и привязки клавиш к действиям (InputMap).
## Является Autoload-синглтоном; регистрировать как "InputSettings" в Project Settings.
##
## Настройки применяются к InputMap и сохраняются в user://settings.cfg ТОЛЬКО когда
## UI явно вызывает apply_and_save() (кнопка «Сохранить»). До этого правки живут лишь
## в черновике UI и на игру не влияют.
extends Node

const SETTINGS_PATH := "user://settings.cfg"

## Способ передвижения персонажа. KEYBOARD — WASD/стрелки, MOUSE — бег к точке по ПКМ.
enum MovementMode { KEYBOARD, MOUSE }

var movement_mode: MovementMode = MovementMode.KEYBOARD

signal movement_mode_changed(mode: int)

func _ready() -> void:
	load_settings()

## Читает сохранённые настройки и применяет их к InputMap. Если файла нет — оставляет
## значения по умолчанию из project.godot.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		movement_mode = MovementMode.KEYBOARD
		return
	movement_mode = int(cfg.get_value("controls", "movement_mode", 0)) as MovementMode
	if cfg.has_section("keybinds"):
		for action in cfg.get_section_keys("keybinds"):
			_apply_binding(action, int(cfg.get_value("keybinds", action)))

## Применяет переданный режим передвижения и привязки к InputMap и сохраняет их на диск.
## Вызывается из UI настроек по кнопке «Сохранить». [param bindings] — action -> physical_keycode.
func apply_and_save(mode: int, bindings: Dictionary) -> void:
	movement_mode = mode as MovementMode
	for action in bindings:
		_apply_binding(str(action), int(bindings[action]))
	_save_to_disk(bindings)
	movement_mode_changed.emit(int(movement_mode))

## Возвращает физический keycode клавиши, назначенной на [param action] в текущем InputMap
## (0 если это действие без клавиши — например, привязано к кнопке мыши).
func current_binding(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var key := ev as InputEventKey
			return key.physical_keycode if key.physical_keycode != 0 else key.keycode
	return 0

## Человекочитаемое имя клавиши по её физическому keycode (для текущей раскладки).
static func keycode_label(physical_keycode: int) -> String:
	if physical_keycode == 0:
		return "—"
	var logical := DisplayServer.keyboard_get_keycode_from_physical(physical_keycode)
	var label := OS.get_keycode_string(logical)
	if label.is_empty():
		label = OS.get_keycode_string(physical_keycode)
	return label if not label.is_empty() else "?"

func _apply_binding(action: String, physical_keycode: int) -> void:
	if not InputMap.has_action(action) or physical_keycode == 0:
		return
	# Снимаем старые клавиатурные события, но сохраняем события мыши (attack/block и т.п.).
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = physical_keycode
	InputMap.action_add_event(action, key_event)

func _save_to_disk(bindings: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "movement_mode", int(movement_mode))
	for action in bindings:
		cfg.set_value("keybinds", str(action), int(bindings[action]))
	cfg.save(SETTINGS_PATH)
