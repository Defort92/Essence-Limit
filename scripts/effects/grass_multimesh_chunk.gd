@tool
extends MultiMeshInstance3D
class_name GrassMultiMeshChunk

## Generates a stable grid of slightly randomized grass cards.
## The generated transforms live in one MultiMesh and have no physics bodies.

enum BuildMode {
	USE_EXISTING,
	GENERATE_IF_EMPTY,
	ALWAYS_REBUILD,
}

@export var blade_mesh: Mesh
## GENERATE_IF_EMPTY prevents loading a serialized buffer and rebuilding it
## immediately. ALWAYS_REBUILD is intended only for explicit regeneration tests.
@export var build_mode := BuildMode.GENERATE_IF_EMPTY
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
## Optional shared CPU image supplied by GrassChunkGrid so streamed chunks do
## not download/read the same coverage texture on every rebuild.
var coverage_image_override: Image
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
var _last_rebuild_benchmark: Dictionary = {}
var _incremental_generated: MultiMesh
var _incremental_coverage_image: Image
var _incremental_random: RandomNumberGenerator
var _incremental_started_us := 0
var _incremental_population_us := 0
var _incremental_columns := 0
var _incremental_rows := 0
var _incremental_capacity := 0
var _incremental_candidate_index := 0
var _incremental_written := 0
var _incremental_cell_size := 0.0
var _is_incremental_rebuild_active := false


func _ready() -> void:
	add_to_group("grass_benchmark")
	match build_mode:
		BuildMode.USE_EXISTING:
			_capture_existing_multimesh()
		BuildMode.GENERATE_IF_EMPTY:
			if multimesh == null:
				_rebuild()
			else:
				_capture_existing_multimesh()
		BuildMode.ALWAYS_REBUILD:
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
			var interactor_position := interactor.global_position
			_character_positions[written] = Vector4(
				interactor_position.x,
				interactor_position.y,
				interactor_position.z,
				interactor_radius
			)
			written += 1
			if written >= _character_positions.size():
				break
	else:
		var interactor := get_node_or_null(interactor_path) as Node3D
		if interactor != null:
			var interactor_position := interactor.global_position
			_character_positions[0] = Vector4(
				interactor_position.x,
				interactor_position.y,
				interactor_position.z,
				interactor_radius
			)

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


func get_rebuild_benchmark() -> Dictionary:
	return _last_rebuild_benchmark.duplicate()


func is_incremental_rebuild_active() -> bool:
	return _is_incremental_rebuild_active


## Prepares an empty MultiMesh and the immutable data needed for a budgeted
## rebuild. Call continue_incremental_rebuild() on later frames until it returns
## true. Godot resources stay on the main thread.
func begin_incremental_rebuild() -> bool:
	_begin_rebuild()
	return not _is_incremental_rebuild_active


## Processes at most candidate_budget placement candidates. Returns true when
## the finished MultiMesh has been published.
func continue_incremental_rebuild(candidate_budget: int) -> bool:
	if not _is_incremental_rebuild_active:
		return true

	var population_started_us := Time.get_ticks_usec()
	var processed := 0
	var candidate_total := _incremental_columns * _incremental_rows
	while (
		processed < maxi(candidate_budget, 1)
		and _incremental_candidate_index < candidate_total
		and _incremental_written < _incremental_capacity
	):
		var candidate_index := _incremental_candidate_index
		_incremental_candidate_index += 1
		processed += 1

		var row := candidate_index / _incremental_columns
		var column := candidate_index % _incremental_columns
		var base_x := (
			(float(column) + 0.5) / float(_incremental_columns) * area_size.x
			- area_size.x * 0.5
		)
		var base_z := (
			(float(row) + 0.5) / float(_incremental_rows) * area_size.y
			- area_size.y * 0.5
		)
		var jitter_x := (
			_incremental_random.randf_range(-0.5, 0.5)
			* _incremental_cell_size
			* position_jitter
		)
		var jitter_z := (
			_incremental_random.randf_range(-0.5, 0.5)
			* _incremental_cell_size
			* position_jitter
		)
		var local_position := Vector3(base_x + jitter_x, 0.02, base_z + jitter_z)

		if absf(local_position.z) < path_clear_half_width:
			continue
		if exclusion_rect.has_point(Vector2(local_position.x, local_position.z)):
			continue
		if not _is_inside_coverage(local_position, _incremental_coverage_image):
			continue

		var uniform_scale := _incremental_random.randf_range(minimum_scale, maximum_scale)
		var instance_basis := Basis.IDENTITY.scaled(
			Vector3(uniform_scale, uniform_scale, uniform_scale)
		)
		_incremental_generated.set_instance_transform(
			_incremental_written,
			Transform3D(instance_basis, local_position)
		)
		_incremental_written += 1

	_incremental_population_us += Time.get_ticks_usec() - population_started_us
	if (
		_incremental_candidate_index < candidate_total
		and _incremental_written < _incremental_capacity
	):
		return false

	_publish_incremental_rebuild()
	return true


func _capture_existing_multimesh() -> void:
	_last_rebuild_benchmark = {
		"action": "used existing",
		"total_ms": 0.0,
		"coverage_image_ms": 0.0,
		"allocation_ms": 0.0,
		"population_ms": 0.0,
		"publish_ms": 0.0,
		"candidate_count": 0,
		"visible_count": get_visible_grass_count(),
	}


func _rebuild() -> void:
	_begin_rebuild()
	while _is_incremental_rebuild_active:
		continue_incremental_rebuild(1000000)


func _begin_rebuild() -> void:
	_incremental_started_us = Time.get_ticks_usec()
	_incremental_population_us = 0
	_is_incremental_rebuild_active = false
	_last_rebuild_benchmark = {
		"action": "generated",
		"total_ms": 0.0,
		"coverage_image_ms": 0.0,
		"allocation_ms": 0.0,
		"population_ms": 0.0,
		"publish_ms": 0.0,
		"candidate_count": 0,
		"visible_count": 0,
	}
	if blade_mesh == null:
		_last_rebuild_benchmark["total_ms"] = _elapsed_ms(_incremental_started_us)
		return
	if is_zero_approx(density_per_square_meter):
		multimesh = null
		_last_rebuild_benchmark["total_ms"] = _elapsed_ms(_incremental_started_us)
		return

	var coverage_started_us := Time.get_ticks_usec()
	_incremental_coverage_image = _load_coverage_image()
	_last_rebuild_benchmark["coverage_image_ms"] = _elapsed_ms(coverage_started_us)
	if (
		coverage_texture != null
		and (
			_incremental_coverage_image == null
			or _incremental_coverage_image.is_empty()
		)
	):
		push_warning(
			"Grass coverage texture could not be read; grass generation was disabled for %s." % name
		)
		multimesh = null
		_last_rebuild_benchmark["total_ms"] = _elapsed_ms(_incremental_started_us)
		return

	var target_count := mini(
		maximum_instances,
		roundi(area_size.x * area_size.y * density_per_square_meter)
	)
	_incremental_cell_size = sqrt((area_size.x * area_size.y) / float(target_count))
	_incremental_columns = maxi(1, ceili(area_size.x / _incremental_cell_size))
	_incremental_rows = maxi(1, ceili(area_size.y / _incremental_cell_size))
	_incremental_capacity = mini(
		maximum_instances,
		_incremental_columns * _incremental_rows
	)

	var allocation_started_us := Time.get_ticks_usec()
	_incremental_generated = MultiMesh.new()
	_incremental_generated.transform_format = MultiMesh.TRANSFORM_3D
	_incremental_generated.mesh = blade_mesh
	_incremental_generated.instance_count = _incremental_capacity
	_incremental_generated.visible_instance_count = 0
	_incremental_generated.custom_aabb = AABB(
		Vector3(-area_size.x * 0.5, -0.1, -area_size.y * 0.5),
		Vector3(area_size.x, 1.2, area_size.y)
	)
	_last_rebuild_benchmark["allocation_ms"] = _elapsed_ms(allocation_started_us)

	_incremental_random = RandomNumberGenerator.new()
	_incremental_random.seed = random_seed
	_incremental_candidate_index = 0
	_incremental_written = 0
	_is_incremental_rebuild_active = true


func _publish_incremental_rebuild() -> void:
	var publish_started_us := Time.get_ticks_usec()
	_incremental_generated.visible_instance_count = _incremental_written
	multimesh = _incremental_generated
	_last_rebuild_benchmark["publish_ms"] = _elapsed_ms(publish_started_us)
	_last_rebuild_benchmark["population_ms"] = float(_incremental_population_us) / 1000.0
	_last_rebuild_benchmark["candidate_count"] = _incremental_candidate_index
	_last_rebuild_benchmark["visible_count"] = _incremental_written
	_last_rebuild_benchmark["total_ms"] = _elapsed_ms(_incremental_started_us)
	_is_incremental_rebuild_active = false
	_incremental_generated = null
	_incremental_coverage_image = null
	_incremental_random = null


func _load_coverage_image() -> Image:
	if coverage_image_override != null:
		return coverage_image_override
	if coverage_texture == null:
		return null

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


func _elapsed_ms(started_us: int) -> float:
	return float(Time.get_ticks_usec() - started_us) / 1000.0
