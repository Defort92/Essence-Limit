## Отдельный Sprite3D-слой экипировки, синхронизированный с DirectionalSprite3D персонажа.
## Использует тот же сектор, индекс кадра и зеркалирование, но загружает собственные PNG.
extends Sprite3D
class_name DirectionalEquipmentLayer3D


@export var source_path: NodePath

var source_sprite: DirectionalSprite3D = null
var _frames_dir: String = ""
var _idle_frames: Array = []
var _movement_frames: Array = []
var _named_clip_frames: Dictionary = {}

static var _shared_frames_cache: Dictionary = {}


func _ready() -> void:
	if source_sprite == null and not source_path.is_empty():
		source_sprite = get_node_or_null(source_path) as DirectionalSprite3D
	if source_sprite != null:
		# The body advances the shared clock first; every equipment layer samples it after.
		process_priority = source_sprite.process_priority + 1
	visible = false
	set_process(source_sprite != null)


## Переключает визуал на каталог надетого предмета. Пустой путь скрывает слой.
func set_frames_dir(frames_dir: String) -> void:
	if frames_dir == _frames_dir:
		_sync_frame()
		return
	_frames_dir = frames_dir
	# Cached arrays are shared between equipment layers. Replacing our references
	# keeps the cache intact when a character switches to another weapon; clear()
	# here used to empty the cached sword clips permanently.
	_idle_frames = []
	_movement_frames = []
	_named_clip_frames.clear()
	texture = null
	visible = false
	if _frames_dir.is_empty():
		return
	_load_frames()
	_sync_frame()


func _load_frames() -> void:
	var cached: Variant = _shared_frames_cache.get(_frames_dir)
	if cached is Dictionary:
		_idle_frames = cached["idle"]
		_movement_frames = cached["movement"]
		return

	_idle_frames.resize(8)
	_movement_frames.resize(8)
	var idle_by_source: Dictionary = {}
	var movement_by_source: Dictionary = {}
	for sector in 8:
		var source_sector := sector
		var mirror_source := DirectionalSpriteConstants.MIRROR_SOURCE_SECTORS[sector]
		if mirror_source >= 0:
			source_sector = mirror_source
		if not idle_by_source.has(source_sector):
			var direction_dir := _frames_dir.path_join(
				DirectionalSpriteConstants.DIR_FOLDERS[source_sector]
			)
			var idle_series := _load_series(
				direction_dir.path_join("idle").path_join("default"),
				"frame"
			)
			if idle_series.is_empty():
				idle_series = _load_series(direction_dir, "idle")
			var movement_series := _load_series(
				direction_dir.path_join("run").path_join("default"),
				"frame"
			)
			if movement_series.is_empty():
				movement_series = _load_series(direction_dir, "run")
			idle_by_source[source_sector] = idle_series
			movement_by_source[source_sector] = movement_series
		_idle_frames[sector] = idle_by_source[source_sector]
		_movement_frames[sector] = movement_by_source[source_sector]

	_shared_frames_cache[_frames_dir] = {
		"idle": _idle_frames,
		"movement": _movement_frames,
	}


func _clip_key(state: StringName, variant: StringName) -> String:
	return "%s/%s" % [state, variant]


func _get_clip_frames(state: StringName, variant: StringName) -> Array:
	if state == &"idle" and variant == &"default":
		return _idle_frames
	if state == &"run" and variant == &"default":
		return _movement_frames
	var key := _clip_key(state, variant)
	if not _named_clip_frames.has(key):
		_named_clip_frames[key] = _load_directional_clip(state, variant)
	return _named_clip_frames[key]


func _load_directional_clip(state: StringName, variant: StringName) -> Array:
	var cache_key := "%s|clip=%s/%s" % [_frames_dir, state, variant]
	var cached: Variant = _shared_frames_cache.get(cache_key)
	if cached is Array:
		return cached
	var clip_frames: Array = []
	clip_frames.resize(8)
	var loaded_by_source: Dictionary = {}
	for sector in 8:
		var source_sector := sector
		var mirror_source := DirectionalSpriteConstants.MIRROR_SOURCE_SECTORS[sector]
		if mirror_source >= 0:
			source_sector = mirror_source
		if not loaded_by_source.has(source_sector):
			var clip_dir := _frames_dir.path_join(
				DirectionalSpriteConstants.DIR_FOLDERS[source_sector]
			).path_join(String(state)).path_join(String(variant))
			loaded_by_source[source_sector] = _load_series(clip_dir, "frame")
		clip_frames[sector] = loaded_by_source[source_sector]
	_shared_frames_cache[cache_key] = clip_frames
	return clip_frames


func _load_series(directory: String, prefix: String) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var index := 1
	while true:
		var path := "%s/%s_%02d.png" % [directory, prefix, index]
		if not ResourceLoader.exists(path):
			break
		var frame := load(path) as Texture2D
		if frame == null:
			break
		frames.append(frame)
		index += 1
	return frames


func _process(_delta: float) -> void:
	_sync_frame()


func _sync_frame() -> void:
	if source_sprite == null or _frames_dir.is_empty():
		visible = false
		return
	var sector := source_sprite.get_current_sector()
	if sector < 0 or sector >= 8:
		visible = false
		return
	var state := source_sprite.get_current_animation_state()
	var variant := source_sprite.get_current_animation_variant()
	var clip_frames := _get_clip_frames(state, variant)
	var series: Array[Texture2D] = []
	if not clip_frames.is_empty():
		series = clip_frames[sector]
	if series.is_empty() and variant != &"default":
		clip_frames = _get_clip_frames(state, &"default")
		if not clip_frames.is_empty():
			series = clip_frames[sector]
	if series.is_empty():
		visible = false
		return
	var frame_index := mini(
		int(source_sprite.get_current_animation_phase() * float(series.size())),
		series.size() - 1
	)
	texture = series[frame_index]
	flip_h = source_sprite.flip_h
	visible = true


func get_animation_frame_count(sector: int, moving: bool) -> int:
	return get_animation_clip_frame_count(
		sector,
		&"run" if moving else &"idle",
		&"default"
	)


func get_animation_clip_frame_count(
	sector: int,
	state: StringName,
	variant: StringName = &"default"
) -> int:
	if sector < 0 or sector >= 8:
		return 0
	var clip_frames := _get_clip_frames(state, variant)
	if clip_frames.is_empty():
		return 0
	var series: Array[Texture2D] = clip_frames[sector]
	return series.size()
