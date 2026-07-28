extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var focus := Node3D.new()
	focus.add_to_group("grass_streaming_test_focus")
	root.add_child(focus)

	var grid := GrassChunkGrid.new()
	grid.blade_mesh = QuadMesh.new()
	grid.map_size = Vector2(3.0, 1.0)
	grid.chunk_size = Vector2.ONE
	grid.density_per_square_meter = 1.0
	grid.maximum_instances_per_chunk = 100
	grid.streaming_focus_group = &"grass_streaming_test_focus"
	grid.near_radius_chunks = 1
	grid.medium_radius_chunks = 1
	grid.focus_check_interval_seconds = 0.05
	root.add_child(grid)
	for frame in 20:
		var initial_stats := grid.get_streaming_stats()
		if (
			initial_stats["active_chunks"] == 3
			and initial_stats["pending_chunks"] == 0
			and initial_stats["completed_generations"] == 3
		):
			break
		await process_frame

	var stats := grid.get_streaming_stats()
	if stats["active_chunks"] != 3 or stats["pending_chunks"] != 0:
		push_error("Initial 3x1 streaming area did not settle: %s" % stats)
		quit(1)
		return

	for child in grid.get_children():
		var chunk := child as GrassMultiMeshChunk
		if chunk == null:
			continue
		if chunk.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			push_error("Runtime grass chunk unexpectedly casts shadows.")
			quit(1)
			return
		if chunk.multimesh == null or chunk.get_visible_grass_count() != 1:
			push_error("Incremental grass generation did not finish as expected.")
			quit(1)
			return

	focus.position.x = 1.1
	grid.refresh_streaming_now()
	await process_frame
	stats = grid.get_streaming_stats()
	if stats["active_chunks"] != 2 or stats["cached_chunks"] != 1:
		push_error("Chunk unload/cache state is invalid: %s" % stats)
		quit(1)
		return

	focus.position.x = 0.0
	grid.refresh_streaming_now()
	await process_frame
	stats = grid.get_streaming_stats()
	if stats["active_chunks"] != 3 or stats["cached_chunks"] != 0:
		push_error("Cached chunk was not restored: %s" % stats)
		quit(1)
		return

	print(
		"[GrassChunkGridTest] PASS: shadows off, incremental build, "
		+ "streaming unload and cache restore valid."
	)
	quit()
