## Периодически спавнит рядовых врагов рядом с собой, поддерживая на локации не больше
## max_alive живых экземпляров. Добавляй как узел в сцену локации (город, стартовая зона).
## Заспавненные враги живут в родителе спавнера (в общем пространстве сцены), а не под ним,
## чтобы навигация и таргетинг работали как у обычных врагов сцены.
extends Node3D
class_name MobSpawner

## Сцена врага (обычно scenes/characters/enemy_base.tscn). Её корень должен быть Enemy.
@export var enemy_scene: PackedScene
## Конфиг врага, назначаемый на data заспавненного Enemy (обычно .tres из resources/enemies).
@export var enemy_data: EnemyData
## Интервал между спавнами, сек.
@export var spawn_interval: float = 6.0
## Максимум одновременно живых врагов от этого спавнера.
@export var max_alive: int = 4
## Радиус случайного разброса точек спавна вокруг спавнера.
@export var spawn_radius: float = 6.0
## Задержка перед первым спавном, сек.
@export var initial_delay: float = 3.0
## Заполнить сразу до max_alive при старте (иначе набор постепенный по таймеру).
@export var prewarm: bool = false

var _timer: float = 0.0
var _alive: Array[Node] = []

func _ready() -> void:
	_timer = initial_delay
	if prewarm:
		for i in max_alive:
			_spawn_one()

func _process(delta: float) -> void:
	_prune()
	if _alive.size() >= max_alive:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_spawn_one()

## Убирает из учёта врагов, которых уже нет (умерли и освобождены).
func _prune() -> void:
	var live: Array[Node] = []
	for e in _alive:
		if is_instance_valid(e):
			live.append(e)
	_alive = live

func _spawn_one() -> void:
	if enemy_scene == null:
		push_error("MobSpawner '%s': enemy_scene не назначен" % name)
		return
	var enemy := enemy_scene.instantiate()
	if enemy is Enemy and enemy_data != null:
		(enemy as Enemy).data = enemy_data
	var angle: float = randf() * TAU
	var dist: float = randf_range(spawn_radius * 0.3, spawn_radius)
	var offset := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	var container: Node = get_parent()
	if container == null:
		container = self
	container.add_child(enemy)
	if enemy is Node3D:
		(enemy as Node3D).global_position = global_position + offset
	_alive.append(enemy)
