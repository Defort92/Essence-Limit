## Всплывающее боевое число (урон/лечение) в мировом пространстве над существом.
## Билборд-текст, живёт ~LIFETIME секунд, затем исчезает.
## Анимация появления: быстрый подскок вверх; у крита — короткое дрожание.
## Анимация исчезания: в последней трети жизни число гаснет (alpha→0) и падает вниз.
## Цвета/размер по типу: обычный урон — белый; крит урона — красный; лечение — зелёное;
## крит лечения — зелёное того же цвета, но крупнее. Крит всегда крупнее обычного числа.
extends Label3D
class_name FloatingCombatText

enum Kind { HIT, HIT_CRIT, HEAL, HEAL_CRIT }

## Полное время жизни числа (сек) — «буквально пару секунд».
const LIFETIME: float = 1.4
## Высота подскока при появлении (мировые единицы).
const RISE_HEIGHT: float = 0.7
## Дистанция падения вниз на фазе исчезания.
const FALL_DISTANCE: float = 0.9
## Доля жизни, после которой число начинает гаснуть и падать.
const FADE_START: float = 0.55
## Длительность дрожания при появлении (только крит), сек.
const SHAKE_TIME: float = 0.28
## Амплитуда дрожания крита (мировые единицы).
const SHAKE_AMPLITUDE: float = 0.09

const BASE_FONT_SIZE: int = 32
const CRIT_FONT_SIZE: int = 46
## Шрифт интерфейса — чтобы цифры совпадали по стилю с остальным UI (не дефолтный шрифт).
const UI_FONT_PATH: String = "res://assets/fonts/DotGothic16-Regular.ttf"

var _elapsed: float = 0.0
var _anchor: Vector3 = Vector3.ZERO
var _is_crit: bool = false

## Спавнит число [param amount] типа [param kind] над мировой точкой [param world_pos].
## [param host] — любой узел в дереве (по нему находим текущую сцену для добавления).
static func spawn(host: Node, world_pos: Vector3, amount: int, kind: int) -> void:
	if host == null or not host.is_inside_tree():
		return
	var text := FloatingCombatText.new()
	text._configure(amount, kind)
	# Небольшой случайный сдвиг по X, чтобы серия чисел не наложилась в одну точку.
	text._anchor = world_pos + Vector3(randf_range(-0.25, 0.25), 0.0, 0.0)
	var root: Node = host.get_tree().current_scene
	if root == null:
		root = host.get_tree().root
	root.add_child(text)
	text.global_position = text._anchor

func _configure(amount: int, kind: int) -> void:
	text = str(amount)
	var ui_font: Font = load(UI_FONT_PATH)
	if ui_font != null:
		font = ui_font
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fixed_size = true
	no_depth_test = true
	shaded = false
	double_sided = true
	# 0.002: при font_size 32/46 цифры выходят заметно меньше спрайта персонажа.
	pixel_size = 0.002
	outline_size = 6
	outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	render_priority = 10
	outline_render_priority = 9
	_is_crit = kind == Kind.HIT_CRIT or kind == Kind.HEAL_CRIT
	font_size = CRIT_FONT_SIZE if _is_crit else BASE_FONT_SIZE
	match kind:
		Kind.HIT:       modulate = Color(1.0, 1.0, 1.0)
		Kind.HIT_CRIT:  modulate = Color(1.0, 0.2, 0.2)
		Kind.HEAL:      modulate = Color(0.3, 1.0, 0.4)
		Kind.HEAL_CRIT: modulate = Color(0.3, 1.0, 0.4)

func _process(delta: float) -> void:
	_elapsed += delta
	var p: float = _elapsed / LIFETIME
	if p >= 1.0:
		queue_free()
		return
	# Вертикаль: быстрый подскок в первые 30% жизни (ease-out).
	var rise: float = RISE_HEIGHT * _ease_out(minf(p / 0.3, 1.0))
	var fall: float = 0.0
	var alpha: float = 1.0
	if p > FADE_START:
		var fp: float = (p - FADE_START) / (1.0 - FADE_START)
		fall = FALL_DISTANCE * fp * fp
		alpha = 1.0 - fp
	# Дрожание только на появлении крита, затухает к концу SHAKE_TIME.
	var shake_x: float = 0.0
	var shake_y: float = 0.0
	if _is_crit and _elapsed < SHAKE_TIME:
		var decay: float = 1.0 - _elapsed / SHAKE_TIME
		shake_x = randf_range(-1.0, 1.0) * SHAKE_AMPLITUDE * decay
		shake_y = randf_range(-1.0, 1.0) * SHAKE_AMPLITUDE * decay
	global_position = _anchor + Vector3(shake_x, rise - fall + shake_y, 0.0)
	_set_alpha(alpha)

func _set_alpha(a: float) -> void:
	var c: Color = modulate
	c.a = a
	modulate = c
	var o: Color = outline_modulate
	o.a = a * 0.85
	outline_modulate = o

func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)
