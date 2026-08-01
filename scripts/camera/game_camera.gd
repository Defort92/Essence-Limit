extends Camera3D


var _target: Node3D
var _offset_direction: Vector3
var _camera_offset: Vector3
var _perspective_fov: float

func _ready() -> void:
	rotation_degrees = Vector3(GameCameraConstants.PITCH_DEG, 0.0, 0.0)
	# Preserve the original 45-degree position relative to the player. The screen
	# centering is handled by an off-axis projection, not by changing this angle.
	_offset_direction = Vector3(0.0, 1.0, 1.0).normalized()
	_perspective_fov = fov
	projection = Camera3D.PROJECTION_FRUSTUM
	_set_camera_distance(CameraSettings.distance)
	CameraSettings.distance_changed.connect(_set_camera_distance)
	PartySystem.active_member_changed.connect(_on_active_member_changed)
	await get_tree().process_frame
	_target = PartySystem.get_active_member()

func _process(delta: float) -> void:
	if _target == null:
		return
	var desired := _target.global_position + _camera_offset
	global_position = global_position.lerp(desired, GameCameraConstants.FOLLOW_SPEED * delta)

## Плавно перенацеливается на нового активного участника при переключении управления.
func _on_active_member_changed(_old_member: Player, new_member: Player) -> void:
	_target = new_member

func _set_camera_distance(value: float) -> void:
	_camera_offset = _offset_direction * value
	_update_projection_offset()

## Shifts only the projection center so the middle of the 2D character sprite is
## centered without changing the camera position or its fixed viewing angle.
func _update_projection_offset() -> void:
	size = 2.0 * near * tan(deg_to_rad(_perspective_fov) * 0.5)
	var relative_focus := Vector3.UP * GameCameraConstants.TARGET_FOCUS_HEIGHT - _camera_offset
	var camera_space := transform.basis.inverse() * relative_focus
	var center_y := camera_space.y * near / -camera_space.z
	frustum_offset = Vector2(0.0, center_y)
