extends SceneTree

const TARGET_SCENE := "res://scenes/main.tscn"
const WARMUP_SCENE := "res://scenes/world/human_city.tscn"


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var mode := "baseline"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		mode = args[0]
	if mode.begins_with("warm_city_"):
		await _warm_city()
		mode = mode.trim_prefix("warm_city_")

	var load_started := Time.get_ticks_usec()
	var packed := load(TARGET_SCENE) as PackedScene
	var load_ms := _elapsed_ms(load_started)
	if packed == null:
		push_error("Could not load %s." % TARGET_SCENE)
		quit(1)
		return

	var instantiate_started := Time.get_ticks_usec()
	var scene := packed.instantiate()
	var instantiate_ms := _elapsed_ms(instantiate_started)
	_configure_mode(scene, mode)

	var ready_started := Time.get_ticks_usec()
	root.add_child(scene)
	var ready_ms := _elapsed_ms(ready_started)
	print(
		"[SceneStartupBreakdown] mode=%s load=%.2f ms instantiate=%.2f ms ready=%.2f ms total=%.2f ms"
		% [mode, load_ms, instantiate_ms, ready_ms, instantiate_ms + ready_ms]
	)
	quit()


func _warm_city() -> void:
	var packed := load(WARMUP_SCENE) as PackedScene
	if packed == null:
		return
	var city := packed.instantiate()
	root.add_child(city)
	await process_frame
	root.remove_child(city)
	city.free()


func _configure_mode(scene: Node, mode: String) -> void:
	match mode:
		"no_animation":
			for node in scene.find_children("*", "DirectionalSprite3D", true, false):
				(node as DirectionalSprite3D).frames_dir = ""
		"no_ui":
			_free_children(scene, ["HUD", "LootUI", "CharacterScreen", "StatesScreen", "PauseMenu"])
		"no_navigation":
			_free_children(scene, ["NavigationRegion3D"])
		"no_environment":
			_free_children(scene, ["ShaderGlobals", "DirectionalLight3D", "Floor", "VegetationChunks"])
		"minimal":
			_free_children(
				scene,
				[
					"ShaderGlobals", "DirectionalLight3D", "NavigationRegion3D", "Floor",
					"VegetationChunks", "PartyStarter", "PortalToCity", "HUD", "LootUI",
					"Goblin", "CharacterScreen", "StatesScreen", "PauseMenu", "MobSpawner",
					"HealingAura",
				]
			)
		_:
			pass


func _free_children(scene: Node, names: Array[String]) -> void:
	for child_name in names:
		var child := scene.get_node_or_null(child_name)
		if child != null:
			child.free()


func _elapsed_ms(started_us: int) -> float:
	return float(Time.get_ticks_usec() - started_us) / 1000.0
