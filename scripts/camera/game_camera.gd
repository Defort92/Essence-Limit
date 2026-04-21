extends Camera3D

# Угол камеры: ~60° вниз, фиксирован — 2.5D перспектива
const PITCH_DEG: float = -60.0
const FOLLOW_SPEED: float = 8.0

# Смещение камеры относительно цели в мировых координатах
@export var offset: Vector3 = Vector3(0.0, 18.0, 11.0)

var _target: Node3D

func _ready() -> void:
	rotation_degrees = Vector3(PITCH_DEG, 0.0, 0.0)
	await get_tree().process_frame
	_target = get_tree().get_first_node_in_group("player")

func _process(delta: float) -> void:
	if _target == null:
		return
	var desired := _target.global_position + offset
	global_position = global_position.lerp(desired, FOLLOW_SPEED * delta)
