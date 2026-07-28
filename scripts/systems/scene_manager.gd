## Управляет сменой сцен. Единственное место в проекте, где вызывается change_scene_to_file.
## Является Autoload-синглтоном; регистрировать как "SceneManager" в Project Settings.
extends Node

signal scene_changed(scene_path: String)

const BENCHMARK_PREFIX := "[SceneBenchmark]"
const BENCHMARK_WARNING_MS := 250.0

var _transition_id := 0
var _transition_in_progress := false
var _benchmark: Dictionary = {}

## Меняет сцену на произвольный путь.
func go_to(scene_path: String) -> void:
	if _transition_in_progress:
		push_warning("%s Scene transition is already in progress; ignored: %s" % [
			BENCHMARK_PREFIX,
			scene_path,
		])
		return

	if not OS.is_debug_build():
		get_tree().change_scene_to_file(scene_path)
		scene_changed.emit(scene_path)
		return

	_transition_in_progress = true
	_transition_id += 1
	var transition_id := _transition_id
	var source_path := _current_scene_path()
	var started_us := Time.get_ticks_usec()
	var memory_before := OS.get_static_memory_usage()
	var was_cached := ResourceLoader.has_cached(scene_path)

	print("\n%s #%d START %s -> %s" % [
		BENCHMARK_PREFIX,
		transition_id,
		source_path,
		scene_path,
	])

	var dependency_scan_started_us := Time.get_ticks_usec()
	var dependencies := ResourceLoader.get_dependencies(scene_path)
	var dependency_scan_ms := _elapsed_ms(dependency_scan_started_us)
	print("%s #%d dependencies: %.2f ms, direct=%d" % [
		BENCHMARK_PREFIX,
		transition_id,
		dependency_scan_ms,
		dependencies.size(),
	])
	for dependency in dependencies:
		print("%s #%d   dependency: %s" % [BENCHMARK_PREFIX, transition_id, dependency])

	var load_started_us := Time.get_ticks_usec()
	var packed_scene := ResourceLoader.load(scene_path, "PackedScene") as PackedScene
	var resource_load_ms := _elapsed_ms(load_started_us)
	if packed_scene == null:
		_transition_in_progress = false
		_benchmark.clear()
		push_error("%s #%d failed to load %s after %.2f ms" % [
			BENCHMARK_PREFIX,
			transition_id,
			scene_path,
			resource_load_ms,
		])
		return

	_benchmark = {
		"id": transition_id,
		"source_path": source_path,
		"target_path": scene_path,
		"started_us": started_us,
		"memory_before": memory_before,
		"was_cached": was_cached,
		"dependency_scan_ms": dependency_scan_ms,
		"dependency_count": dependencies.size(),
		"resource_load_ms": resource_load_ms,
	}
	print("%s #%d resource load: %.2f ms (cached before=%s)" % [
		BENCHMARK_PREFIX,
		transition_id,
		resource_load_ms,
		str(was_cached),
	])

	# Subscribe before requesting the change so even a very fast transition is measured.
	_watch_scene_change(transition_id)
	var change_started_us := Time.get_ticks_usec()
	var error := get_tree().change_scene_to_packed(packed_scene)
	var change_request_ms := _elapsed_ms(change_started_us)
	_benchmark["change_request_ms"] = change_request_ms
	print("%s #%d instantiate/change request: %.2f ms" % [
		BENCHMARK_PREFIX,
		transition_id,
		change_request_ms,
	])

	if error != OK:
		_transition_in_progress = false
		_benchmark.clear()
		push_error("%s #%d change_scene_to_packed failed with error %d" % [
			BENCHMARK_PREFIX,
			transition_id,
			error,
		])
		return

	scene_changed.emit(scene_path)


func _watch_scene_change(transition_id: int) -> void:
	await get_tree().scene_changed
	if transition_id != _transition_id or _benchmark.is_empty():
		return

	var ready_ms := _elapsed_ms(int(_benchmark["started_us"]))
	_benchmark["scene_ready_ms"] = ready_ms
	print("%s #%d target scene ready: %.2f ms total" % [
		BENCHMARK_PREFIX,
		transition_id,
		ready_ms,
	])
	_print_scene_tree_summary(transition_id)
	_print_grass_summary(transition_id)

	var first_frame_started_us := Time.get_ticks_usec()
	await get_tree().process_frame
	var first_frame_ms := _elapsed_ms(first_frame_started_us)
	var first_process_total_ms := _elapsed_ms(int(_benchmark["started_us"]))
	_benchmark["first_frame_ms"] = first_frame_ms
	_benchmark["first_process_total_ms"] = first_process_total_ms
	print("%s #%d first process frame: %.2f ms (transition total %.2f ms)" % [
		BENCHMARK_PREFIX,
		transition_id,
		first_frame_ms,
		first_process_total_ms,
	])

	var second_frame_started_us := Time.get_ticks_usec()
	await get_tree().process_frame
	var second_frame_ms := _elapsed_ms(second_frame_started_us)
	_benchmark["second_frame_ms"] = second_frame_ms
	_print_benchmark_result(transition_id, second_frame_ms)
	_transition_in_progress = false


func _print_scene_tree_summary(transition_id: int) -> void:
	var current_scene := get_tree().current_scene
	var node_count := _count_nodes(current_scene)
	var memory_after := OS.get_static_memory_usage()
	var memory_delta_mb := float(memory_after - int(_benchmark["memory_before"])) / (1024.0 * 1024.0)
	_benchmark["node_count"] = node_count
	_benchmark["memory_after"] = memory_after
	print("%s #%d scene tree: nodes=%d, static memory delta=%.2f MiB" % [
		BENCHMARK_PREFIX,
		transition_id,
		node_count,
		memory_delta_mb,
	])


func _print_grass_summary(transition_id: int) -> void:
	var grass_nodes := get_tree().get_nodes_in_group("grass_benchmark")
	if grass_nodes.is_empty():
		print("%s #%d grass: no runtime-generated chunks" % [BENCHMARK_PREFIX, transition_id])
		return

	var total_ms := 0.0
	var total_candidates := 0
	var total_visible := 0
	var measured_chunks := 0
	var slowest_chunk_ms := 0.0
	var slowest_chunk_path := ""
	var print_individual_chunks := grass_nodes.size() <= 16
	for grass_node in grass_nodes:
		if not grass_node.has_method("get_rebuild_benchmark"):
			continue
		var result: Dictionary = grass_node.get_rebuild_benchmark()
		var chunk_ms := float(result.get("total_ms", 0.0))
		total_ms += chunk_ms
		total_candidates += int(result.get("candidate_count", 0))
		total_visible += int(result.get("visible_count", 0))
		measured_chunks += 1
		if chunk_ms > slowest_chunk_ms:
			slowest_chunk_ms = chunk_ms
			slowest_chunk_path = str(grass_node.get_path())
		if not print_individual_chunks:
			continue
		print((
			"%s #%d grass %s [%s]: total=%.2f ms "
			+ "(mask=%.2f, allocate=%.2f, populate=%.2f, publish=%.2f), "
			+ "candidates=%d, visible=%d"
		) % [
			BENCHMARK_PREFIX,
			transition_id,
			str(grass_node.get_path()),
			str(result.get("action", "unknown")),
			float(result.get("total_ms", 0.0)),
				float(result.get("coverage_image_ms", 0.0)),
				float(result.get("allocation_ms", 0.0)),
				float(result.get("population_ms", 0.0)),
				float(result.get("publish_ms", 0.0)),
				int(result.get("candidate_count", 0)),
				int(result.get("visible_count", 0)),
			]
		)

	if not print_individual_chunks and measured_chunks > 0:
		print("%s #%d grass chunk details: average=%.2f ms, slowest=%.2f ms (%s)" % [
			BENCHMARK_PREFIX,
			transition_id,
			total_ms / float(measured_chunks),
			slowest_chunk_ms,
			slowest_chunk_path,
		])

	_benchmark["grass_total_ms"] = total_ms
	_benchmark["grass_candidate_count"] = total_candidates
	_benchmark["grass_visible_count"] = total_visible
	print("%s #%d grass total: %.2f ms, candidates=%d, visible=%d, chunks=%d" % [
		BENCHMARK_PREFIX,
		transition_id,
		total_ms,
		total_candidates,
		total_visible,
		measured_chunks,
	])


func _print_benchmark_result(transition_id: int, second_frame_ms: float) -> void:
	var total_ms := float(_benchmark.get("first_process_total_ms", 0.0))
	var verdict := "OK"
	if total_ms > 1000.0:
		verdict = "VERY SLOW"
	elif total_ms > BENCHMARK_WARNING_MS:
		verdict = "SLOW"
	elif total_ms > 100.0:
		verdict = "NOTICEABLE"

	print(("%s #%d RESULT %s: load=%.2f ms, instantiate/ready=%.2f ms, "
		+ "first_frame=%.2f ms, second_frame=%.2f ms, total_to_first_process=%.2f ms"
	) % [
			BENCHMARK_PREFIX,
			transition_id,
			verdict,
			float(_benchmark.get("resource_load_ms", 0.0)),
			float(_benchmark.get("scene_ready_ms", 0.0))
				- float(_benchmark.get("resource_load_ms", 0.0))
				- float(_benchmark.get("dependency_scan_ms", 0.0)),
			float(_benchmark.get("first_frame_ms", 0.0)),
			second_frame_ms,
			total_ms,
		]
	)
	if total_ms > BENCHMARK_WARNING_MS:
		push_warning("%s #%d transition exceeded %.0f ms; inspect the phases above." % [
			BENCHMARK_PREFIX,
			transition_id,
			BENCHMARK_WARNING_MS,
		])
	print("%s #%d END\n" % [BENCHMARK_PREFIX, transition_id])


func _current_scene_path() -> String:
	var current_scene := get_tree().current_scene
	if current_scene == null or current_scene.scene_file_path.is_empty():
		return "<no current scene>"
	return current_scene.scene_file_path


func _count_nodes(root: Node) -> int:
	if root == null:
		return 0
	var result := 1
	for child in root.get_children():
		result += _count_nodes(child)
	return result


func _elapsed_ms(started_us: int) -> float:
	return float(Time.get_ticks_usec() - started_us) / 1000.0

## Переход в главное меню.
func go_to_main_menu() -> void:
	go_to("res://scenes/ui/main_menu.tscn")

## Переход на экран создания персонажа (выбор расы и имени).
func go_to_character_creation() -> void:
	go_to("res://scenes/ui/character_creation.tscn")

## Переход в человеческий город (основной хаб).
func go_to_city() -> void:
	go_to("res://scenes/world/human_city.tscn")

## Переход в стартовую локацию расы после создания персонажа.
func go_to_race_start(race: GameManager.Race) -> void:
	match race:
		GameManager.Race.HUMAN:     go_to("res://scenes/world/human_city.tscn")
		GameManager.Race.BARBARIAN: go_to("res://scenes/world/barbarian_camp.tscn")
		GameManager.Race.ELF:       go_to("res://scenes/world/elf_village.tscn")
		GameManager.Race.DEMON:     go_to("res://scenes/world/demon_ruins.tscn")
		GameManager.Race.ANGEL:     go_to("res://scenes/world/angel_citadel.tscn")

## Переход на этаж подземелья. floor_num: 1–15.
func go_to_dungeon_floor(floor_num: int) -> void:
	assert(floor_num >= 1 and floor_num <= DungeonPortalConstants.MAX_FLOORS)
	go_to("res://scenes/dungeon/floor_%02d.tscn" % floor_num)

## Экран смерти (показывает UI, затем возвращает в город).
func go_to_death_screen() -> void:
	go_to("res://scenes/ui/death_screen.tscn")
