## Автокаст способностей эссенций для врага. Добавляется дочерним узлом на сцену Enemy;
## список способностей берёт из EnemyData.ability_scenes родителя.
## Эвристика первой итерации: способность кастуется, как только она не на кулдауне,
## а враг в бою (CHASE/ATTACK) и цель в радиусе detection_range.
## Не переиспользует AbilityManager — тот заточен под клавиши и одного игрока.
extends Node
class_name EnemyAbilityController

## Пауза между попытками каста (сек), чтобы не перебирать способности каждый кадр.
const CAST_ATTEMPT_INTERVAL: float = 0.5

var _enemy: Enemy = null
var _abilities: Array[AbilityBase] = []
var _attempt_timer: float = 0.0

func _ready() -> void:
	_enemy = get_parent() as Enemy
	if _enemy == null:
		push_error("EnemyAbilityController: родитель '%s' не Enemy" % get_parent().name)
		return
	# data может быть ещё не назначен (Enemy сам репортит эту ошибку).
	if _enemy.data == null:
		return
	for scene: PackedScene in _enemy.data.ability_scenes:
		if scene == null:
			continue
		var ability := scene.instantiate() as AbilityBase
		if ability == null:
			push_error("EnemyAbilityController: сцена '%s' не содержит AbilityBase" % scene.resource_path)
			continue
		ability.caster = _enemy
		add_child(ability)
		_abilities.append(ability)

func _physics_process(delta: float) -> void:
	if _enemy == null or _abilities.is_empty():
		return
	_attempt_timer -= delta
	if _attempt_timer > 0.0:
		return
	_attempt_timer = CAST_ATTEMPT_INTERVAL
	if not _is_in_combat():
		return
	for ability in _abilities:
		if ability.try_activate():
			return  # Один каст за попытку — не вываливаем все скиллы разом.

## Враг считается в бою, когда он преследует/атакует живую цель в радиусе обнаружения.
func _is_in_combat() -> bool:
	if _enemy.state != Enemy.State.CHASE and _enemy.state != Enemy.State.ATTACK:
		return false
	var target: Node3D = _enemy.get_target()
	if target == null:
		return false
	return _enemy.global_position.distance_to(target.global_position) <= _enemy.get_stat("detection_range")
