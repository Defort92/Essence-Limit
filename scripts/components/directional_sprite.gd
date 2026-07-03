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

func _ready() -> void:
	_textures = [
		tex_front, tex_front_right, tex_right, tex_rear_right,
		tex_back, tex_rear_left, tex_left, tex_front_left,
	]
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

## Кратко подсвечивает спрайт цветом [param color], затем плавно возвращает
## тот modulate, что был активен на момент вызова (сохраняет расовый/монстровый оттенок).
## Используется как дешёвая обратная связь по урону/лечению/бафам без спрайтовых анимаций.
func flash(color: Color, duration: float = 0.15) -> void:
	var base_color: Color = modulate
	modulate = color
	var tween := create_tween()
	tween.tween_property(self, "modulate", base_color, duration)
