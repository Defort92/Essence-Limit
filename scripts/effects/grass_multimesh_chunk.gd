@tool
extends MultiMeshInstance3D
class_name GrassMultiMeshChunk

## Generates a stable grid of slightly randomized grass cards.
## The generated transforms live in one MultiMesh and have no physics bodies.

@export var blade_mesh: Mesh
@export var area_size := Vector2(16.0, 16.0)
@export_range(0.0, 160.0, 1.0) var density_per_square_meter := 30.0
@export_range(100, 30000, 100) var maximum_instances := 15000
@export var random_seed := 8042
@export_range(0.0, 1.0, 0.01) var position_jitter := 0.82
@export_range(0.5, 1.5, 0.01) var minimum_scale := 0.82
@export_range(0.5, 1.8, 0.01) var maximum_scale := 1.18

## Keeps the prototype's horizontal modular path free from grass.
@export_range(0.0, 4.0, 0.05) var path_clear_half_width := 1.05
## Optional exclusion rectangle in local X/Z coordinates.
@export var exclusion_rect := Rect2(Vector2(2.0, 1.0), Vector2(6.0, 6.0))

@export_node_path("Node3D") var interactor_path: NodePath
@export_range(0.1, 4.0, 0.05) var interactor_radius := 0.9
@export_range(1.0, 30.0, 1.0) var interaction_updates_per_second := 10.0

var _interaction_accumulator := 0.0
var _character_positions: Array[Vector4] = []


func _ready() -> void:
	_rebuild()
	_character_positions.resize(8)
	_clear_character_positions()
	set_process(not interactor_path.is_empty())


func _process(delta: float) -> void:
	_interaction_accumulator += delta
	var update_interval := 1.0 / maxf(interaction_updates_per_second, 1.0)
	if _interaction_accumulator < update_interval:
		return
	_interaction_accumulator = fmod(_interaction_accumulator, update_interval)

	var interactor := get_node_or_null(interactor_path) as Node3D
	var grass_material := material_override as ShaderMaterial
	if interactor != null and grass_material != null:
		_clear_character_positions()
		var position := interactor.global_position
		_character_positions[0] = Vector4(position.x, position.y, position.z, interactor_radius)
		grass_material.set_shader_parameter("character_positions", _character_positions)


func _clear_character_positions() -> void:
	for index in _character_positions.size():
		_character_positions[index] = Vector4.ZERO


func set_density(value: float) -> void:
	density_per_square_meter = clampf(value, 0.0, 160.0)
	_rebuild()


func get_visible_grass_count() -> int:
	if multimesh == null:
		return 0
	return multimesh.visible_instance_count


func _rebuild() -> void:
	if blade_mesh == null:
		return
	if is_zero_approx(density_per_square_meter):
		multimesh = null
		return

	var target_count := mini(
		maximum_instances,
		roundi(area_size.x * area_size.y * density_per_square_meter)
	)
	var cell_size := sqrt((area_size.x * area_size.y) / float(target_count))
	var columns := maxi(1, ceili(area_size.x / cell_size))
	var rows := maxi(1, ceili(area_size.y / cell_size))
	var capacity := mini(maximum_instances, columns * rows)

	var generated := MultiMesh.new()
	generated.transform_format = MultiMesh.TRANSFORM_3D
	generated.mesh = blade_mesh
	generated.instance_count = capacity
	generated.visible_instance_count = 0
	generated.custom_aabb = AABB(
		Vector3(-area_size.x * 0.5, -0.1, -area_size.y * 0.5),
		Vector3(area_size.x, 1.2, area_size.y)
	)

	var random := RandomNumberGenerator.new()
	random.seed = random_seed
	var written := 0

	for row in rows:
		for column in columns:
			if written >= capacity:
				break

			var base_x := (float(column) + 0.5) / float(columns) * area_size.x - area_size.x * 0.5
			var base_z := (float(row) + 0.5) / float(rows) * area_size.y - area_size.y * 0.5
			var jitter_x := random.randf_range(-0.5, 0.5) * cell_size * position_jitter
			var jitter_z := random.randf_range(-0.5, 0.5) * cell_size * position_jitter
			var local_position := Vector3(base_x + jitter_x, 0.02, base_z + jitter_z)

			if absf(local_position.z) < path_clear_half_width:
				continue
			if exclusion_rect.has_point(Vector2(local_position.x, local_position.z)):
				continue

			var uniform_scale := random.randf_range(minimum_scale, maximum_scale)
			var basis := Basis.IDENTITY.scaled(Vector3(uniform_scale, uniform_scale, uniform_scale))
			generated.set_instance_transform(written, Transform3D(basis, local_position))
			written += 1

	generated.visible_instance_count = written
	multimesh = generated
