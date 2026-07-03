## Главное меню: новая игра, продолжить (последний найденный слот сохранения),
## настройки (громкость, полноэкранный режим), выход.
extends Control

@onready var _continue_button: Button = $CenterContainer/Panel/Margin/VBoxContainer/ButtonsContainer/ContinueButton
@onready var _settings_panel: Panel = $SettingsPanel
@onready var _volume_slider: HSlider = $SettingsPanel/Margin/VBoxContainer/VolumeRow/VolumeSlider
@onready var _fullscreen_check: CheckBox = $SettingsPanel/Margin/VBoxContainer/FullscreenRow/FullscreenCheck

## Слот, который откроет "Продолжить" (-1 = сохранений нет).
var _continue_slot: int = -1

func _ready() -> void:
	_continue_slot = _find_last_save_slot()
	_continue_button.disabled = _continue_slot < 0
	_settings_panel.hide()

	var master_bus: int = AudioServer.get_bus_index("Master")
	_volume_slider.value = db_to_linear(AudioServer.get_bus_volume_db(master_bus))
	_fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

func _on_new_game_pressed() -> void:
	SceneManager.go_to_character_creation()

func _on_continue_pressed() -> void:
	if _continue_slot < 0:
		return
	SaveSystem.load_game(_continue_slot)
	SceneManager.go_to_city()

func _on_settings_pressed() -> void:
	_settings_panel.show()

func _on_settings_back_pressed() -> void:
	_settings_panel.hide()

func _on_exit_pressed() -> void:
	get_tree().quit()

func _on_volume_changed(value: float) -> void:
	var master_bus: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(value))

func _on_fullscreen_toggled(pressed: bool) -> void:
	var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

## Возвращает первый слот с сохранением (0..MAX_SLOTS-1) или -1 если сохранений нет.
func _find_last_save_slot() -> int:
	for slot in SaveSystem.MAX_SLOTS:
		if SaveSystem.has_save(slot):
			return slot
	return -1
