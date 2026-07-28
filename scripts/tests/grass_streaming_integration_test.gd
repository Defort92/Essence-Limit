extends SceneTree

const TARGET_SCENE := "res://scenes/main.tscn"
const FRAMES_TO_SETTLE := 260
const READY_BUDGET_MS := 150.0
const STREAMING_FRAME_LIMIT_MS := 33.0


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var load_started_us := Time.get_ticks_usec()
	var packed_scene := load(TARGET_SCENE) as PackedScene
	var resource_load_ms := _elapsed_ms(load_started_us)
	if packed_scene == null:
		push_error("Could not load %s." % TARGET_SCENE)
		quit(1)
		return

	var memory_before := Performance.get_monitor(Performance.MEMORY_STATIC)
	var ready_started_us := Time.get_ticks_usec()
	var main := packed_scene.instantiate()
	root.add_child(main)
	var instantiate_ready_ms := _elapsed_ms(ready_started_us)

	var grid := main.get_node_or_null("VegetationChunks") as GrassChunkGrid
	if grid == null:
		push_error("Main scene does not contain a GrassChunkGrid.")
		quit(1)
		return

	var maximum_observed_frame_ms := 0.0
	for frame in FRAMES_TO_SETTLE:
		var frame_started_us := Time.get_ticks_usec()
		await process_frame
		maximum_observed_frame_ms = maxf(
			maximum_observed_frame_ms,
			_elapsed_ms(frame_started_us)
		)

	var memory_delta_mib := (
		Performance.get_monitor(Performance.MEMORY_STATIC) - memory_before
	) / (1024.0 * 1024.0)
	var stats := grid.get_streaming_stats()
	if DisplayServer.get_name() != "headless":
		_save_screenshot("res://.godot/grass_streaming_final.png")
	print(
		(
			"[GrassStreamingIntegration] load=%.2f ms, instantiate_ready=%.2f ms, "
			+ "max_frame=%.2f ms, memory_delta=%.2f MiB, stats=%s"
		)
		% [
			resource_load_ms,
			instantiate_ready_ms,
			maximum_observed_frame_ms,
			memory_delta_mib,
			stats,
		]
	)

	if instantiate_ready_ms > READY_BUDGET_MS:
		push_error(
			"Scene initialization exceeded %.2f ms: %.2f ms."
			% [READY_BUDGET_MS, instantiate_ready_ms]
		)
		quit(1)
		return
	if float(stats["maximum_generation_step_ms"]) > STREAMING_FRAME_LIMIT_MS:
		push_error(
			"Grass generation step exceeded %.2f ms: %.2f ms."
			% [STREAMING_FRAME_LIMIT_MS, stats["maximum_generation_step_ms"]]
		)
		quit(1)
		return
	if stats["active_chunks"] != 25 or stats["pending_chunks"] != 0:
		push_error("Streaming did not settle to the expected 5x5 area: %s" % stats)
		quit(1)
		return
	if stats["visible_instances"] >= 1000000:
		push_error("Streaming retained too many grass instances: %s" % stats)
		quit(1)
		return

	var player := main.get_node_or_null("Player") as Node3D
	if player == null:
		push_error("Main scene player is unavailable for the movement check.")
		quit(1)
		return
	player.global_position.x += grid.chunk_size.x + 5.0
	grid.refresh_streaming_now()
	for frame in FRAMES_TO_SETTLE:
		await process_frame
		if frame == 30 and DisplayServer.get_name() != "headless":
			_save_screenshot("res://.godot/grass_streaming_transition.png")
	var moved_stats := grid.get_streaming_stats()
	if moved_stats["active_chunks"] != 25 or moved_stats["pending_chunks"] != 0:
		push_error("Streaming did not settle after movement: %s" % moved_stats)
		quit(1)
		return
	if moved_stats["cached_chunks"] > grid.cached_chunk_limit:
		push_error("Grass cache exceeded its configured limit: %s" % moved_stats)
		quit(1)
		return
	if DisplayServer.get_name() != "headless":
		_save_screenshot("res://.godot/grass_streaming_moved.png")
	print("[GrassStreamingIntegration] moved stats=%s" % moved_stats)

	print("[GrassStreamingIntegration] PASS")
	quit()


func _save_screenshot(resource_path: String) -> void:
	var screenshot := root.get_viewport().get_texture().get_image()
	var screenshot_error := screenshot.save_png(
		ProjectSettings.globalize_path(resource_path)
	)
	if screenshot_error != OK:
		push_error("Could not save %s: %s" % [resource_path, screenshot_error])


func _elapsed_ms(started_us: int) -> float:
	return float(Time.get_ticks_usec() - started_us) / 1000.0
