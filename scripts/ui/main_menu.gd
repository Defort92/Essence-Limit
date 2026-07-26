## Главное меню: новая игра, продолжить (последний найденный слот сохранения),
## настройки (громкость, полноэкранный режим), выход.
extends Control

@onready var _new_game_button: Button = $LeftPanel/ContentMargin/ContentContainer/ButtonsContainer/NewGameButton
@onready var _continue_button: Button = $LeftPanel/ContentMargin/ContentContainer/ButtonsContainer/ContinueButton
@onready var _settings_overlay: Control = $SettingsOverlay
@onready var _volume_slider: HSlider = $SettingsOverlay/Panel/Margin/VBoxContainer/VolumeSlider
@onready var _volume_value_label: Label = $SettingsOverlay/Panel/Margin/VBoxContainer/VolumeRow/VolumeValueLabel
@onready var _fullscreen_check: CheckButton = $SettingsOverlay/Panel/Margin/VBoxContainer/FullscreenRow/FullscreenCheck
@onready var _font_option: OptionButton = $SettingsOverlay/Panel/Margin/VBoxContainer/FontRow/FontOption
@onready var _body_font_option: OptionButton = $SettingsOverlay/Panel/Margin/VBoxContainer/BodyFontRow/BodyFontOption


## Слот, который откроет "Продолжить" (-1 = сохранений нет).
var _continue_slot: int = -1

## Панель раздела «Управление», инстанцируется в _ready и прячется до вызова open().
var _controls_panel: ControlsSettings = null

func _ready() -> void:
	_continue_slot = _find_last_save_slot()
	_continue_button.disabled = _continue_slot < 0
	_settings_overlay.hide()

	_controls_panel = MainMenuConstants.CONTROLS_SETTINGS_SCENE.instantiate()
	add_child(_controls_panel)
	_controls_panel.hide()

	var master_bus: int = AudioServer.get_bus_index("Master")
	_volume_slider.value = db_to_linear(AudioServer.get_bus_volume_db(master_bus))
	_update_volume_label(_volume_slider.value)
	_fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_setup_font_option()
	_new_game_button.grab_focus()

## Заполняет выпадающие списки шрифтов (заголовок и основной текст) и выделяет текущий выбор.
func _setup_font_option() -> void:
	var names := FontSettings.font_names()
	_font_option.clear()
	_body_font_option.clear()
	for font_name in names:
		_font_option.add_item(font_name)
		_body_font_option.add_item(font_name)
	_font_option.select(FontSettings.title_index)
	_body_font_option.select(FontSettings.body_index)

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

func _on_font_selected(index: int) -> void:
	FontSettings.select_title_font(index)

func _on_body_font_selected(index: int) -> void:
	FontSettings.select_body_font(index)

func _on_fullscreen_toggled(pressed: bool) -> void:
	var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

## Возвращает первый слот с сохранением (0..MAX_SLOTS-1) или -1 если сохранений нет.
func _find_last_save_slot() -> int:
	for slot in SaveSystemConstants.MAX_SLOTS:
		if SaveSystem.has_save(slot):
			return slot
	return -1
