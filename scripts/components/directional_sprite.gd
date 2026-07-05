## 2.5D-спрайт персонажа с переключением по 8 ракурсам.
## Выбирает текстуру по направлению взгляда в мировых координатах X/Z.
## Камера фиксирована (без поворота по Y), поэтому мировое направление = экранному:
## +Z — к камере (front), -Z — от камеры (back), +X — вправо, -X — влево.
## Билборд FIXED_Y держит спрайт вертикально и развёрнутым к камере.
## Используется и игроком, и врагами — направление подаётся через face_direction().
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

var _textures: Array[Texture2D] = []
var _current_index: int = -1

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
	_apply_index(0)  # Старт лицом к камере.

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

func _apply_index(index: int) -> void:
	if index == _current_index:
		return
	_current_index = index
	if index < _textures.size() and _textures[index] != null:
		texture = _textures[index]

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
