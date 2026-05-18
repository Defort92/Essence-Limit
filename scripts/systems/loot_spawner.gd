## Слушает сигнал loot_dropped от всех врагов и спавнит ItemPickup-узлы в текущей сцене.
## Является Autoload-синглтоном; регистрировать как "LootSpawner" в Project Settings.
##
## Золото падает отдельным ItemPickup (gold_amount > 0, item = null).
## Предметы — по одному ItemPickup на каждый элемент массива items.
## Все дропы разбрасываются случайно в радиусе SPREAD_RADIUS от позиции гибели.
extends Node

## Радиус разброса предметов вокруг точки гибели врага (в единицах мира).
const SPREAD_RADIUS: float = 0.6
## Смещение по Y — чтобы пикапы не проваливались сквозь пол при спавне.
const SPAWN_Y_OFFSET: float = 0.1

## Подписывает врага на систему лута. Вызывается из Enemy._ready().
func register_enemy(enemy: Enemy) -> void:
	enemy.loot_dropped.connect(_on_loot_dropped)

# ─── Внутренняя логика ─────────────────────────────────────────────────────

func _on_loot_dropped(items: Array, gold: int, at_position: Vector3) -> void:
	var parent := _get_spawn_parent()
	if parent == null:
		return

	if gold > 0:
		_spawn_gold(parent, gold, at_position)

	for item in items:
		if item is ItemData:
			_spawn_item(parent, item, at_position)

func _spawn_gold(parent: Node, gold: int, origin: Vector3) -> void:
	var pickup := ItemPickup.new()
	pickup.gold_amount = gold
	_add_with_collision(parent, pickup, origin)

func _spawn_item(parent: Node, item: ItemData, origin: Vector3) -> void:
	var pickup := ItemPickup.new()
	pickup.item = item
	pickup.quantity = 1
	_add_with_collision(parent, pickup, origin)

## Добавляет ItemPickup в сцену со сферическим коллайдером и случайным смещением.
func _add_with_collision(parent: Node, pickup: ItemPickup, origin: Vector3) -> void:
	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	pickup.add_child(col)
	parent.add_child(pickup)
	pickup.global_position = origin + _random_offset()

func _random_offset() -> Vector3:
	return Vector3(
		randf_range(-SPREAD_RADIUS, SPREAD_RADIUS),
		SPAWN_Y_OFFSET,
		randf_range(-SPREAD_RADIUS, SPREAD_RADIUS)
	)

func _get_spawn_parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.current_scene
