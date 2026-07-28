extends SceneTree

const CITY_SCENE := "res://scenes/world/human_city.tscn"
const GRASS_SCENE := "res://scenes/main.tscn"
const STREAMING_SETTLE_FRAMES := 260


func _initialize() -> void:
	call_deferred("_run_benchmark")


func _run_benchmark() -> void:
	await _change_scene(CITY_SCENE)
	await _change_scene(GRASS_SCENE)

	for frame in STREAMING_SETTLE_FRAMES:
		await process_frame
	var first_grid := current_scene.get_node_or_null("VegetationChunks") as GrassChunkGrid
	if first_grid != null:
		print("[GrassTransitionBenchmark] settled first pass: %s" % first_grid.get_streaming_stats())

	await _change_scene(CITY_SCENE)
	await _change_scene(GRASS_SCENE)
	var second_grid := current_scene.get_node_or_null("VegetationChunks") as GrassChunkGrid
	if second_grid != null:
		print("[GrassTransitionBenchmark] second pass start: %s" % second_grid.get_streaming_stats())
	quit()


func _change_scene(scene_path: String) -> void:
	var scene_manager := root.get_node_or_null("SceneManager")
	if scene_manager == null:
		push_error("SceneManager autoload is unavailable.")
		quit(1)
		return
	scene_manager.call("go_to", scene_path)
	await scene_changed
	for frame in 4:
		await process_frame
