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
@export_range(0.0, 160.0, 1.0) var density_per_square_meter := 38.0
@export_range(100, 60000, 100) var maximum_instances_per_chunk := 35000
@export var random_seed := 8042
@export var interactor_group: StringName = &"party"


func _ready() -> void:
	_build_grid()


func _build_grid() -> void:
	if blade_mesh == null:
		push_warning("GrassChunkGrid requires a blade mesh.")
		return
	if chunk_size.x <= 0.0 or chunk_size.y <= 0.0:
		push_warning("GrassChunkGrid requires a positive chunk size.")
		return

	var columns := maxi(1, ceili(map_size.x / chunk_size.x))
	var rows := maxi(1, ceili(map_size.y / chunk_size.y))
	var world_origin := -map_size * 0.5

	for row in rows:
		for column in columns:
			var chunk := GrassMultiMeshChunk.new()
			chunk.name = "Grass_%02d_%02d" % [column, row]
			chunk.position = Vector3(
				world_origin.x + (float(column) + 0.5) * chunk_size.x,
				0.02,
				world_origin.y + (float(row) + 0.5) * chunk_size.y
			)
			chunk.blade_mesh = blade_mesh
			chunk.material_override = grass_material
			chunk.area_size = chunk_size
			chunk.density_per_square_meter = density_per_square_meter
			chunk.maximum_instances = maximum_instances_per_chunk
			chunk.random_seed = random_seed + row * columns + column
			chunk.coverage_texture = coverage_texture
			chunk.coverage_world_origin = world_origin
			chunk.coverage_world_size = map_size
			chunk.path_clear_half_width = 0.0
			chunk.exclusion_rect = Rect2()
			chunk.interactor_group = interactor_group
			add_child(chunk)
