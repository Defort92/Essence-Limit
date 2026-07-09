## Миникарта: схематичный вид локации сверху (проекция XZ) с центром на активном игроке.
## Игрок — оранжевая точка со свечением, враги — красные точки, участники отряда — светлые,
## NPC и прочие объекты локации (группа "minimap_object") — золотистые квадраты,
## обыскиваемые тела (группа "lootable") — мелкие золотые точки.
## Стилизована под остальной HUD: тёмная штрихованная подложка с золотой рамкой.
extends Control
class_name Minimap

## Радиус мира (в метрах), укладывающийся в половину меньшей стороны миникарты.
## Всё, что дальше от игрока, на карту не попадает.
@export var world_radius: float = 25.0

const BG_COLOR: Color = Color(0.031, 0.024, 0.027, 0.7)
const STRIPE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.03)
const BORDER_COLOR: Color = Color(0.471, 0.376, 0.212, 0.4)
const PLAYER_COLOR: Color = Color(0.949, 0.573, 0.267)
const PARTY_COLOR: Color = Color(0.878, 0.698, 0.416)
const ENEMY_COLOR: Color = Color(0.85, 0.25, 0.2)
const OBJECT_COLOR: Color = Color(0.62, 0.54, 0.42, 0.9)
const LOOT_COLOR: Color = Color(0.93, 0.79, 0.36)

## Шаг и толщина диагональной штриховки фона, px.
const STRIPE_STEP: float = 14.0
const STRIPE_WIDTH: float = 6.0
## Внутренний отступ: маркеры ближе этого расстояния к рамке не рисуются.
const EDGE_MARGIN: float = 5.0

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	_draw_backdrop()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var center: Vector3 = player.global_position
	# Пикселей на метр: радиус мира вписывается в половину меньшей стороны.
	var ppm: float = minf(size.x, size.y) * 0.5 / world_radius

	# Объекты локации (NPC, порталы и т.п.) — золотистые квадраты.
	for node in get_tree().get_nodes_in_group("minimap_object"):
		var obj := node as Node3D
		if obj == null:
			continue
		var pos: Vector2 = _world_to_map(obj.global_position, center, ppm)
		if _on_map(pos):
			draw_rect(Rect2(pos - Vector2(2, 2), Vector2(4, 4)), OBJECT_COLOR)

	# Обыскиваемые тела — мелкие золотые точки.
	for node in get_tree().get_nodes_in_group("lootable"):
		var corpse := node as Node3D
		if corpse == null:
			continue
		var pos: Vector2 = _world_to_map(corpse.global_position, center, ppm)
		if _on_map(pos):
			draw_circle(pos, 1.5, LOOT_COLOR)

	# Враги — красные точки (мёртвых не показываем).
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.state == Enemy.State.DEAD:
			continue
		var pos: Vector2 = _world_to_map(enemy.global_position, center, ppm)
		if _on_map(pos):
			draw_circle(pos, 2.5, ENEMY_COLOR)

	# Остальные участники отряда — светлые точки.
	for node in get_tree().get_nodes_in_group("party"):
		var member := node as Node3D
		if member == null or member == player:
			continue
		var pos: Vector2 = _world_to_map(member.global_position, center, ppm)
		if _on_map(pos):
			draw_circle(pos, 2.5, PARTY_COLOR)

	# Активный игрок — в центре, со свечением.
	var player_pos: Vector2 = size * 0.5
	draw_circle(player_pos, 8.0, Color(PLAYER_COLOR, 0.18))
	draw_circle(player_pos, 5.5, Color(PLAYER_COLOR, 0.42))
	draw_circle(player_pos, 3.5, PLAYER_COLOR)

## Тёмная подложка с диагональной штриховкой и золотой рамкой (как на панелях HUD).
func _draw_backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	# Диагонали под 45°: собственная отрисовка обрезается clip_contents.
	var t: float = -size.y
	while t < size.x:
		draw_line(Vector2(t, size.y), Vector2(t + size.y, 0.0), STRIPE_COLOR, STRIPE_WIDTH)
		t += STRIPE_STEP
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 1.0)

## Проекция мировой позиции (XZ) в координаты миникарты относительно центра (игрока).
func _world_to_map(world: Vector3, center: Vector3, ppm: float) -> Vector2:
	return size * 0.5 + Vector2(world.x - center.x, world.z - center.z) * ppm

## Точка достаточно далеко от рамки, чтобы маркер не налезал на неё.
func _on_map(pos: Vector2) -> bool:
	return pos.x >= EDGE_MARGIN and pos.y >= EDGE_MARGIN \
		and pos.x <= size.x - EDGE_MARGIN and pos.y <= size.y - EDGE_MARGIN
