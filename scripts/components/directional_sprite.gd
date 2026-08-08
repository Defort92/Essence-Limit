## 2.5D-спрайт персонажа с переключением по 8 ракурсам.
## Выбирает текстуру по направлению взгляда в мировых координатах X/Z.
## Камера фиксирована (без поворота по Y), поэтому мировое направление = экранному:
## +Z — к камере (front), -Z — от камеры (back), +X — вправо, -X — влево.
## Билборд FIXED_Y держит спрайт вертикально и развёрнутым к камере.
## Используется и игроком, и врагами — направление подаётся через face_direction().
##
## Поддерживает два режима:
## - Статичный: одна текстура на ракурс (tex_front и т.д.). Так работают враги.
## - Анимированный: если задан frames_dir, клипы читаются из каталогов
##   <direction>/<state>/<variant>/frame_NN.png. Состояние и вариант едины для тела
##   и всех слоёв экипировки.
extends Sprite3D
class_name DirectionalSprite3D

signal animation_changed(state: StringName, variant: StringName)
signal animation_cycle_finished(state: StringName, variant: StringName)

## 8 ракурсов. Соответствие секторам atan2(dir.x, dir.z), шаг 45°:
## 0=front(к камере) 1=front-right 2=right 3=rear-right 4=back 5=rear-left 6=left 7=front-left
@export var tex_front: Texture2D
@export var tex_front_right: Texture2D
@export var tex_right: Texture2D
@export var tex_rear_right: Texture2D
@export var tex_back: Texture2D
@export var tex_rear_left: Texture2D
@export var tex_left: Texture2D
@export var tex_front_left: Texture2D

## Каталог с покадровой анимацией. Пусто — статичный режим (враги).
## Формат: <direction>/<state>/<variant>/frame_NN.png.
@export_dir var frames_dir: String = ""
## Legacy fallbacks for projects that have not migrated to run/<variant>/frame_NN.png yet.
## New animation libraries should leave these fields empty.
@export var movement_frames_subdir: String = ""
@export var movement_frames_prefix: String = "walk"
## Optional replacement for the front-facing movement series. This allows the front
## direction to use a separately selected cycle while the other directions use the subfolder above.
@export_dir var front_movement_frames_dir: String = ""
@export var front_movement_frames_prefix: String = "walk"
## Кадров в секунду для анимаций покоя и ходьбы.
@export var idle_fps: float = 6.0
@export var walk_fps: float = 10.0
## Duration of each idle frame. Six frames at 0.18 seconds produce a 1.08-second clip.
## A non-positive duration restores the old continuously looping idle animation.
@export_range(0.0, 10.0, 0.01, "or_greater") var idle_frame_duration: float = 0.18
@export_range(0.0, 10.0, 0.01, "or_greater") var idle_pause_min: float = 0.3
@export_range(0.0, 10.0, 0.01, "or_greater") var idle_pause_max: float = 0.5
## Переиспользует правые кадры для трёх симметричных левых секторов.
## Статичные текстуры остаются уникальными; зеркалятся только серии анимации.
@export var mirror_left_animations := true
@export var default_idle_variant: StringName = &"default"
@export var default_run_variant: StringName = &"default"


var _textures: Array[Texture2D] = []
var _current_index: int = -1

## Загруженные серии кадров по секторам (8 элементов, каждый — Array[Texture2D]).
## Пусты в статичном режиме.
var _idle_frames: Array = []
var _walk_frames: Array = []
var _animation_flip_h: Array[bool] = []
## true — загружена хотя бы одна серия кадров, спрайт работает в анимированном режиме.
var _has_animation: bool = false
## true — проигрывается анимация ходьбы, false — покоя. Ставится игроком через set_moving().
var _is_moving: bool = false
var _frame_index: int = 0
var _frame_timer: float = 0.0
var _idle_is_paused: bool = false
var _idle_pause_timer: float = 0.0
var _idle_rng := RandomNumberGenerator.new()
var _current_animation_state: StringName = &"idle"
var _current_animation_variant: StringName = &"default"
var _named_clip_frames: Dictionary = {}
var _locomotion_requested: bool = false
var _return_to_default_idle_after_cycle: bool = false

## Истинный «базовый» цвет спрайта (расовый/монстровый оттенок), к которому возвращается
## вспышка. Хранится отдельно от modulate, иначе наложение вспышек запоминало бы уже
## подсвеченный (красный) цвет как базовый — и спрайт «застревал» бы в нём.
var _base_modulate: Color = Color.WHITE
var _flash_tween: Tween = null

## Ресурсный кэш живёт вместе с class_name-скриптом, а не с конкретной сценой.
## Без сильных ссылок все 60 кадров игрока освобождались при смене локации и
## синхронно читались заново в _ready() следующего Player.
static var _shared_animation_cache: Dictionary = {}

func _ready() -> void:
	_idle_rng.randomize()
	_current_animation_state = &"idle"
	_current_animation_variant = default_idle_variant
	_textures = [
		tex_front, tex_front_right, tex_right, tex_rear_right,
		tex_back, tex_rear_left, tex_left, tex_front_left,
	]
	_base_modulate = modulate
	if not frames_dir.is_empty():
		_load_animation_frames()
	# _process нужен только для покадровой анимации — врагам (статика) он не тратит время.
	set_process(_has_animation)
	_apply_index(0)  # Старт лицом к камере.
	_start_idle_pause()

## Загружает стандартные idle/run-клипы для всех 8 ракурсов. Остальные варианты
## подгружаются лениво через play_animation_clip().
func _load_animation_frames() -> void:
	var cache_key := "%s|idle=%s|run=%s|movement_subdir=%s|movement_prefix=%s|front_movement=%s|front_prefix=%s|mirror=%s" % [
		frames_dir,
		default_idle_variant,
		default_run_variant,
		movement_frames_subdir,
		movement_frames_prefix,
		front_movement_frames_dir,
		front_movement_frames_prefix,
		str(mirror_left_animations),
	]
	var cached: Variant = _shared_animation_cache.get(cache_key)
	if cached is Dictionary:
		_idle_frames = cached["idle_frames"]
		_walk_frames = cached["walk_frames"]
		_animation_flip_h = cached["flip_h"]
		_has_animation = bool(cached["has_animation"])
		return

	_idle_frames.resize(8)
	_walk_frames.resize(8)
	_animation_flip_h.resize(8)
	var loaded_idle_by_source: Dictionary = {}
	var loaded_walk_by_source: Dictionary = {}
	for sector in 8:
		var source_sector := sector
		var mirror_source := DirectionalSpriteConstants.MIRROR_SOURCE_SECTORS[sector]
		if mirror_left_animations and mirror_source >= 0:
			source_sector = mirror_source
			_animation_flip_h[sector] = true
		else:
			_animation_flip_h[sector] = false
		var idle_series: Array[Texture2D]
		var walk_series: Array[Texture2D]
		if loaded_idle_by_source.has(source_sector):
			idle_series = loaded_idle_by_source[source_sector]
			walk_series = loaded_walk_by_source[source_sector]
		else:
			var dir_path: String = frames_dir.path_join(
				DirectionalSpriteConstants.DIR_FOLDERS[source_sector]
			)
			idle_series = _load_series(
				dir_path.path_join("idle").path_join(String(default_idle_variant)),
				"frame"
			)
			if idle_series.is_empty():
				idle_series = _load_series(dir_path, "idle")
			walk_series = _load_series(
				dir_path.path_join("run").path_join(String(default_run_variant)),
				"frame"
			)
			if walk_series.is_empty() and source_sector == 0 and not front_movement_frames_dir.is_empty():
				walk_series = _load_series(
					front_movement_frames_dir,
					front_movement_frames_prefix
				)
			elif walk_series.is_empty() and not movement_frames_subdir.is_empty():
				walk_series = _load_series(
					dir_path.path_join(movement_frames_subdir),
					movement_frames_prefix
				)
			if walk_series.is_empty():
				walk_series = _load_series(dir_path, "walk")
			loaded_idle_by_source[source_sector] = idle_series
			loaded_walk_by_source[source_sector] = walk_series
		_idle_frames[sector] = idle_series
		_walk_frames[sector] = walk_series
		if not idle_series.is_empty() or not walk_series.is_empty():
			_has_animation = true

	_shared_animation_cache[cache_key] = {
		"idle_frames": _idle_frames,
		"walk_frames": _walk_frames,
		"flip_h": _animation_flip_h,
		"has_animation": _has_animation,
	}

## Грузит нумерованную серию кадров prefix_01.png, prefix_02.png … из каталога [param dir_path],
## пока файлы существуют. Возвращает пустой массив, если ни одного кадра нет.
func _load_series(dir_path: String, prefix: String) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var i: int = 1
	while true:
		var path: String = "%s/%s_%02d.png" % [dir_path, prefix, i]
		if not ResourceLoader.exists(path):
			break
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			break
		frames.append(tex)
		i += 1
	return frames


func _clip_key(state: StringName, variant: StringName) -> String:
	return "%s/%s" % [state, variant]


func _get_clip_frames(state: StringName, variant: StringName) -> Array:
	if state == &"idle" and variant == default_idle_variant:
		return _idle_frames
	if state == &"run" and variant == default_run_variant:
		return _walk_frames
	var key := _clip_key(state, variant)
	if not _named_clip_frames.has(key):
		_named_clip_frames[key] = _load_directional_clip(state, variant)
	return _named_clip_frames[key]


func _load_directional_clip(state: StringName, variant: StringName) -> Array:
	var cache_key := "%s|clip=%s/%s|mirror=%s" % [
		frames_dir,
		state,
		variant,
		str(mirror_left_animations),
	]
	var cached: Variant = _shared_animation_cache.get(cache_key)
	if cached is Array:
		return cached

	var clip_frames: Array = []
	clip_frames.resize(8)
	var loaded_by_source: Dictionary = {}
	for sector in 8:
		var source_sector := sector
		var mirror_source := DirectionalSpriteConstants.MIRROR_SOURCE_SECTORS[sector]
		if mirror_left_animations and mirror_source >= 0:
			source_sector = mirror_source
		if not loaded_by_source.has(source_sector):
			var clip_dir := frames_dir.path_join(
				DirectionalSpriteConstants.DIR_FOLDERS[source_sector]
			).path_join(String(state)).path_join(String(variant))
			loaded_by_source[source_sector] = _load_series(clip_dir, "frame")
		clip_frames[sector] = loaded_by_source[source_sector]
	_shared_animation_cache[cache_key] = clip_frames
	return clip_frames


func has_animation_clip(state: StringName, variant: StringName = &"default") -> bool:
	var clip_frames := _get_clip_frames(state, variant)
	for series: Array[Texture2D] in clip_frames:
		if not series.is_empty():
			return true
	return false


func play_animation_clip(
	state: StringName,
	variant: StringName = &"default",
	restart: bool = true
) -> bool:
	if not has_animation_clip(state, variant):
		return false
	_has_animation = true
	set_process(true)
	if not restart and state == _current_animation_state and variant == _current_animation_variant:
		return true
	_current_animation_state = state
	_current_animation_variant = variant
	_is_moving = state == &"run"
	_return_to_default_idle_after_cycle = false
	_frame_index = 0
	_frame_timer = 0.0
	_idle_is_paused = false
	_idle_pause_timer = 0.0
	if state == &"idle":
		_start_idle_pause()
	animation_changed.emit(state, variant)
	return true


func play_idle_variant(
	variant: StringName,
	restart: bool = true,
	return_to_default: bool = true
) -> bool:
	if not play_animation_clip(&"idle", variant, restart):
		return false
	if variant != default_idle_variant:
		# An explicitly requested ambient action starts immediately and can hand
		# control back to the default intermittent idle after one complete cycle.
		_idle_is_paused = false
		_idle_pause_timer = 0.0
		_return_to_default_idle_after_cycle = return_to_default
	return true


func resume_locomotion_animation() -> bool:
	return play_animation_clip(
		&"run" if _locomotion_requested else &"idle",
		default_run_variant if _locomotion_requested else default_idle_variant
	)

## Разворачивает спрайт по направлению взгляда [param world_dir] (X/Z; Y игнорируется).
## Нулевой вектор сохраняет текущий ракурс.
func face_direction(world_dir: Vector3) -> void:
	if world_dir.length_squared() < 0.0001:
		return
	# atan2(x, z): 0 рад → +Z (front). Делим окружность на 8 секторов по 45°.
	var angle := atan2(world_dir.x, world_dir.z)
	var sector := int(round(angle / (PI / 4.0)))
	sector = ((sector % 8) + 8) % 8
	_apply_index(sector)

## Переключает анимацию между ходьбой ([param moving] = true) и покоем. Смена сбрасывает
## отсчёт кадров, чтобы анимация начиналась с первого кадра. В статичном режиме — no-op.
func set_moving(moving: bool) -> void:
	_locomotion_requested = moving
	if _current_animation_state != &"idle" and _current_animation_state != &"run":
		return
	if (moving and _current_animation_state == &"run") or (
		not moving and _current_animation_state == &"idle"
	):
		return
	resume_locomotion_animation()

func _apply_index(index: int) -> void:
	if index == _current_index:
		return
	_current_index = index
	flip_h = (
		_animation_flip_h[index]
		if _has_animation and index < _animation_flip_h.size()
		else false
	)
	# В статичном режиме текстуру ставим прямо на смене ракурса; в анимированном её каждый
	# кадр обновляет _process по текущей серии.
	if not _has_animation and index < _textures.size() and _textures[index] != null:
		texture = _textures[index]

## Прокручивает покадровую анимацию текущего ракурса. Активен только в анимированном режиме.
func _process(delta: float) -> void:
	var frames: Array[Texture2D] = _current_frames()
	if frames.is_empty():
		return
	if _current_animation_state == &"idle" and idle_frame_duration > 0.0:
		_process_interval_idle(delta, frames)
		frames = _current_frames()
		if frames.is_empty():
			return
		texture = frames[_frame_index]
		return
	_frame_timer += delta
	var frame_dur: float = 1.0 / (idle_fps if _current_animation_state == &"idle" else walk_fps)
	while _frame_timer >= frame_dur:
		_frame_timer -= frame_dur
		_frame_index += 1
		if _frame_index >= frames.size():
			_frame_index = 0
			animation_cycle_finished.emit(
				_current_animation_state,
				_current_animation_variant
			)
	_frame_index %= frames.size()
	texture = frames[_frame_index]


func _process_interval_idle(delta: float, frames: Array[Texture2D]) -> void:
	_frame_index %= frames.size()
	var remaining := maxf(delta, 0.0)
	var frame_duration := maxf(idle_frame_duration, 0.0001)
	while remaining > 0.0:
		if _idle_is_paused:
			_frame_index = 0
			if remaining < _idle_pause_timer:
				_idle_pause_timer -= remaining
				return
			remaining -= _idle_pause_timer
			_idle_pause_timer = 0.0
			_idle_is_paused = false
			_frame_timer = 0.0
			continue

		var until_next_frame := frame_duration - _frame_timer
		if remaining < until_next_frame:
			_frame_timer += remaining
			return
		remaining -= until_next_frame
		_frame_timer = 0.0
		_frame_index += 1
		if _frame_index >= frames.size():
			_frame_index = 0
			animation_cycle_finished.emit(
				_current_animation_state,
				_current_animation_variant
			)
			if _return_to_default_idle_after_cycle:
				_return_to_default_idle_after_cycle = false
				play_animation_clip(&"idle", default_idle_variant)
				return
			_start_idle_pause()


func _start_idle_pause() -> void:
	if idle_frame_duration <= 0.0:
		_idle_is_paused = false
		_idle_pause_timer = 0.0
		return
	_idle_is_paused = true
	_frame_index = 0
	_frame_timer = 0.0
	var pause_from := minf(idle_pause_min, idle_pause_max)
	var pause_to := maxf(idle_pause_min, idle_pause_max)
	_idle_pause_timer = _idle_rng.randf_range(pause_from, pause_to)

## Серия кадров текущего ракурса и состояния (ходьба/покой). Если нужной серии нет —
## откат к другой серии этого ракурса (например, покой при отсутствии ходьбы).
func _current_frames() -> Array[Texture2D]:
	if _current_index < 0 or _current_index >= 8:
		return []
	var clip_frames := _get_clip_frames(
		_current_animation_state,
		_current_animation_variant
	)
	if clip_frames.is_empty():
		return []
	var primary: Array[Texture2D] = clip_frames[_current_index]
	if not primary.is_empty():
		return primary
	var default_variant := (
		default_idle_variant if _current_animation_state == &"idle" else default_run_variant
	)
	if _current_animation_variant != default_variant:
		var fallback_frames := _get_clip_frames(_current_animation_state, default_variant)
		if not fallback_frames.is_empty():
			return fallback_frames[_current_index]
	return []


## Диагностика для автоматической проверки анимаций и инструментов.
func get_animation_frame_count(sector: int, moving: bool) -> int:
	return get_animation_clip_frame_count(
		sector,
		&"run" if moving else &"idle",
		default_run_variant if moving else default_idle_variant
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


func is_animation_sector_mirrored(sector: int) -> bool:
	return (
		sector >= 0
		and sector < _animation_flip_h.size()
		and _animation_flip_h[sector]
	)


## Текущее состояние нужно синхронным слоям экипировки, которые используют те же кадры.
func get_current_sector() -> int:
	return _current_index


func get_current_animation_frame() -> int:
	return _frame_index


func get_current_animation_state() -> StringName:
	return _current_animation_state


func get_current_animation_variant() -> StringName:
	return _current_animation_variant


func get_current_animation_phase() -> float:
	var frames := _current_frames()
	if frames.is_empty() or is_idle_animation_paused():
		return 0.0
	var frame_duration := (
		maxf(idle_frame_duration, 0.0001)
		if _current_animation_state == &"idle" and idle_frame_duration > 0.0
		else 1.0 / maxf(
			idle_fps if _current_animation_state == &"idle" else walk_fps,
			0.0001
		)
	)
	return clampf(
		(float(_frame_index) + _frame_timer / frame_duration) / float(frames.size()),
		0.0,
		0.999999
	)


func is_moving_animation() -> bool:
	return _is_moving


func is_idle_animation_paused() -> bool:
	return _current_animation_state == &"idle" and _idle_is_paused


func get_idle_pause_remaining() -> float:
	return _idle_pause_timer if is_idle_animation_paused() else 0.0

## Устанавливает базовый оттенок спрайта (расовый/монстровый). Вспышки возвращаются
## именно к нему. Вызывай вместо прямого присваивания modulate для стойкого цвета.
func set_tint(color: Color) -> void:
	_base_modulate = color
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = color

## Затемняет базовый оттенок на [param amount] (0..1) с заданной [param alpha] —
## например, для визуального «трупа» павшего союзника.
func darken_base(amount: float, alpha: float = 1.0) -> void:
	var c: Color = _base_modulate.darkened(amount)
	c.a = alpha
	set_tint(c)

## Кратко подсвечивает спрайт цветом [param color], затем плавно возвращает базовый
## оттенок (_base_modulate). Прерывает предыдущую вспышку, поэтому серия ударов не
## оставляет спрайт «застрявшим» в цвете вспышки.
func flash(color: Color, duration: float = 0.15) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", _base_modulate, duration)
