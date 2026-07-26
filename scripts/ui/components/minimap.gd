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
			draw_rect(Rect2(pos - Vector2(2, 2), Vector2(4, 4)), MinimapConstants.OBJECT_COLOR)

	# Обыскиваемые тела — мелкие золотые точки.
	for node in get_tree().get_nodes_in_group("lootable"):
		var corpse := node as Node3D
		if corpse == null:
			continue
		var pos: Vector2 = _world_to_map(corpse.global_position, center, ppm)
		if _on_map(pos):
			draw_circle(pos, 1.5, MinimapConstants.LOOT_COLOR)

	# Враги — красные точки (мёртвых не показываем).
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.state == Enemy.State.DEAD:
			continue
		var pos: Vector2 = _world_to_map(enemy.global_position, center, ppm)
		if _on_map(pos):
			draw_circle(pos, 2.5, MinimapConstants.ENEMY_COLOR)

	# Остальные участники отряда — светлые точки.
	for node in get_tree().get_nodes_in_group("party"):
		var member := node as Node3D
		if member == null or member == player:
			continue
		var pos: Vector2 = _world_to_map(member.global_position, center, ppm)
		if _on_map(pos):
			draw_circle(pos, 2.5, MinimapConstants.PARTY_COLOR)

	# Активный игрок — в центре, со свечением.
	var player_pos: Vector2 = size * 0.5
	draw_circle(player_pos, 8.0, Color(MinimapConstants.PLAYER_COLOR, 0.18))
	draw_circle(player_pos, 5.5, Color(MinimapConstants.PLAYER_COLOR, 0.42))
	draw_circle(player_pos, 3.5, MinimapConstants.PLAYER_COLOR)

## Тёмная подложка с диагональной штриховкой и золотой рамкой (как на панелях HUD).
func _draw_backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), MinimapConstants.BG_COLOR)
	# Диагонали под 45°: собственная отрисовка обрезается clip_contents.
	var t: float = -size.y
	while t < size.x:
		draw_line(Vector2(t, size.y), Vector2(t + size.y, 0.0), MinimapConstants.STRIPE_COLOR, MinimapConstants.STRIPE_WIDTH)
		t += MinimapConstants.STRIPE_STEP
	draw_rect(Rect2(Vector2.ZERO, size), MinimapConstants.BORDER_COLOR, false, 1.0)

## Проекция мировой позиции (XZ) в координаты миникарты относительно центра (игрока).
func _world_to_map(world: Vector3, center: Vector3, ppm: float) -> Vector2:
	return size * 0.5 + Vector2(world.x - center.x, world.z - center.z) * ppm

## Точка достаточно далеко от рамки, чтобы маркер не налезал на неё.
func _on_map(pos: Vector2) -> bool:
	return pos.x >= MinimapConstants.EDGE_MARGIN and pos.y >= MinimapConstants.EDGE_MARGIN \
		and pos.x <= size.x - MinimapConstants.EDGE_MARGIN and pos.y <= size.y - MinimapConstants.EDGE_MARGIN
