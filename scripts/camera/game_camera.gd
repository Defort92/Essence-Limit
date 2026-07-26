extends Camera3D


# Смещение камеры относительно цели в мировых координатах
@export var offset: Vector3 = Vector3(0.0, 10.0, 10.0)

var _target: Node3D

func _ready() -> void:
	rotation_degrees = Vector3(GameCameraConstants.PITCH_DEG, 0.0, 0.0)
	PartySystem.active_member_changed.connect(_on_active_member_changed)
	await get_tree().process_frame
	_target = PartySystem.get_active_member()

func _process(delta: float) -> void:
	if _target == null:
		return
	var desired := _target.global_position + offset
	global_position = global_position.lerp(desired, GameCameraConstants.FOLLOW_SPEED * delta)

## Плавно перенацеливается на нового активного участника при переключении управления.
func _on_active_member_changed(_old_member: Player, new_member: Player) -> void:
	_target = new_member
