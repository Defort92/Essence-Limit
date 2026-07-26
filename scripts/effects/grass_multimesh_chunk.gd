@tool
extends MultiMeshInstance3D
class_name GrassMultiMeshChunk

## Generates a stable grid of slightly randomized grass cards.
## The generated transforms live in one MultiMesh and have no physics bodies.

@export var blade_mesh: Mesh
@export var area_size := Vector2(16.0, 16.0)
@export_range(0.0, 160.0, 1.0) var density_per_square_meter := 30.0
@export_range(100, 60000, 100) var maximum_instances := 15000
@export var random_seed := 8042
@export_range(0.0, 1.0, 0.01) var position_jitter := 0.82
@export_range(0.5, 1.5, 0.01) var minimum_scale := 0.82
@export_range(0.5, 1.8, 0.01) var maximum_scale := 1.18

## Optional world-space coverage map. Its alpha channel controls where blades
## may be generated, so paths and clearings use the same layout as the floor.
@export var coverage_texture: Texture2D
@export var coverage_world_origin := Vector2(-30.0, -30.0)
@export var coverage_world_size := Vector2(60.0, 60.0)
@export_range(0.0, 1.0, 0.01) var coverage_threshold := 0.72

## Keeps the prototype's horizontal modular path free from grass.
@export_range(0.0, 4.0, 0.05) var path_clear_half_width := 1.05
## Optional exclusion rectangle in local X/Z coordinates.
@export var exclusion_rect := Rect2(Vector2(2.0, 1.0), Vector2(6.0, 6.0))

@export_node_path("Node3D") var interactor_path: NodePath
@export var interactor_group: StringName
@export_range(0.1, 4.0, 0.05) var interactor_radius := 0.9
@export_range(1.0, 30.0, 1.0) var interaction_updates_per_second := 10.0

var _interaction_accumulator := 0.0
var _character_positions: Array[Vector4] = []


func _ready() -> void:
	_rebuild()
	_character_positions.resize(8)
	_clear_character_positions()
	set_process(not interactor_path.is_empty() or not interactor_group.is_empty())


func _process(delta: float) -> void:
	_interaction_accumulator += delta
	var update_interval := 1.0 / maxf(interaction_updates_per_second, 1.0)
	if _interaction_accumulator < update_interval:
		return
	_interaction_accumulator = fmod(_interaction_accumulator, update_interval)

	var grass_material := material_override as ShaderMaterial
	if grass_material == null:
		return

	_clear_character_positions()
	var written := 0
	if not interactor_group.is_empty():
		for candidate in get_tree().get_nodes_in_group(interactor_group):
			var interactor := candidate as Node3D
			if interactor == null:
				continue
			var position := interactor.global_position
			_character_positions[written] = Vector4(position.x, position.y, position.z, interactor_radius)
			written += 1
			if written >= _character_positions.size():
				break
	else:
		var interactor := get_node_or_null(interactor_path) as Node3D
		if interactor != null:
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

	var coverage_image := _load_coverage_image()
	if coverage_texture != null and (coverage_image == null or coverage_image.is_empty()):
		push_warning(
			"Grass coverage texture could not be read; grass generation was disabled for %s." % name
		)
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
			if not _is_inside_coverage(local_position, coverage_image):
				continue

			var uniform_scale := random.randf_range(minimum_scale, maximum_scale)
			var basis := Basis.IDENTITY.scaled(Vector3(uniform_scale, uniform_scale, uniform_scale))
			generated.set_instance_transform(written, Transform3D(basis, local_position))
			written += 1

	generated.visible_instance_count = written
	multimesh = generated


func _load_coverage_image() -> Image:
	if coverage_texture == null:
		return null

	# Reading the source PNG first preserves its alpha channel even when Godot
	# imported the Texture2D using a GPU-oriented compression mode.
	var source_path := coverage_texture.resource_path
	if not source_path.is_empty() and source_path.get_extension().to_lower() == "png":
		var source_image := Image.load_from_file(source_path)
		if source_image != null and not source_image.is_empty():
			return source_image

	return coverage_texture.get_image()


func _is_inside_coverage(local_position: Vector3, coverage_image: Image) -> bool:
	if coverage_texture != null and (coverage_image == null or coverage_image.is_empty()):
		return false
	if coverage_image == null:
		return true
	if coverage_world_size.x <= 0.0 or coverage_world_size.y <= 0.0:
		return true

	var world_position := global_transform * local_position
	var uv := (
		Vector2(world_position.x, world_position.z) - coverage_world_origin
	) / coverage_world_size
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return false

	var pixel_x := clampi(roundi(uv.x * float(coverage_image.get_width() - 1)), 0, coverage_image.get_width() - 1)
	var pixel_y := clampi(roundi(uv.y * float(coverage_image.get_height() - 1)), 0, coverage_image.get_height() - 1)
	return coverage_image.get_pixel(pixel_x, pixel_y).a >= coverage_threshold
