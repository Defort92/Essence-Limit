## Меню паузы: не переключает паузу сама — только реагирует на сигналы PauseManager.
## Если пауза уже "занята" другим модальным экраном (группа "modal_screen"),
## не показывается поверх него — тот экран сам закроет её по ESC.
extends CanvasLayer

const CONTROLS_SETTINGS_SCENE := preload("res://scenes/ui/controls_settings.tscn")

@onready var _settings_panel: Panel = $Dim/SettingsPanel
@onready var _volume_slider: HSlider = $Dim/SettingsPanel/Margin/VBoxContainer/VolumeRow/VolumeSlider
@onready var _fullscreen_check: CheckButton = $Dim/SettingsPanel/Margin/VBoxContainer/FullscreenRow/FullscreenCheck

## Панель раздела «Управление», инстанцируется в _ready и прячется до вызова open().
var _controls_panel: ControlsSettings = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	hide()
	_settings_panel.hide()
	PauseManager.paused.connect(_on_paused)
	PauseManager.unpaused.connect(_on_unpaused)

	_controls_panel = CONTROLS_SETTINGS_SCENE.instantiate()
	add_child(_controls_panel)
	_controls_panel.hide()

func _on_paused() -> void:
	if _other_overlay_open():
		return
	show()

func _on_unpaused() -> void:
	hide()
	_settings_panel.hide()

## Все модальные экраны (обыск, лавка, персонаж, состояния) регистрируются в общей
## группе "modal_screen" через UIModalScreen — новые экраны учитываются автоматически.
func _other_overlay_open() -> bool:
	for screen in get_tree().get_nodes_in_group("modal_screen"):
		if screen.visible:
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
	_settings_panel.show()

func _on_settings_back_pressed() -> void:
	_settings_panel.hide()

func _on_controls_pressed() -> void:
	_controls_panel.open()

func _on_volume_changed(value: float) -> void:
	var master_bus: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(value))

func _on_fullscreen_toggled(pressed: bool) -> void:
	var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

func _on_main_menu_pressed() -> void:
	PauseManager.unpause()
	SceneManager.go_to_main_menu()

func _on_quit_pressed() -> void:
	get_tree().quit()
