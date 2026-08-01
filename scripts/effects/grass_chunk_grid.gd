extends Node3D
class_name GrassChunkGrid

## Runtime grid for large test locations. Chunks are created without serialized
## MultiMesh buffers, so only the grass that is actually generated occupies the
## scene file.

@export var blade_mesh: Mesh
@export var grass_material: Material
@export var coverage_texture: Texture2D
@export var map_size := Vector2(300.0, 300.0)
@export var chunk_size := Vector2(30.0, 30.0)
@export_range(0.0, 160.0, 1.0) var density_per_square_meter := 52.0
@export_range(100, 60000, 100) var maximum_instances_per_chunk := 50000
## Matches the beginning of the terrain shader's green blend, so the visible
## green border is planted instead of leaving a bare ring around grass patches.
@export_range(0.0, 1.0, 0.01) var coverage_threshold := 0.10
@export var random_seed := 8042
@export var interactor_group: StringName = &"party"
## Millions of overlapping grass cards create severe self-shadowing. Keep
## blade shadows disabled by default and reserve real shadows for larger plants.
@export var shadow_casting_setting: GeometryInstance3D.ShadowCastingSetting = \
	GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
@export_group("Streaming")
@export var streaming_enabled := true
@export var streaming_focus_group: StringName = &"player"
@export_range(0, 4, 1) var near_radius_chunks := 1
@export_range(1, 6, 1) var medium_radius_chunks := 2
@export_range(0.05, 1.0, 0.05) var medium_density_ratio := 0.45
@export_range(100, 10000, 100) var generation_candidates_per_frame := 3500
@export_range(0.05, 2.0, 0.05) var fade_duration_seconds := 0.25
@export_range(0.05, 1.0, 0.05) var focus_check_interval_seconds := 0.2
@export_range(0, 32, 1) var cached_chunk_limit := 8

enum GrassLod {
	NEAR,
	MEDIUM,
}

var _columns := 0
var _rows := 0
var _world_origin := Vector2.ZERO
var _focus_check_accumulator := 0.0
var _focus_coordinate := Vector2i(-1000000, -1000000)
var _active_chunks: Dictionary = {}
var _active_lods: Dictionary = {}
var _desired_lods: Dictionary = {}
var _pending_coordinates: Array[Vector2i] = []
var _building_chunk: GrassMultiMeshChunk
var _building_coordinate := Vector2i.ZERO
var _multimesh_cache: Dictionary = {}
var _cache_order: Array[String] = []
var _maximum_generation_step_ms := 0.0
var _completed_generation_count := 0
var _coverage_image: Image
var _setup_ms := 0.0
var _coverage_image_ms := 0.0


func _ready() -> void:
	var setup_started_us := Time.get_ticks_usec()
	if not _validate_configuration():
		return
	add_to_group("grass_streaming_benchmark")

	_columns = maxi(1, ceili(map_size.x / chunk_size.x))
	_rows = maxi(1, ceili(map_size.y / chunk_size.y))
	_world_origin = -map_size * 0.5
	if coverage_texture != null:
		var coverage_started_us := Time.get_ticks_usec()
		_coverage_image = coverage_texture.get_image()
		_coverage_image_ms = float(Time.get_ticks_usec() - coverage_started_us) / 1000.0
	_setup_ms = float(Time.get_ticks_usec() - setup_started_us) / 1000.0
	if OS.is_debug_build():
		print(
			"[GrassStreaming] setup=%.2f ms coverage_image=%.2f ms"
			% [_setup_ms, _coverage_image_ms]
		)
	if streaming_enabled:
		set_process(true)
		call_deferred("_refresh_streaming", true)
	else:
		_build_full_grid()


func _process(delta: float) -> void:
	if not streaming_enabled:
		return

	var step_started_us := Time.get_ticks_usec()
	var completed_this_frame := false
	if _building_chunk != null and is_instance_valid(_building_chunk):
		if _building_chunk.continue_incremental_rebuild(generation_candidates_per_frame):
			_completed_generation_count += 1
			_fade_in(_building_chunk)
			_building_chunk = null
			completed_this_frame = true

	if _building_chunk == null and not completed_this_frame:
		_start_next_pending_chunk()

	_focus_check_accumulator += delta
	if _focus_check_accumulator >= focus_check_interval_seconds:
		_focus_check_accumulator = fmod(
			_focus_check_accumulator,
			focus_check_interval_seconds
		)
		_refresh_streaming()

	var step_ms := float(Time.get_ticks_usec() - step_started_us) / 1000.0
	_maximum_generation_step_ms = maxf(_maximum_generation_step_ms, step_ms)


func get_streaming_stats() -> Dictionary:
	var visible_instances := 0
	for chunk_variant in _active_chunks.values():
		var chunk := chunk_variant as GrassMultiMeshChunk
		if chunk != null:
			visible_instances += chunk.get_visible_grass_count()
	return {
		"active_chunks": _active_chunks.size(),
		"pending_chunks": _pending_coordinates.size(),
		"cached_chunks": _multimesh_cache.size(),
		"visible_instances": visible_instances,
		"completed_generations": _completed_generation_count,
		"maximum_generation_step_ms": _maximum_generation_step_ms,
		"focus_coordinate": _focus_coordinate,
		"setup_ms": _setup_ms,
		"coverage_image_ms": _coverage_image_ms,
	}


## Forces an immediate focus check. Useful after teleports and in automated
## streaming checks; ordinary movement is sampled on the configured interval.
func refresh_streaming_now() -> void:
	_refresh_streaming(true)


func _validate_configuration() -> bool:
	if blade_mesh == null:
		push_warning("GrassChunkGrid requires a blade mesh.")
		return false
	if chunk_size.x <= 0.0 or chunk_size.y <= 0.0:
		push_warning("GrassChunkGrid requires a positive chunk size.")
		return false
	if medium_radius_chunks < near_radius_chunks:
		push_warning("GrassChunkGrid medium radius cannot be smaller than near radius.")
		return false
	return true


func _build_full_grid() -> void:
	for row in _rows:
		for column in _columns:
			var coordinate := Vector2i(column, row)
			var chunk := _create_chunk(coordinate, GrassLod.NEAR, false)
			add_child(chunk)


func _refresh_streaming(force := false) -> void:
	var focus_position := _find_focus_position()
	var new_focus_coordinate := _coordinate_from_world(focus_position)
	if not force and new_focus_coordinate == _focus_coordinate:
		return
	_focus_coordinate = new_focus_coordinate

	var new_desired_lods: Dictionary = {}
	for offset_y in range(-medium_radius_chunks, medium_radius_chunks + 1):
		for offset_x in range(-medium_radius_chunks, medium_radius_chunks + 1):
			var coordinate := _focus_coordinate + Vector2i(offset_x, offset_y)
			if not _is_coordinate_inside_map(coordinate):
				continue
			var distance := maxi(absi(offset_x), absi(offset_y))
			var lod := GrassLod.NEAR if distance <= near_radius_chunks else GrassLod.MEDIUM
			new_desired_lods[coordinate] = lod
	_desired_lods = new_desired_lods

	for coordinate_variant in _active_chunks.keys():
		var coordinate: Vector2i = coordinate_variant
		var desired_lod: Variant = _desired_lods.get(coordinate)
		if desired_lod == null or int(desired_lod) != int(_active_lods[coordinate]):
			_remove_active_chunk(coordinate)

	_pending_coordinates.clear()
	for coordinate_variant in _desired_lods.keys():
		var coordinate: Vector2i = coordinate_variant
		if not _active_chunks.has(coordinate):
			_pending_coordinates.append(coordinate)
	_pending_coordinates.sort_custom(_sort_pending_coordinates)

	if OS.is_debug_build():
		print(
			"[GrassStreaming] focus=%s desired=%d active=%d pending=%d cached=%d"
			% [
				_focus_coordinate,
				_desired_lods.size(),
				_active_chunks.size(),
				_pending_coordinates.size(),
				_multimesh_cache.size(),
			]
		)


func _sort_pending_coordinates(left: Vector2i, right: Vector2i) -> bool:
	var left_distance := _chunk_distance(left, _focus_coordinate)
	var right_distance := _chunk_distance(right, _focus_coordinate)
	if left_distance == right_distance:
		if left.y == right.y:
			return left.x < right.x
		return left.y < right.y
	return left_distance < right_distance


func _start_next_pending_chunk() -> void:
	while not _pending_coordinates.is_empty():
		var coordinate: Vector2i = _pending_coordinates.pop_front()
		if _active_chunks.has(coordinate) or not _desired_lods.has(coordinate):
			continue

		var lod := int(_desired_lods[coordinate])
		var cache_key := _cache_key(coordinate, lod)
		var cached_multimesh := _take_cached_multimesh(cache_key)
		var chunk := _create_chunk(coordinate, lod, true)
		if cached_multimesh != null:
			chunk.multimesh = cached_multimesh
		add_child(chunk)
		_active_chunks[coordinate] = chunk
		_active_lods[coordinate] = lod

		if cached_multimesh != null:
			_fade_in(chunk)
			continue

		_building_chunk = chunk
		_building_coordinate = coordinate
		if chunk.begin_incremental_rebuild():
			_completed_generation_count += 1
			_fade_in(chunk)
			_building_chunk = null
		return


func _create_chunk(
	coordinate: Vector2i,
	lod: int,
	manual_build: bool
) -> GrassMultiMeshChunk:
	var chunk := GrassMultiMeshChunk.new()
	chunk.name = "Grass_%02d_%02d_%s" % [
		coordinate.x,
		coordinate.y,
		"Near" if lod == GrassLod.NEAR else "Medium",
	]
	chunk.position = Vector3(
		_world_origin.x + (float(coordinate.x) + 0.5) * chunk_size.x,
		0.02,
		_world_origin.y + (float(coordinate.y) + 0.5) * chunk_size.y
	)
	chunk.blade_mesh = blade_mesh
	chunk.material_override = grass_material
	chunk.cast_shadow = shadow_casting_setting
	chunk.area_size = chunk_size
	chunk.density_per_square_meter = (
		density_per_square_meter
		if lod == GrassLod.NEAR
		else density_per_square_meter * medium_density_ratio
	)
	chunk.maximum_instances = maximum_instances_per_chunk
	chunk.random_seed = random_seed + coordinate.y * _columns + coordinate.x
	chunk.coverage_texture = coverage_texture
	chunk.coverage_image_override = _coverage_image
	chunk.coverage_world_origin = _world_origin
	chunk.coverage_world_size = map_size
	chunk.coverage_threshold = coverage_threshold
	chunk.path_clear_half_width = 0.0
	chunk.exclusion_rect = Rect2()
	chunk.interactor_group = interactor_group if lod == GrassLod.NEAR else &""
	chunk.transparency = 1.0 if manual_build else 0.0
	if manual_build:
		chunk.build_mode = GrassMultiMeshChunk.BuildMode.USE_EXISTING
	return chunk


func _remove_active_chunk(coordinate: Vector2i) -> void:
	var chunk := _active_chunks.get(coordinate) as GrassMultiMeshChunk
	if chunk == null:
		_active_chunks.erase(coordinate)
		_active_lods.erase(coordinate)
		return

	if chunk == _building_chunk:
		_building_chunk = null
	elif chunk.multimesh != null:
		_store_cached_multimesh(
			_cache_key(coordinate, int(_active_lods[coordinate])),
			chunk.multimesh
		)
	_active_chunks.erase(coordinate)
	_active_lods.erase(coordinate)

	var tween := create_tween()
	tween.tween_property(chunk, "transparency", 1.0, fade_duration_seconds)
	tween.tween_callback(chunk.queue_free)


func _fade_in(chunk: GrassMultiMeshChunk) -> void:
	if not is_instance_valid(chunk):
		return
	var tween := create_tween()
	tween.tween_property(chunk, "transparency", 0.0, fade_duration_seconds)


func _store_cached_multimesh(key: String, cached_multimesh: MultiMesh) -> void:
	if cached_chunk_limit <= 0:
		return
	_multimesh_cache[key] = cached_multimesh
	_cache_order.erase(key)
	_cache_order.append(key)
	while _cache_order.size() > cached_chunk_limit:
		var oldest_key: String = _cache_order.pop_front()
		_multimesh_cache.erase(oldest_key)


func _take_cached_multimesh(key: String) -> MultiMesh:
	var cached_multimesh := _multimesh_cache.get(key) as MultiMesh
	if cached_multimesh != null:
		_multimesh_cache.erase(key)
		_cache_order.erase(key)
	return cached_multimesh


func _cache_key(coordinate: Vector2i, lod: int) -> String:
	return "%d:%d:%d" % [coordinate.x, coordinate.y, int(lod)]


func _find_focus_position() -> Vector3:
	var focus := get_tree().get_first_node_in_group(streaming_focus_group) as Node3D
	if focus == null:
		focus = get_tree().get_first_node_in_group(interactor_group) as Node3D
	if focus == null:
		return global_position
	return focus.global_position


func _coordinate_from_world(world_position: Vector3) -> Vector2i:
	var local_position := to_local(world_position)
	return Vector2i(
		clampi(floori((local_position.x - _world_origin.x) / chunk_size.x), 0, _columns - 1),
		clampi(floori((local_position.z - _world_origin.y) / chunk_size.y), 0, _rows - 1)
	)


func _is_coordinate_inside_map(coordinate: Vector2i) -> bool:
	return (
		coordinate.x >= 0
		and coordinate.x < _columns
		and coordinate.y >= 0
		and coordinate.y < _rows
	)


func _chunk_distance(left: Vector2i, right: Vector2i) -> int:
	return maxi(absi(left.x - right.x), absi(left.y - right.y))
