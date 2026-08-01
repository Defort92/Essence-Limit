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

const SPAWN_POSITION_ATTEMPTS: int = 16
const SPAWN_BODY_CLEARANCE: float = 0.15
const SPAWN_CAPSULE_HEIGHT: float = 1.8
const COMBAT_BODY_MASK: int = 2 | 4

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

func _spawn_one() -> bool:
	if enemy_scene == null:
		push_error("MobSpawner '%s': enemy_scene не назначен" % name)
		return false
	var collision_radius := enemy_data.collision_radius if enemy_data != null else 0.4
	var spawn_position := _find_free_spawn_position(collision_radius)
	if spawn_position == Vector3.INF:
		# Не создаём врага внутри персонажа. Таймер сделает следующую попытку позже,
		# когда место около спавнера освободится.
		return false
	var enemy := enemy_scene.instantiate()
	if enemy is Enemy and enemy_data != null:
		(enemy as Enemy).data = enemy_data
	var container: Node = get_parent()
	if container == null:
		container = self
	# Позиция задаётся до add_child: _ready() врага не должен даже на один кадр
	# выполняться в точке спавнера и пересекаться с находящимся там персонажем.
	if enemy is Node3D and container is Node3D:
		(enemy as Node3D).position = (container as Node3D).to_local(spawn_position)
	container.add_child(enemy)
	if enemy is Node3D and not container is Node3D:
		(enemy as Node3D).global_position = spawn_position
	_alive.append(enemy)
	return true


## Ищет случайную точку, в которой капсула нового врага не пересекает ни игрока,
## ни союзника, ни уже существующего врага. Если все попытки заняты, спавн откладывается.
func _find_free_spawn_position(collision_radius: float) -> Vector3:
	for _attempt in SPAWN_POSITION_ATTEMPTS:
		var angle: float = randf() * TAU
		var dist: float = randf_range(spawn_radius * 0.3, spawn_radius)
		var candidate := global_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		if _is_spawn_position_clear(candidate, collision_radius):
			return candidate
	return Vector3.INF


## Отдельный helper оставлен доступным тестам и будущим особым спавнерам.
func _is_spawn_position_clear(world_position: Vector3, collision_radius: float) -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return false
	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(0.05, collision_radius + SPAWN_BODY_CLEARANCE)
	capsule.height = maxf(SPAWN_CAPSULE_HEIGHT, capsule.radius * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, world_position + Vector3.UP * SPAWN_CAPSULE_HEIGHT * 0.5)
	query.collision_mask = COMBAT_BODY_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
