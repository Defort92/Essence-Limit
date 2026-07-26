## Слушает сигнал loot_dropped от всех врагов и спавнит обыскиваемое тело (LootableCorpse)
## в текущей сцене на месте гибели. Игрок подходит и обыскивает его по клавише F —
## золото и предметы забираются через экран лута (см. loot_ui.gd), а не подбираются с земли.
## Является Autoload-синглтоном; регистрировать как "LootSpawner" в Project Settings.
extends Node


## Подписывает врага на систему лута. Вызывается из Enemy._ready().
## Враг привязан как доп. аргумент — обработчик читает его спрайт для визуального трупа
## (сигнал испускается синхронно в _die() до queue_free, так что враг ещё валиден).
func register_enemy(enemy: Enemy) -> void:
	enemy.loot_dropped.connect(_on_loot_dropped.bind(enemy))

# ─── Внутренняя логика ─────────────────────────────────────────────────────

func _on_loot_dropped(items: Array, gold: int, at_position: Vector3, enemy: Enemy) -> void:
	if gold <= 0 and items.is_empty():
		return
	var parent := _get_spawn_parent()
	if parent == null:
		return

	var corpse := LootableCorpse.new()
	corpse.loot_gold = gold
	corpse.loot_items = _aggregate_items(items)
	corpse.corpse_name = "Останки"
	if is_instance_valid(enemy):
		var visual: Dictionary = enemy.get_death_visual()
		corpse.corpse_texture = visual.texture
		corpse.corpse_tint = visual.tint
	parent.add_child(corpse)
	corpse.global_position = at_position + Vector3(0.0, LootSpawnerConstants.SPAWN_Y_OFFSET, 0.0)

## Сворачивает список ItemData в записи { "item", "quantity" }, объединяя одинаковые id.
func _aggregate_items(items: Array) -> Array:
	var by_id: Dictionary = {}
	var order: Array = []
	for item in items:
		if not (item is ItemData):
			continue
		if by_id.has(item.id):
			by_id[item.id].quantity += 1
		else:
			by_id[item.id] = { "item": item, "quantity": 1 }
			order.append(item.id)
	var result: Array = []
	for id in order:
		result.append(by_id[id])
	return result

func _get_spawn_parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.current_scene
