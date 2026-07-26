extends CharacterBody3D

@export_range(0.1, 20.0, 0.1) var move_speed := 4.5
@export_range(1.0, 20.0, 0.5) var camera_follow_speed := 8.0
@export var movement_bounds := Vector2(8.0, 8.0)
@export_node_path("Camera3D") var camera_path: NodePath

@onready var _camera := get_node_or_null(camera_path) as Camera3D
@onready var _sprite := get_node_or_null("Sprite3D") as DirectionalSprite3D

var _camera_offset := Vector3.ZERO


func _ready() -> void:
	if _camera != null:
		_camera_offset = _camera.global_position - global_position


func _physics_process(_delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := _camera_relative_direction(input)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	velocity = direction * move_speed
	move_and_slide()

	position.x = clampf(position.x, -movement_bounds.x, movement_bounds.x)
	position.z = clampf(position.z, -movement_bounds.y, movement_bounds.y)

	if _sprite != null:
		_sprite.face_direction(_camera_view_direction(Vector3(velocity.x, 0.0, velocity.z)))
		_sprite.set_moving(velocity.length_squared() > 0.01)


func _process(delta: float) -> void:
	if _camera == null:
		return
	var desired_position := global_position + _camera_offset
	var follow_weight := 1.0 - exp(-camera_follow_speed * delta)
	_camera.global_position = _camera.global_position.lerp(desired_position, follow_weight)


## Преобразует экранный WASD-ввод в направление по земле относительно камеры:
## W всегда уводит персонажа к верхнему краю экрана, D — к правому.
func _camera_relative_direction(input: Vector2) -> Vector3:
	if _camera == null:
		return Vector3(input.x, 0.0, input.y)

	var camera_right := _camera.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()

	var camera_forward := -_camera.global_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()

	return camera_right * input.x - camera_forward * input.y


## DirectionalSprite3D выбирает кадр в экранных координатах (+Z — к камере).
## Переводим фактическое мировое движение обратно в эту систему координат.
func _camera_view_direction(world_direction: Vector3) -> Vector3:
	if _camera == null or world_direction.length_squared() < 0.0001:
		return world_direction

	var camera_right := _camera.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()

	var towards_camera := _camera.global_basis.z
	towards_camera.y = 0.0
	towards_camera = towards_camera.normalized()

	return Vector3(
		world_direction.dot(camera_right),
		0.0,
		world_direction.dot(towards_camera)
	)
