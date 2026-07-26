## 2.5D-спрайт персонажа с переключением по 8 ракурсам.
## Выбирает текстуру по направлению взгляда в мировых координатах X/Z.
## Камера фиксирована (без поворота по Y), поэтому мировое направление = экранному:
## +Z — к камере (front), -Z — от камеры (back), +X — вправо, -X — влево.
## Билборд FIXED_Y держит спрайт вертикально и развёрнутым к камере.
## Используется и игроком, и врагами — направление подаётся через face_direction().
##
## Поддерживает два режима:
## - Статичный: одна текстура на ракурс (tex_front и т.д.). Так работают враги.
## - Анимированный: если задан frames_dir, на каждый ракурс грузятся серии кадров
##   idle_NN.png / walk_NN.png, и спрайт проигрывает покадровую анимацию, переключаясь
##   между покоем и ходьбой по set_moving(). Так работает главный герой/союзники.
extends Sprite3D
class_name DirectionalSprite3D

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

## Каталог с покадровой анимацией. Пусто — статичный режим (враги). Внутри ожидаются
## подпапки по именам ракурсов (см. DIR_FOLDERS), в каждой — кадры idle_01.png…, walk_01.png…
@export_dir var frames_dir: String = ""
## Кадров в секунду для анимаций покоя и ходьбы.
@export var idle_fps: float = 6.0
@export var walk_fps: float = 10.0


var _textures: Array[Texture2D] = []
var _current_index: int = -1

## Загруженные серии кадров по секторам (8 элементов, каждый — Array[Texture2D]).
## Пусты в статичном режиме.
var _idle_frames: Array = []
var _walk_frames: Array = []
## true — загружена хотя бы одна серия кадров, спрайт работает в анимированном режиме.
var _has_animation: bool = false
## true — проигрывается анимация ходьбы, false — покоя. Ставится игроком через set_moving().
var _is_moving: bool = false
var _frame_index: int = 0
var _frame_timer: float = 0.0

## Истинный «базовый» цвет спрайта (расовый/монстровый оттенок), к которому возвращается
## вспышка. Хранится отдельно от modulate, иначе наложение вспышек запоминало бы уже
## подсвеченный (красный) цвет как базовый — и спрайт «застревал» бы в нём.
var _base_modulate: Color = Color.WHITE
var _flash_tween: Tween = null

func _ready() -> void:
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

## Грузит серии кадров idle/walk для всех 8 ракурсов из frames_dir. Отсутствие какой-то
## серии не ошибка — на этот ракурс останется откат к статике/другой серии.
func _load_animation_frames() -> void:
	_idle_frames.resize(8)
	_walk_frames.resize(8)
	for sector in 8:
		var dir_path: String = frames_dir.path_join(DirectionalSpriteConstants.DIR_FOLDERS[sector])
		var idle_series: Array[Texture2D] = _load_series(dir_path, "idle")
		var walk_series: Array[Texture2D] = _load_series(dir_path, "walk")
		_idle_frames[sector] = idle_series
		_walk_frames[sector] = walk_series
		if not idle_series.is_empty() or not walk_series.is_empty():
			_has_animation = true

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
	if moving == _is_moving:
		return
	_is_moving = moving
	_frame_index = 0
	_frame_timer = 0.0

func _apply_index(index: int) -> void:
	if index == _current_index:
		return
	_current_index = index
	# В статичном режиме текстуру ставим прямо на смене ракурса; в анимированном её каждый
	# кадр обновляет _process по текущей серии.
	if not _has_animation and index < _textures.size() and _textures[index] != null:
		texture = _textures[index]

## Прокручивает покадровую анимацию текущего ракурса. Активен только в анимированном режиме.
func _process(delta: float) -> void:
	var frames: Array[Texture2D] = _current_frames()
	if frames.is_empty():
		return
	_frame_timer += delta
	var frame_dur: float = 1.0 / (walk_fps if _is_moving else idle_fps)
	while _frame_timer >= frame_dur:
		_frame_timer -= frame_dur
		_frame_index = (_frame_index + 1) % frames.size()
	_frame_index %= frames.size()
	texture = frames[_frame_index]

## Серия кадров текущего ракурса и состояния (ходьба/покой). Если нужной серии нет —
## откат к другой серии этого ракурса (например, покой при отсутствии ходьбы).
func _current_frames() -> Array[Texture2D]:
	if _current_index < 0 or _current_index >= 8:
		return []
	var primary: Array[Texture2D] = _walk_frames[_current_index] if _is_moving else _idle_frames[_current_index]
	if not primary.is_empty():
		return primary
	return _idle_frames[_current_index] if _is_moving else _walk_frames[_current_index]

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
