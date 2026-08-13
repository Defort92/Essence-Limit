## Меню паузы: не переключает паузу сама — только реагирует на сигналы PauseManager.
## Если пауза уже "занята" другим модальным экраном (группа "modal_screen"),
## не показывается поверх него — тот экран сам закроет её по ESC.
extends CanvasLayer


@onready var _settings_panel: Panel = $Dim/SettingsPanel
@onready var _volume_slider: HSlider = $Dim/SettingsPanel/Margin/VBoxContainer/VolumeRow/VolumeSlider
@onready var _fullscreen_check: CheckButton = $Dim/SettingsPanel/Margin/VBoxContainer/FullscreenRow/FullscreenCheck
@onready var _camera_distance_slider: HSlider = $Dim/SettingsPanel/Margin/VBoxContainer/CameraDistanceRow/CameraDistanceSlider
@onready var _camera_distance_value: Label = $Dim/SettingsPanel/Margin/VBoxContainer/CameraDistanceRow/CameraDistanceValue

## Панель раздела «Управление», инстанцируется в _ready и прячется до вызова open().
var _controls_panel: ControlsSettings = null
var _developer_visual_panel: DeveloperVisualSettings = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	hide()
	_settings_panel.hide()
	PauseManager.paused.connect(_on_paused)
	PauseManager.unpaused.connect(_on_unpaused)

	_controls_panel = PauseMenuConstants.CONTROLS_SETTINGS_SCENE.instantiate()
	add_child(_controls_panel)
	_controls_panel.hide()
	_developer_visual_panel = PauseMenuConstants.DEVELOPER_VISUAL_SETTINGS_SCENE.instantiate()
	add_child(_developer_visual_panel)
	_developer_visual_panel.hide()

func _on_paused() -> void:
	if _other_overlay_open():
		return
	show()

func _on_unpaused() -> void:
	hide()
	_settings_panel.hide()
	if _developer_visual_panel != null:
		_developer_visual_panel.hide()

## Не открываем меню поверх экрана, который сам держит паузу (сейчас — состояния).
## Непаусящие окна при Esc закрываются и не мешают обычному меню паузы.
func _other_overlay_open() -> bool:
	for screen in get_tree().get_nodes_in_group("modal_screen"):
		if screen.visible and screen.get("pauses_game") == true:
			return true
	return false

func _on_resume_pressed() -> void:
	PauseManager.unpause()

func _on_save_slot_pressed(slot: int) -> void:
	SaveSystem.save(slot)

func _on_settings_pressed() -> void:
	var master_bus: int = AudioServer.get_bus_index("Master")
	_volume_slider.value = db_to_linear(AudioServer.get_bus_volume_db(master_bus))
	_fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_camera_distance_slider.set_value_no_signal(CameraSettings.distance)
	_update_camera_distance_label(CameraSettings.distance)
	_settings_panel.show()

func _on_settings_back_pressed() -> void:
	_settings_panel.hide()

func _on_controls_pressed() -> void:
	_controls_panel.open()

func _on_developer_visual_settings_pressed() -> void:
	_developer_visual_panel.open()

func _on_volume_changed(value: float) -> void:
	var master_bus: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(value))

func _on_fullscreen_toggled(pressed: bool) -> void:
	var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

func _on_camera_distance_changed(value: float) -> void:
	CameraSettings.set_distance(value)
	_update_camera_distance_label(CameraSettings.distance)

func _update_camera_distance_label(value: float) -> void:
	_camera_distance_value.text = "%.1f" % value

func _on_main_menu_pressed() -> void:
	PauseManager.unpause()
	SceneManager.go_to_main_menu()

func _on_quit_pressed() -> void:
	get_tree().quit()
