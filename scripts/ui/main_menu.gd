## Главное меню: новая игра, продолжить (последний найденный слот сохранения),
## настройки (громкость, полноэкранный режим), выход.
extends Control

@onready var _new_game_button: Button = $CenterContainer/VBoxContainer/ButtonsContainer/NewGameButton
@onready var _continue_button: Button = $CenterContainer/VBoxContainer/ButtonsContainer/ContinueButton
@onready var _settings_overlay: Control = $SettingsOverlay
@onready var _volume_slider: HSlider = $SettingsOverlay/Panel/Margin/VBoxContainer/VolumeSlider
@onready var _volume_value_label: Label = $SettingsOverlay/Panel/Margin/VBoxContainer/VolumeRow/VolumeValueLabel
@onready var _fullscreen_check: CheckButton = $SettingsOverlay/Panel/Margin/VBoxContainer/FullscreenRow/FullscreenCheck

const CONTROLS_SETTINGS_SCENE := preload("res://scenes/ui/controls_settings.tscn")

## Слот, который откроет "Продолжить" (-1 = сохранений нет).
var _continue_slot: int = -1

## Панель раздела «Управление», инстанцируется в _ready и прячется до вызова open().
var _controls_panel: ControlsSettings = null

func _ready() -> void:
	_continue_slot = _find_last_save_slot()
	_continue_button.disabled = _continue_slot < 0
	_settings_overlay.hide()

	_controls_panel = CONTROLS_SETTINGS_SCENE.instantiate()
	add_child(_controls_panel)
	_controls_panel.hide()

	var master_bus: int = AudioServer.get_bus_index("Master")
	_volume_slider.value = db_to_linear(AudioServer.get_bus_volume_db(master_bus))
	_update_volume_label(_volume_slider.value)
	_fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_new_game_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _settings_overlay.visible:
		_settings_overlay.hide()
		get_viewport().set_input_as_handled()

func _on_new_game_pressed() -> void:
	SceneManager.go_to_character_creation()

func _on_continue_pressed() -> void:
	if _continue_slot < 0:
		return
	SaveSystem.load_game(_continue_slot)
	SceneManager.go_to_city()

func _on_settings_pressed() -> void:
	_settings_overlay.show()

func _on_settings_back_pressed() -> void:
	_settings_overlay.hide()

func _on_controls_pressed() -> void:
	_controls_panel.open()

func _on_exit_pressed() -> void:
	get_tree().quit()

func _on_volume_changed(value: float) -> void:
	var master_bus: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(value))
	_update_volume_label(value)

func _update_volume_label(value: float) -> void:
	_volume_value_label.text = "%d%%" % roundi(value * 100.0)

func _on_fullscreen_toggled(pressed: bool) -> void:
	var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

## Возвращает первый слот с сохранением (0..MAX_SLOTS-1) или -1 если сохранений нет.
func _find_last_save_slot() -> int:
	for slot in SaveSystem.MAX_SLOTS:
		if SaveSystem.has_save(slot):
			return slot
	return -1
