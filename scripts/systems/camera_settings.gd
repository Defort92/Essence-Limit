## Stores the camera distance selected in the settings menu.
## Registered as the CameraSettings autoload singleton.
extends Node


signal distance_changed(value: float)

const SETTINGS_PATH := "user://settings.cfg"

var distance: float = GameCameraConstants.DEFAULT_DISTANCE

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		distance = _normalized_distance(float(cfg.get_value(
			"display", "camera_distance", GameCameraConstants.DEFAULT_DISTANCE
		)))

func set_distance(value: float) -> void:
	var normalized := _normalized_distance(value)
	if is_equal_approx(normalized, distance):
		return
	distance = normalized
	_save()
	distance_changed.emit(distance)

func _normalized_distance(value: float) -> float:
	var clamped := clampf(
		value,
		GameCameraConstants.MIN_DISTANCE,
		GameCameraConstants.MAX_DISTANCE
	)
	return snappedf(clamped, GameCameraConstants.DISTANCE_STEP)

func _save() -> void:
	var cfg := ConfigFile.new()
	# Keep the settings written by the controls and font systems.
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "camera_distance", distance)
	cfg.save(SETTINGS_PATH)
