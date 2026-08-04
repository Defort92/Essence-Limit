## Отдельный Sprite3D-слой экипировки, синхронизированный с DirectionalSprite3D персонажа.
## Использует тот же сектор, индекс кадра и зеркалирование, но загружает собственные PNG.
extends Sprite3D
class_name DirectionalEquipmentLayer3D


@export var source_path: NodePath

var source_sprite: DirectionalSprite3D = null
var _frames_dir: String = ""
var _idle_frames: Array = []
var _movement_frames: Array = []

static var _shared_frames_cache: Dictionary = {}


func _ready() -> void:
	if source_sprite == null and not source_path.is_empty():
		source_sprite = get_node_or_null(source_path) as DirectionalSprite3D
	visible = false
	set_process(source_sprite != null)


## Переключает визуал на каталог надетого предмета. Пустой путь скрывает слой.
func set_frames_dir(frames_dir: String) -> void:
	if frames_dir == _frames_dir:
		_sync_frame()
		return
	_frames_dir = frames_dir
	_idle_frames.clear()
	_movement_frames.clear()
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
			idle_by_source[source_sector] = _load_series(direction_dir, "idle")
			movement_by_source[source_sector] = _load_series(direction_dir, "run")
		_idle_frames[sector] = idle_by_source[source_sector]
		_movement_frames[sector] = movement_by_source[source_sector]

	_shared_frames_cache[_frames_dir] = {
		"idle": _idle_frames,
		"movement": _movement_frames,
	}


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
	var series: Array[Texture2D] = (
		_movement_frames[sector]
		if source_sprite.is_moving_animation()
		else _idle_frames[sector]
	)
	if series.is_empty():
		visible = false
		return
	var frame_index := source_sprite.get_current_animation_frame() % series.size()
	texture = series[frame_index]
	flip_h = source_sprite.flip_h
	visible = true


func get_animation_frame_count(sector: int, moving: bool) -> int:
	if sector < 0 or sector >= 8 or _idle_frames.is_empty():
		return 0
	var series: Array[Texture2D] = (
		_movement_frames[sector] if moving else _idle_frames[sector]
	)
	return series.size()
