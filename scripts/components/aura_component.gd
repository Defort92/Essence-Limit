## Пассивный эффект в радиусе: накладывает StatModifier на всех существ в зоне.
## Снимает модификаторы при выходе существа из зоны или при удалении компонента.
## Добавляй как дочерний узел к этажу подземелья (глобальная аура) или к персонажу/боссу.
extends Node3D
class_name AuraComponent

@export var radius: float = 5.0
@export var modifiers: Array[StatModifier] = []
## Как часто (сек) обновлять список существ в зоне. Меньше = точнее, но дороже.
@export var tick_interval: float = 0.5
@export var affects_player: bool = true
@export var affects_enemies: bool = false

var _tick_timer: float = 0.0
var _affected: Array[Node3D] = []
## Уникальный ID источника, используется при снятии модификаторов через remove_modifiers_by_source().
var _source_id: String = ""

func _ready() -> void:
	_source_id = "aura_%d" % get_instance_id()

func _physics_process(delta: float) -> void:
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = tick_interval
		_update_affected()

func _update_affected() -> void:
	var candidates: Array[Node3D] = _gather_candidates()
	var still_inside: Array[Node3D] = []

	for candidate in candidates:
		if not is_instance_valid(candidate):
			continue
		if global_position.distance_to(candidate.global_position) <= radius:
			still_inside.append(candidate)

	for entity in _affected:
		if entity not in still_inside and is_instance_valid(entity):
			_remove_from(entity)

	for entity in still_inside:
		if entity not in _affected:
			_apply_to(entity)

	_affected = still_inside

func _gather_candidates() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if affects_player:
		for node in get_tree().get_nodes_in_group("player"):
			result.append(node as Node3D)
	if affects_enemies:
		for node in get_tree().get_nodes_in_group("enemies"):
			result.append(node as Node3D)
	return result

func _apply_to(entity: Node3D) -> void:
	if not entity.has_method("apply_modifier"):
		return
	for modifier in modifiers:
		# Копируем модификатор, чтобы не делить один объект между несколькими целями.
		var mod_copy := StatModifier.new()
		mod_copy.stat = modifier.stat
		mod_copy.op = modifier.op
		mod_copy.value = modifier.value
		mod_copy.source_id = _source_id
		entity.apply_modifier(mod_copy)

func _remove_from(entity: Node3D) -> void:
	if entity.has_method("remove_modifiers_by_source"):
		entity.remove_modifiers_by_source(_source_id)

func _exit_tree() -> void:
	for entity in _affected:
		if is_instance_valid(entity):
			_remove_from(entity)
	_affected.clear()
